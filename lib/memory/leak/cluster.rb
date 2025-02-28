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
			# @parameter total_size_limit [Numeric | Nil] The total memory limit for the cluster.
			def initialize(total_size_limit: nil)
				@total_size = nil
				@total_size_limit = total_size_limit
				
				@processes = {}
			end
			
			# @returns [Hash] A serializable representation of the cluster.
			def as_json(...)
				{
					total_size: @total_size,
					total_size_limit: @total_size_limit,
					processes: @processes.transform_values(&:as_json),
				}
			end
			
			# @returns [String] The JSON representation of the cluster.
			def to_json(...)
				as_json.to_json(...)
			end
			
			# @attribute [Numeric | Nil] The total size of the cluster.
			attr :total_size
			
			# @attribute [Numeric | Nil] The total size limit for the cluster, in bytes, if which is exceeded, the cluster will terminate processes.
			attr_accessor :total_size_limit
			
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
			def apply_limit!(total_size_limit = @total_size_limit)
				@total_size = @processes.values.map(&:current_size).sum
				
				if @total_size > total_size_limit
					Console.warn(self, "Total memory usage exceeded limit.", total_size: @total_size, total_size_limit: total_size_limit)
				else
					return false
				end
				
				sorted = @processes.sort_by do |process_id, monitor|
					-monitor.current_size
				end
				
				sorted.each do |process_id, monitor|
					if @total_size > total_size_limit
						yield(process_id, monitor, @total_size)
						
						# For the sake of the calculation, we assume that the process has been terminated:
						@total_size -= monitor.current_size
					else
						break
					end
				end
			end
			
			# Sample the memory usage of all processes in the cluster.
			def sample!
				System.memory_usages(@processes.keys).each do |process_id, memory_usage|
					@processes[process_id].current_size = memory_usage
				end
			end
			
			# Check all processes in the cluster for memory leaks.
			#
			# @yields {|process_id, monitor| ...} each process ID and monitor that is leaking or exceeds the memory limit.
			def check!(&block)
				return to_enum(__method__) unless block_given?
				
				self.sample!
				
				leaking = []
				
				@processes.each do |process_id, monitor|
					if monitor.leaking?
						Console.debug(self, "Memory Leak Detected!", process_id: process_id, monitor: monitor)
						
						leaking << [process_id, monitor]
					end
				end
				
				leaking.each(&block)
				
				# Finally, apply any per-cluster memory limits:
				apply_limit!(@total_size_limit, &block) if @total_size_limit
			end
		end
	end
end
