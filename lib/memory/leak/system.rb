# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025, by Samuel Williams.

require "console"

module Memory
	module Leak
		module System
			if File.exist?("/proc/meminfo")
				def self.total_memory_size
					File.foreach("/proc/meminfo") do |line|
						if /MemTotal:\s*(?<total>\d+)\s*kB/ =~ line
							return total.to_i * 1024
						end
					end
					
					return nil
				end
			elsif RUBY_PLATFORM =~ /darwin/
				def self.total_memory_size
					IO.popen(["sysctl", "hw.memsize"], "r") do |io|
						io.each_line do |line|
							if /hw.memsize:\s*(?<total>\d+)/ =~ line
								return total.to_i
							end
						end
					end
				end
			end
		end
	end
end
