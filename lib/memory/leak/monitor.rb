# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025, by Samuel Williams.

require "console"
require_relative "system"

module Memory
	module Leak
		# Detects memory leaks by tracking process size increases.
		#
		# A memory leak is characterised by the memory usage of the application continuing to rise over time. We can detect this by sampling memory usage and comparing it to the previous sample. If the memory usage is higher than the previous sample, we can say that the application has allocated more memory. Eventually we expect to see this stabilize, but if it continues to rise, we can say that the application has a memory leak.
		#
		# We should be careful not to filter historical data, as some memory leaks may only become apparent after a long period of time. Any kind of filtering may prevent us from detecting such a leak.
		class Monitor
			# We only track process size changes greater than this threshold_size, across the DEFAULT_INTERVAL.
			# True memory leaks will eventually hit this threshold_size, while small fluctuations will not.
			DEFAULT_THRESHOLD_SIZE = 1024*1024*10
			
			# We track the last N process size increases.
			# If the process size is not stabilizing within the specified increase_limit, we can assume there is a leak.
			# With a default interval of 10 seconds, this will track the last ~3 minutes of process size increases.
			DEFAULT_INCREASE_LIMIT = 20
			
			# Create a new monitor.
			#
			# @parameter process_id [Integer] The process ID to monitor.
			# @parameter maximum_size [Numeric] The initial process size, from which we willl track increases, in bytes.
			# @parameter maximum_size_limit [Numeric | Nil] The maximum process size allowed, in bytes, before we assume a memory leak.
			# @parameter threshold_size [Numeric] The threshold for process size increases, in bytes.
			# @parameter increase_limit [Numeric] The limit for the number of process size increases, before we assume a memory leak.
			def initialize(process_id = Process.pid, maximum_size: nil, maximum_size_limit: nil, threshold_size: DEFAULT_THRESHOLD_SIZE, increase_limit: DEFAULT_INCREASE_LIMIT)
				@process_id = process_id
				
				@sample_count = 0
				@current_size = nil
				@maximum_size = maximum_size
				@maximum_size_limit = maximum_size_limit
				@maximum_observed_size = nil
				
				@threshold_size = threshold_size
				@increase_count = 0
				@increase_limit = increase_limit
			end
			
			# @returns [Hash] A serializable representation of the cluster.
			def as_json(...)
				{
					process_id: @process_id,
					sample_count: @sample_count,
					current_size: @current_size,
					maximum_size: @maximum_size,
					maximum_size_limit: @maximum_size_limit,
					threshold_size: @threshold_size,
					increase_count: @increase_count,
					increase_limit: @increase_limit,
				}
			end
			
			# @returns [String] The JSON representation of the cluster.
			def to_json(...)
				as_json.to_json(...)
			end
			
			# @attribute [Integer] The process ID to monitor.
			attr :process_id
			
			# @attribute [Numeric] The maximum process size observed.
			attr_accessor :maximum_size
			
			# @attribute [Numeric | Nil] The maximum process size allowed, before we assume a memory leak.
			attr_accessor :maximum_size_limit
			
			# @attribute [Numeric] The threshold_size for process size increases.
			attr_accessor :threshold_size
			
			# @attribute [Integer] The number of increasing process size samples. 
			attr_accessor :increase_count
			
			# @attribute [Numeric] The limit for the number of process size increases, before we assume a memory leak.
			attr_accessor :increase_limit
			
			# @returns [Integer] Ask the system for the current memory usage.
			def memory_usage
				System.memory_usage(@process_id)
			end
			
			# @attribute [Integer] The number of samples taken.
			attr :sample_count
			
			# @returns [Integer] The last sampled memory usage.
			def current_size
				@current_size ||= memory_usage
			end
			
			# Set the current memory usage, rather than sampling it.
			def current_size=(value)
				@current_size = value
			end
			
			# Indicates whether a memory leak has been detected.
			#
			# If the number of increasing heap size samples is greater than or equal to the increase_limit, a memory leak is assumed.
			#
			# @returns [Boolean] True if a memory leak has been detected.
			def increase_limit_exceeded?
				@increase_count >= @increase_limit
			end
			
			# Indicates that the current memory usage has grown beyond the maximum size limit.
			#
			# @returns [Boolean] True if the current memory usage has grown beyond the maximum size limit.
			def maximum_size_limit_exceeded?
				@maximum_size_limit && self.current_size > @maximum_size_limit
			end
			
			# Indicates whether a memory leak has been detected.
			#
			# @returns [Boolean] True if a memory leak has been detected.
			def leaking?
				increase_limit_exceeded? || maximum_size_limit_exceeded?
			end
			
			# Capture a memory usage sample and yield if a memory leak is detected.
			#
			# @yields {|sample, monitor| ...} If a memory leak is detected.
			def sample!(memory_usage = self.memory_usage)
				@sample_count += 1
				
				self.current_size = memory_usage
				
				if @maximum_observed_size
					delta = @current_size - @maximum_observed_size
					Console.debug(self, "Heap size captured.", current_size: @current_size, delta: delta, threshold_size: @threshold_size, maximum_observed_size: @maximum_observed_size)
					
					if delta > @threshold_size
						@maximum_observed_size = @current_size
						@increase_count += 1
						
						Console.debug(self, "Heap size increased.", maximum_observed_size: @maximum_observed_size, count: @count)
					end
				else
					Console.debug(self, "Initial heap size captured.", current_size: @current_size)
					@maximum_observed_size = @current_size
				end
				
				return @current_size
			end
		end
	end
end
