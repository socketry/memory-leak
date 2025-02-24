# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025, by Samuel Williams.

require "memory/leak/cluster"
require "memory/leak/a_leaking_process"

require "sus/fixtures/console"

describe Memory::Leak::Cluster do
	include Sus::Fixtures::Console::CapturedLogger
	
	let(:cluster) {subject.new}
	
	with "a leaking child process" do
		before do
			@children = 3.times.map do
				child = Memory::Leak::LeakingChild.new
				monitor = cluster.add(child.pid, limit: 10)
				
				[child.pid, child]
			end.to_h
		end
		
		after do
			@children.each_value do |child|
				child.close
			end
		end
		
		attr :children
		
		it "can detect memory leaks" do
			child = children.values.first
			monitor = cluster.pids[child.pid]
			
			# Force the first child to trigger the memory leak:
			until monitor.leaking?
				child.write_message(action: "allocate", size: monitor.threshold * 1024 + 1)
				child.wait_for_message("allocated")
				
				# Capture a sample of the memory usage:
				monitor.sample!
			end
			
			cluster.check! do |pid, monitor|
				expect(pid).to be == child.pid
				expect(monitor.count).to be == monitor.limit
				expect(monitor).to be(:leaking?)
				
				child.close
				children.delete(pid)
				cluster.remove(pid)
			end
			
			expect(cluster.pids.keys).to be == children.keys
		ensure
			children.each_value do |child|
				child.close
			end
		end
		
		it "can apply memory limit" do
			# 100 MiB limit:
			cluster.limit = 1024*100
			
			big_child = children.values.first
			small_child = children.values.last
			
			big_child.write_message(action: "allocate", size: (cluster.limit * 0.8 * 1024).floor)
			big_child.wait_for_message("allocated")
			
			small_child.write_message(action: "allocate", size: (cluster.limit * 0.3 * 1024).floor)
			small_child.wait_for_message("allocated")
			
			# The total memory usage is 110% of the limit, so the biggest child should be terminated:
			cluster.check! do |pid, monitor|
				expect(pid).to be == big_child.pid
				expect(monitor).not.to be(:leaking?)
				
				big_child.close
				children.delete(pid)
				cluster.remove(pid)
				
				true
			end
			
			expect_console.to have_logged(
				severity: be == :warn,
				message: be == "Total memory usage exceeded limit."
			)
		end
	end
end
