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
end
