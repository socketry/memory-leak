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
		class Monitor
			# We only track heap size changes greater than this threshold (KB), across the DEFAULT_INTERVAL.
			# True memory leaks will eventually hit this threshold, while small fluctuations will not.
			DEFAULT_THRESHOLD = 1024*10
			
			# We track the last N heap size increases.
			# If the heap size is not stabilizing within the specified limit, we can assume there is a leak.
			# With a default interval of 10 seconds, this will track the last ~3 minutes of heap size increases.
			DEFAULT_LIMIT = 20
			
			# Create a new monitor.
			#
			# @parameter maximum [Numeric] The initial maximum heap size, from which we willl track increases, in KiB.
			# @parameter threshold [Numeric] The threshold for heap size increases, in KiB.
			# @parameter limit [Numeric] The limit for the number of heap size increases, before we assume a memory leak.
			# @parameter [Integer] The process ID to monitor.
			def initialize(process_id = Process.pid, maximum: nil, threshold: DEFAULT_THRESHOLD, limit: DEFAULT_LIMIT)
				@process_id = process_id
				
				@maximum = maximum
				@threshold = threshold
				@limit = limit
				
				# The number of increasing heap size samples.
				@count = 0
				@current = nil
			end
			
			# @attribute [Integer] The process ID to monitor.
			attr :process_id
			
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
			private def memory_usage
				IO.popen(["ps", "-o", "rss=", @process_id.to_s]) do |io|
					return Integer(io.readlines.last)
				end
			end
			
			# @returns [Integer] The last sampled memory usage.
			def current
				@current ||= memory_usage
			end
			
			# Indicates whether a memory leak has been detected.
			#
			# If the number of increasing heap size samples is greater than or equal to the limit, a memory leak is assumed.
			#
			# @returns [Boolean] True if a memory leak has been detected.
			def leaking?
				@count >= @limit
			end
			
			# Capture a memory usage sample and yield if a memory leak is detected.
			#
			# @yields {|sample, monitor| ...} If a memory leak is detected.
			def sample!
				@current = memory_usage
				
				if @maximum
					delta = @current - @maximum
					Console.debug(self, "Heap size captured.", current: @current, delta: delta, threshold: @threshold, maximum: @maximum)
					
					if delta > @threshold
						@maximum = @current
						@count += 1
						
						Console.debug(self, "Heap size increased.", maximum: @maximum, count: @count)
					end
				else
					Console.debug(self, "Initial heap size captured.", current: @current)
					@maximum = @current
				end
				
				return @current
			end
		end
	end
end
