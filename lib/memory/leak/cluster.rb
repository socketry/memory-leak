# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025, by Samuel Williams.

require "console"
require_relative "monitor"

module Memory
	module Leak
		# Detects memory leaks by tracking heap size increases.
		#
		# A memory leak is characterised by the memory usage of the application continuing to rise over time. We can detect this by sampling memory usage and comparing it to the previous sample. If the memory usage is higher than the previous sample, we can say that the application has allocated more memory. Eventually we expect to see this stabilize, but if it continues to rise, we can say that the application has a memory leak.
		#
		# We should be careful not to filter historical data, as some memory leaks may only become apparent after a long period of time. Any kind of filtering may prevent us from detecting such a leak.
		class Cluster
			def initialize(limit: nil)
				@limit = limit
				
				@pids = {}
			end
			
			attr_accessor :limit
			
			attr :pids
			
			def add(pid, **options)
				@pids[pid] = Monitor.new(pid, **options)
			end
			
			def remove(pid)
				@pids.delete(pid)
			end
			
			# Apply the memory limit to the cluster. If the total memory usage exceeds the limit, yields each PID and monitor in order of maximum memory usage, so that they could be terminated and/or removed.
			#
			# @yields {|pid, monitor| ...} each process ID and monitor in order of maximum memory usage, return true if it was terminated to adjust memory usage.
			def apply_limit!(limit = @limit)
				total = @pids.values.map(&:current).sum
				
				if total > limit
					Console.warn(self, "Total memory usage exceeded limit.", total: total, limit: limit)
				end
				
				sorted = @pids.sort_by do |pid, monitor|
					-monitor.current
				end
				
				sorted.each do |pid, monitor|
					if total > limit
						if yield pid, monitor, total
							total -= monitor.current
						end
					else
						break
					end
				end
			end
			
			def check!(&block)
				leaking = []
				
				@pids.each do |pid, monitor|
					monitor.sample!
					
					if monitor.leaking?
						Console.debug(self, "Memory Leak Detected!", pid: pid, monitor: monitor)
						
						leaking << [pid, monitor]
					end
				end
				
				leaking.each(&block)
				
				# Finally, apply any per-cluster memory limits:
				apply_limit!(@limit, &block) if @limit
			end
		end
	end
end
