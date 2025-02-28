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
			
			# Get the memory usage of the given process IDs.
			#
			# @parameter process_ids [Array(Integer)] The process IDs to monitor.
			# @returns [Array(Tuple(Integer, Integer))] The memory usage of the given process IDs.
			def self.memory_usages(process_ids)
				IO.popen(["ps", "-o", "pid=,rss=", *process_ids.map(&:to_s)]) do |io|
					io.each_line.map(&:split).map{|process_id, size| [process_id.to_i, size.to_i * 1024]}
				end
			end
			
			# Get the memory usage of the given process IDs.
			#
			# @parameter process_ids [Array(Integer)] The process IDs to monitor.
			# @returns [Array(Tuple(Integer, Integer))] The memory usage of the given process IDs.
			def self.memory_usage(process_id)
				IO.popen(["ps", "-o", "rss=", process_id.to_s]) do |io|
					return io.read.to_i * 1024
				end
			end
		end
	end
end
