# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025, by Samuel Williams.

require "memory/leak/detector"
require "memory/leak/a_leaking_process"

describe Memory::Leak::Detector do
	let(:detector) {subject.new}
	
	with "#sample!" do
		it "can capture samples" do
			3.times do
				expect(detector.sample!).to be_a(Integer)
			end
			
			# It is very unlikely that in the above test, the threshold of the 2nd and 3rd samples will be greater than the threshold of the 1st sample.
			# Therefore, the count should be 0.
			expect(detector.count).to be == 0
		end
		
		with "a leaking child process" do
			include_context Memory::Leak::ALeakingProcess
			let(:detector) {subject.new(pid: @child.pid, limit: 10)}
			
			it "can detect memory leaks" do
				@child.wait_for_message("ready")
				
				# The child process may have an initial heap which allocations will use up before the heap is increased, so we need to consume that first:
				until detector.count > 0
					@child.write_message(action: "allocate", size: detector.threshold * 1024)
					@child.wait_for_message("allocated")
					detector.sample!
				end
				
				until detector.leaking?
					# The threshold is measured in KiB, so multiply by 1024 to get the threshold in bytes + 1 to ensure that the threshold is exceeded:
					@child.write_message(action: "allocate", size: detector.threshold * 1024 + 1)
					@child.wait_for_message("allocated")
					
					# Capture a sample of the memory usage:
					detector.sample!
				end
				
				expect(detector.count).to be == detector.limit
				expect(detector).to be(:leaking?)
			end
		end
	end
end
