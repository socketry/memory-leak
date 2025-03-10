# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025, by Samuel Williams.

require "memory/leak/monitor"
require "memory/leak/a_leaking_process"

describe Memory::Leak::Monitor do
	let(:monitor) {subject.new}
	
	with "#as_json" do
		it "generates a JSON representation" do
			expect(monitor.as_json).to have_keys(
				process_id: be_a(Integer),
				current_size: be_nil,
				maximum_size: be_nil,
				maximum_size_limit: be_nil,
				threshold_size: be_a(Integer),
				increase_count: be == 0,
				increase_limit: be_a(Integer)
			)
		end
		
		it "generates a JSON string" do
			expect(JSON.dump(monitor)).to be == monitor.to_json
		end
	end
	
	with "#sample!" do
		it "can capture samples" do
			3.times do
				expect(monitor.sample!).to be_a(Integer)
			end
			
			# It is very unlikely that in the above test, the threshold of the 2nd and 3rd samples will be greater than the threshold of the 1st sample.
			# Therefore, the count should be 0.
			expect(monitor.increase_count).to be == 0
		end
		
		with "a leaking child process" do
			include_context Memory::Leak::ALeakingProcess
			let(:monitor) {subject.new(@child.process_id, increase_limit: 10)}
			
			it "can detect memory leaks" do
				@child.wait_for_message("ready")
				
				# The child process may have an initial heap which allocations will use up before the heap is increased, so we need to consume that first:
				until monitor.increase_count > 0
					@child.write_message(action: "allocate", size: monitor.threshold_size)
					@child.wait_for_message("allocated")
					monitor.sample!
				end
				
				until monitor.leaking?
					@child.write_message(action: "allocate", size: monitor.threshold_size + 1)
					@child.wait_for_message("allocated")
					
					# Capture a sample of the memory usage:
					monitor.sample!
				end
				
				expect(monitor.increase_count).to be == monitor.increase_limit
				expect(monitor).to be(:leaking?)
			end
		end
	end
end
