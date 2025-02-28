# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025, by Samuel Williams.

require "memory/leak/system"

describe Memory::Leak::System do
	with ".total_memory_size" do
		it "can determine the total memory size" do
			expect(subject.total_memory_size).to be_a(Integer)
		end
	end
	
	with ".memory_usage" do
		it "can determine the memory usage" do
			expect(subject.memory_usage(Process.pid)).to be_a(Integer)
		end
		
		it "returns 0 for invalid process ID" do
			expect(subject.memory_usage(0)).to be == 0
		end
	end
	
	with ".memory_usages" do
		it "can determine the memory usages of no processes" do
			result = subject.memory_usages([])
			
			expect(result).to be_a(Enumerator)
			expect(result.to_a).to be(:empty?)
		end
		
		it "can determine the memory usages" do
			pids = 3.times.map{Process.spawn("sleep 1")}
			
			result = subject.memory_usages(pids)
			
			result.each do |process_id, size|
				expect(pids).to be(:include?, process_id)
				expect(process_id).to be_a(Integer)
				expect(size).to be_a(Integer)
			end
		ensure
			pids.each do |pid|
				Process.kill(:TERM, pid)
				Process.wait(pid)
			end
		end
		
		it "ignores invalid process IDs" do
			result = subject.memory_usages([Process.pid, 0])
			
			result.each do |process_id, size|
				expect(process_id).to be_a(Integer)
				expect(size).to be > 0
			end
		end
	end
end
