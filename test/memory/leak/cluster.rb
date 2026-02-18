# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025, by Samuel Williams.

require "memory/leak/cluster"
require "memory/leak/a_leaking_process"

require "sus/fixtures/console"

describe Memory::Leak::Cluster do
	include Sus::Fixtures::Console::CapturedLogger
	
	let(:cluster) {subject.new}
	
	with "#as_json" do
		it "generates a JSON representation" do
			expect(cluster.as_json).to have_keys(
				processes: be_a(Hash),
				total_size: be_nil,
				total_size_limit: be_nil,
			)
		end
		
		it "generates a JSON string" do
			expect(JSON.dump(cluster)).to be == cluster.to_json
		end
	end
	
	with "a leaking child process" do
		before do
			@children = 3.times.map do
				child = Memory::Leak::LeakingChild.new
				monitor = cluster.add(child.process_id, increase_limit: 10)
				
				[child.process_id, child]
			end.to_h
		end
		
		after do
			@children&.each_value do |child|
				child.close
			end
		end
		
		attr :children
		
		it "samples memory usage" do
			cluster.check!.to_a
			
			children.each do |process_id, child|
				monitor = cluster.processes[process_id]
				expect(monitor).to have_attributes(
					sample_count: be > 0,
					current_size: be_a(Integer),
				)
			end
		end
		
		it "can detect memory leaks" do
			child = children.values.first
			monitor = cluster.processes[child.process_id]
			
			# Force the first child to trigger the memory leak:
			until monitor.leaking?
				child.write_message(action: "allocate", size: monitor.threshold_size + 1)
				child.wait_for_message("allocated")
				
				# Capture a sample of the memory usage:
				monitor.sample!
			end
			
			expect(monitor).to have_attributes(
				sample_count: be > 0,
			)
			
			cluster.check! do |process_id, monitor|
				expect(process_id).to be == child.process_id
				expect(monitor.increase_count).to be == monitor.increase_limit
				expect(monitor).to be(:leaking?)
				
				child.close
				children.delete(process_id)
				cluster.remove(process_id)
			end
			
			expect(cluster.processes.keys).to be == children.keys
		ensure
			children.each_value do |child|
				child.close
			end
		end
		
		it "can apply memory limit" do
			# 100 MiB limit:
			cluster.total_size_limit = 1024*1024*100
			
			expect(cluster.check!.to_a).to be(:empty?)
			
			big_child = children.values.first
			big_monitor = cluster.processes[big_child.process_id]
			small_child = children.values.last
			small_monitor = cluster.processes[small_child.process_id]
			
			big_allocation = (cluster.total_size_limit * 0.8).floor - big_monitor.current_size
			if big_allocation > 0
				big_child.write_message(action: "allocate", size: big_allocation)
				big_child.wait_for_message("allocated")
			end
			
			small_allocation = (cluster.total_size_limit * 0.2).floor - small_monitor.current_size
			if small_allocation > 0
				small_child.write_message(action: "allocate", size: small_allocation)
				small_child.wait_for_message("allocated")
			end
			
			# Sample to update memory stats after allocation:
			cluster.sample!
			
			# Find the process with the largest private memory (this is what apply_limit! will terminate):
			biggest_process_id, biggest_monitor = cluster.processes.max_by do |process_id, monitor|
				monitor.current_private_size || 0
			end
			
			# The total memory usage is 110% of the limit, so processes should be terminated:
			terminated_processes = []
			cluster.check! do |process_id, monitor, total_size|
				# The first process yielded should be the one with the largest private memory:
				if terminated_processes.empty?
					expect(process_id).to be == biggest_process_id
				end
				expect(monitor).not.to be(:leaking?)
				terminated_processes << process_id
				
				# Close the child process that was terminated:
				if child = children[process_id]
					child.close
					children.delete(process_id)
				end
				cluster.remove(process_id)
			end
			
			# At least one process should have been terminated:
			expect(terminated_processes.size).to be > 0
			
			expect_console.to have_logged(
				severity: be == :warn,
				message: be == "Total memory usage exceeded limit."
			)
		end
		
		it "returns false when memory is within limit" do
			# Set a very high limit that won't be exceeded:
			cluster.total_size_limit = 1024*1024*1024*100 # 100 GB
			
			# Sample to get current memory stats:
			cluster.sample!
			
			yielded = false
			cluster.check! do |process_id, monitor, total_size|
				yielded = true
			end
			
			# No processes should be yielded since we're within the limit:
			expect(yielded).to be == false
			
			expect_console.to have_logged(
				severity: be == :info,
				message: be == "Total memory usage within limit."
			)
		end
		
		it "stops terminating once memory drops below limit" do
			# Sample to get initial memory stats:
			cluster.sample!
			
			# Create a big size difference by allocating a lot in one process:
			big_child = children.values[0]
			medium_child = children.values[1]
			small_child = children.values[2]
			
			big_monitor = cluster.processes[big_child.process_id]
			medium_monitor = cluster.processes[medium_child.process_id]
			small_monitor = cluster.processes[small_child.process_id]
			
			# Allocate 40MB in the big child:
			big_child.write_message(action: "allocate", size: 40*1024*1024)
			big_child.wait_for_message("allocated")
			
			# Allocate 5MB in medium child:
			medium_child.write_message(action: "allocate", size: 5*1024*1024)
			medium_child.wait_for_message("allocated")
			
			# Don't allocate in small child
			
			# Sample to get updated stats:
			cluster.sample!
			
			# Get the sizes:
			max_shared = cluster.processes.values.map(&:current_shared_size).compact.max || 0
			big_private = big_monitor.current_private_size || 0
			medium_private = medium_monitor.current_private_size || 0
			small_private = small_monitor.current_private_size || 0
			sum_private = big_private + medium_private + small_private
			
			# Set limit between (max_shared + medium + small) and (max_shared + big + medium + small):
			# This ensures removing big drops us below the limit
			cluster.total_size_limit = max_shared + medium_private + small_private + (big_private / 2)
			
			# Verify we're over the limit initially:
			current_total = max_shared + sum_private
			expect(current_total).to be > cluster.total_size_limit
			
			# Save the big child's PID before we close it:
			big_child_pid = big_child.process_id
			
			# Now check - should terminate the big child, then stop (break):
			terminated_pids = []
			cluster.check! do |process_id, monitor, total_size|
				terminated_pids << process_id
				
				# Close and remove the process:
				if child = children[process_id]
					child.close
					children.delete(process_id)
				end
				cluster.remove(process_id)
			end
			
			# Should have terminated exactly the big child:
			expect(terminated_pids.size).to be == 1
			expect(terminated_pids).to be(:include?, big_child_pid)
			
			# Should have 2 processes remaining (break prevented terminating all):
			expect(cluster.processes.size).to be == 2
		end
	end
end
