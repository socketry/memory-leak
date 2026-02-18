# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025-2026, by Samuel Williams.

require "console"

module Memory
	module Leak
		# System-specific memory information.
		module System
			# Threshold for distinguishing actual memory limits from "unlimited" sentinel values in cgroups v1.
			# 
			# In cgroups v1, when memory.limit_in_bytes is set to unlimited (by writing -1),
			# the kernel stores a very large sentinel value close to 2^63 (approximately 9,223,372,036,854,771,712 bytes).
			# Since no real system would have 1 exabyte (2^60 bytes) of RAM, any value >= this threshold
			# indicates an "unlimited" configuration and should be treated as if no limit is set.
			#
			# This allows us to distinguish between:
			# - Actual container memory limits: typically in GB-TB range (< 1 EB)
			# - Unlimited sentinel values: near 2^63 (>> 1 EB)
			#
			# Reference: https://www.kernel.org/doc/Documentation/cgroup-v1/memory.txt
			CGROUP_V1_UNLIMITED_THRESHOLD = 2**60 # ~1 exabyte
			
			# Determine the total memory size in bytes. This is the maximum amount of memory that can be used by the current process. If running in a container, this may be limited by the container runtime (e.g. cgroups).
			#
			# @returns [Integer] The total memory size in bytes.
			def self.total_memory_size
				# Check for Kubernetes/cgroup memory limit first (cgroups v2):
				if File.exist?("/sys/fs/cgroup/memory.max")
					limit = File.read("/sys/fs/cgroup/memory.max").strip
					# "max" means unlimited, fall through to other methods:
					if limit != "max"
						return limit.to_i
					end
				end
				
				# Check for Kubernetes/cgroup memory limit (cgroups v1):
				if File.exist?("/sys/fs/cgroup/memory/memory.limit_in_bytes")
					limit = File.read("/sys/fs/cgroup/memory/memory.limit_in_bytes").strip.to_i
					# A very large number means unlimited, fall through:
					if limit > 0 && limit < CGROUP_V1_UNLIMITED_THRESHOLD
						return limit
					end
				end
				
				# Fall back to Linux system memory detection:
				if File.exist?("/proc/meminfo")
					File.foreach("/proc/meminfo") do |line|
						if /MemTotal:\s*(?<total>\d+)\s*kB/ =~ line
							return total.to_i * 1024
						end
					end
				end
				
				# Fall back to macOS memory detection:
				if RUBY_PLATFORM =~ /darwin/
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
				return to_enum(__method__, process_ids) unless block_given?
				
				if process_ids.any?
					IO.popen(["ps", "-o", "pid=,rss=", "-p", process_ids.join(",")]) do |io|
						io.each_line.map(&:split).each do |process_id, size|
							yield process_id.to_i, size.to_i * 1024
						end
					end
				end
			end
			
			# Get the memory usage of the given process IDs.
			#
			# @parameter process_ids [Array(Integer)] The process IDs to monitor.
			# @returns [Array(Tuple(Integer, Integer))] The memory usage of the given process IDs.
			def self.memory_usage(process_id)
				IO.popen(["ps", "-o", "rss=", "-p", process_id.to_s]) do |io|
					return io.read.to_i * 1024
				end
			end
		end
	end
end
