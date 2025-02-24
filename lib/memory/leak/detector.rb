# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025, by Samuel Williams.

require "console"

module Memory
	module Leak
		# Detects memory leaks by tracking heap size increases.
		#
		# A memory leak is characterised by the memory usage of the application continuing to rise over time. We can detect this by sampling memory usage and comparing it to the previous sample. If the memory usage is higher than the previous sample, we can say that the application has allocated more memory. Eventually we expect to see this stabilize, but if it continues to rise, we can say that the application has a memory leak.
		#
		# We should be careful not to filter historical data, as some memory leaks may only become apparent after a long period of time. Any kind of filtering may prevent us from detecting such a leak.
		class Detector
			# We only track heap size changes greater than this threshold (KB), across the DEFAULT_INTERVAL.
			# True memory leaks will eventually hit this threshold, while small fluctuations will not.
			DEFAULT_THRESHOLD = 1024*10
			
			# We track the last N heap size increases.
			# If the heap size is not stabilizing within the specified limit, we can assume there is a leak.
			# With a default interval of 10 seconds, this will track the last ~3 minutes of heap size increases.
			DEFAULT_LIMIT = 20
			
			# Create a new detector.
			#
			# @parameter maximum [Numeric] The initial maximum heap size, from which we willl track increases, in KiB.
			# @parameter threshold [Numeric] The threshold for heap size increases, in KiB.
			# @parameter limit [Numeric] The limit for the number of heap size increases, before we assume a memory leak.
			# @pid [Integer] The process ID to monitor.
			def initialize(maximum: nil, threshold: DEFAULT_THRESHOLD, limit: DEFAULT_LIMIT, pid: Process.pid)
				@maximum = maximum
				@threshold = threshold
				@limit = limit
				@pid = pid
				
				# The number of increasing heap size samples.
				@count = 0
			end
			
			# @attribute [Numeric] The current maximum heap size.
			attr :maximum
			
			# @attribute [Numeric] The threshold for heap size increases.
			attr :threshold
			
			# @attribute [Numeric] The limit for the number of heap size increases, before we assume a memory leak.
			attr :limit
			
			# @attribute [Integer] The number of increasing heap size samples. 
			attr :count
			
			# The current resident set size (RSS) of the process.
			#
			# Even thought the absolute value of this number may not very useful, the relative change is useful for detecting memory leaks, and it works on most platforms.
			#
			# @returns [Numeric] Memory usage size in KiB.
			def memory_usage(pid = @pid)
				IO.popen(["ps", pid.to_s, "-o", "rss="]) do |io|
					return Integer(io.readlines.last)
				end
			end
			
			def memory_leak_detected?
				@count >= @limit
			end
			
			# Capture a memory usage sample and yield if a memory leak is detected.
			#
			# @yields {|sample, detector| ...} If a memory leak is detected.
			def capture_sample
				sample = memory_usage
				
				if @maximum
					delta = sample - @maximum
					Console.debug(self, "Heap size captured.", sample: sample, delta: delta, threshold: @threshold, maximum: @maximum)
					
					if delta > @threshold
						@maximum = sample
						@count += 1
						
						Console.debug(self, "Heap size increased.", maximum: @maximum, count: @count)
					end
				else
					Console.debug(self, "Initial heap size captured.", sample: sample)
					@maximum = sample
				end
				
				return sample
			end
		end
	end
end
