# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025, by Samuel Williams.

require "console"
require_relative "monitor"

module Memory
	module Leak
		# Detects memory leaks in a cluster of processes.
		#
		# This class is used to manage a cluster of processes and detect memory leaks in each process. It can also apply a memory limit to the cluster, and terminate processes if the memory limit is exceeded.
		class Cluster
			# Create a new cluster.
			#
			# @parameter limit [Numeric | Nil] The (total) memory limit for the cluster.
			def initialize(limit: nil)
				@limit = limit
				
				@processes = {}
			end
			
			# @attribute [Numeric | Nil] The memory limit for the cluster.
			attr_accessor :limit
			
			# @attribute [Hash(Integer, Monitor)] The process IDs and monitors in the cluster.
			attr :processes
			
			# Add a new process ID to the cluster.
			def add(process_id, **options)
				@processes[process_id] = Monitor.new(process_id, **options)
			end
			
			# Remove a process ID from the cluster.
			def remove(process_id)
				@processes.delete(process_id)
			end
			
			# Apply the memory limit to the cluster. If the total memory usage exceeds the limit, yields each process ID and monitor in order of maximum memory usage, so that they could be terminated and/or removed.
			#
			# @yields {|process_id, monitor| ...} each process ID and monitor in order of maximum memory usage, return true if it was terminated to adjust memory usage.
			def apply_limit!(limit = @limit)
				total = @processes.values.map(&:current).sum
				
				if total > limit
					Console.warn(self, "Total memory usage exceeded limit.", total: total, limit: limit)
				end
				
				sorted = @processes.sort_by do |process_id, monitor|
					-monitor.current
				end
				
				sorted.each do |process_id, monitor|
					if total > limit
						if yield process_id, monitor, total
							total -= monitor.current
						end
					else
						break
					end
				end
			end
			
			# Check all processes in the cluster for memory leaks.
			#
			# @yields {|process_id, monitor| ...} each process ID and monitor that is leaking or exceeds the memory limit.
			def check!(&block)
				leaking = []
				
				@processes.each do |process_id, monitor|
					monitor.sample!
					
					if monitor.leaking?
						Console.debug(self, "Memory Leak Detected!", process_id: process_id, monitor: monitor)
						
						leaking << [process_id, monitor]
					end
				end
				
				leaking.each(&block)
				
				# Finally, apply any per-cluster memory limits:
				apply_limit!(@limit, &block) if @limit
			end
		end
	end
end
