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
			
			# The total memory usage is 110% of the limit, so the biggest child should be terminated:
			cluster.check! do |process_id, monitor, total_size|
				expect(process_id).to be == big_child.process_id
				expect(monitor).not.to be(:leaking?)
				
				big_child.close
				children.delete(process_id)
				cluster.remove(process_id)
			end
			
			expect_console.to have_logged(
				severity: be == :warn,
				message: be == "Total memory usage exceeded limit."
			)
		end
	end
end
