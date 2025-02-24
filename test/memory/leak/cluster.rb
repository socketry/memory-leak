# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025, by Samuel Williams.

require "memory/leak/cluster"
require "memory/leak/a_leaking_process"

describe Memory::Leak::Cluster do
	let(:cluster) {subject.new}
	
	with "a leaking child process" do
		it "can detect memory leaks" do
			children = 3.times.map do
				child = Memory::Leak::LeakingChild.new
				detector = cluster.add(child.pid, limit: 10)
				
				[child.pid, child]
			end.to_h
			
			child = children.values.first
			detector = cluster.pids[child.pid]
			
			# Force the first child to trigger the memory leak:
			until detector.leaking?
				child.write_message(action: "allocate", size: detector.threshold * 1024 + 1)
				child.wait_for_message("allocated")
				
				# Capture a sample of the memory usage:
				detector.sample!
			end
			
			cluster.check! do |pid, detector|
				expect(pid).to be == child.pid
				expect(detector.count).to be == detector.limit
				expect(detector).to be(:leaking?)
				
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
	end
end
