# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025-2026, by Samuel Williams.

require "console"
require "process/metrics/host/memory"
require_relative "monitor"

module Memory
	module Leak
		# Detects memory leaks in a cluster of processes.
		#
		# This class is used to manage a cluster of processes and detect memory leaks in each process.
		# It can also enforce cluster-wide memory limits in two ways:
		# 
		# 1. **Total Size Limit** (`total_size_limit`): Limits the total memory used by all processes
		#    in the cluster, calculated as max(shared memory) + sum(private memory).
		# 
		# 2. **Free Size Minimum** (`free_size_minimum`): Ensures the host system maintains a minimum
		#    amount of free memory by terminating processes when free memory drops too low.
		#
		# Both limits can be active simultaneously. Processes are terminated in order of largest
		# private memory first to maximize the impact of each termination.
		class Cluster
			# Create a new cluster.
			#
			# @parameter total_size_limit [Numeric | Nil] The total memory limit for the cluster.
			# @parameter free_size_minimum [Numeric | Nil] The minimum free memory required on the host, in bytes.
			def initialize(total_size_limit: nil, free_size_minimum: nil)
				@total_size = nil
				@total_size_limit = total_size_limit
				@free_size_minimum = free_size_minimum
				
				@processes = {}
			end
			
			# @returns [Hash] A serializable representation of the cluster.
			def as_json(...)
				{
					total_size: @total_size,
					total_size_limit: @total_size_limit,
					free_size_minimum: @free_size_minimum,
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
			
			# @attribute [Numeric | Nil] The minimum free memory required on the host, in bytes. If free memory falls below this minimum, the cluster will terminate processes.
			attr_accessor :free_size_minimum
			
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
			
			# Enforce the total size memory limit on the cluster. If the total memory usage exceeds the limit, yields each process ID and monitor in order of maximum memory usage, so that they could be terminated and/or removed.
			#
			# This method terminates processes (largest private memory first) until the total cluster memory
			# usage drops below the limit. Total cluster memory usage is calculated as:
			# 
			#   total_size = max(shared memory usages) + sum(private memory usages)
			# 
			# This accounts for shared memory being counted only once across all processes, as shared memory
			# regions (e.g., loaded libraries) are mapped into multiple processes but only consume memory once.
			# 
			# The calculation uses the initially computed maximum shared size throughout the termination loop
			# for performance, even though terminating processes might change which process has the maximum
			# shared size. This approximation is acceptable for enforcement purposes.
			#
			# Termination stops when `total_size <= total_size_limit`, where `total_size` is incrementally
			# updated by subtracting each terminated process's private memory contribution.
			#
			# @parameter total_size_limit [Numeric] The maximum total memory allowed for the cluster, in bytes.
			# @parameter block [Proc] Required block to handle process termination.
			# @yields {|process_id, monitor, total_size| ...} each process ID and monitor in order of decreasing private memory size.
			# 	@parameter process_id [Integer] The process ID to terminate.
			# 	@parameter monitor [Monitor] The monitor for the process.
			# 	@parameter total_size [Integer] The current estimated total cluster memory usage, in bytes. Updated incrementally after each termination.
			# @raises [ArgumentError] if no block is provided.
			# @returns [Boolean] Returns true if processes were yielded for termination, false otherwise.
			protected def enforce_total_size_limit!(total_size_limit = @total_size_limit, &block)
				# Only processes with known private size can be considered:
				monitors = @processes.values.select do |monitor|
					monitor.current_private_size != nil
				end
				
				maximum_shared_size = monitors.map(&:current_shared_size).max || 0
				sum_private_size = monitors.map(&:current_private_size).sum
				
				@total_size = maximum_shared_size + sum_private_size
				
				host_memory = Process::Metrics::Host::Memory.capture
				
				if @total_size > total_size_limit
					Console.warn(self, "Total memory usage exceeded limit.", total_size: @total_size, total_size_limit: total_size_limit, maximum_shared_size: maximum_shared_size, sum_private_size: sum_private_size, host_memory: host_memory)
				else
					Console.info(self, "Total memory usage within limit.", total_size: @total_size, total_size_limit: total_size_limit, maximum_shared_size: maximum_shared_size, sum_private_size: sum_private_size, host_memory: host_memory)
					return false
				end
				
				# Only process monitors where we can compute private size:
				monitors.sort_by! do |monitor|
					-monitor.current_private_size
				end
				
				monitors.each do |monitor|
					if @total_size > total_size_limit
						# Capture private size before yielding (process may be removed):
						private_size = monitor.current_private_size
						
						yield(monitor.process_id, monitor, @total_size)
						
						# Incrementally update total size by subtracting this process's private memory contribution.
						# We keep the previously computed maximum_shared_size for performance,
						# even though the maximum may shift to a different process after termination.
						sum_private_size -= private_size
						
						@total_size = maximum_shared_size + sum_private_size
					else
						break
					end
				end
			end
			
			# Enforce the minimum free memory requirement. If free memory falls below the minimum, yields each process ID and monitor in order of maximum memory usage, so that they could be terminated and/or removed.
			#
			# This method terminates processes (largest private memory first) until the estimated free memory
			# rises above the minimum threshold. The free memory calculation is approximate:
			# - Free memory is captured once at the start
			# - Expected freed memory is estimated by summing terminated process private memory sizes
			# - The OS may not immediately release all private memory to the free pool
			# - Other system processes may allocate memory concurrently
			#
			# Termination stops when `free_memory + freed_private_size >= free_size_minimum`, where
			# `freed_private_size` is the sum of private memory from all terminated processes.
			#
			# @parameter free_size_minimum [Numeric] The minimum free memory required, in bytes.
			# @parameter block [Proc] Required block to handle process termination.
			# @yields {|process_id, monitor, free_memory| ...} each process ID and monitor in order of decreasing private memory size.
			# 	@parameter process_id [Integer] The process ID to terminate.
			# 	@parameter monitor [Monitor] The monitor for the process.
			# 	@parameter free_memory [Integer] The estimated current free memory (initial free + sum of freed private memory so far), in bytes. This is an estimate and may not reflect actual system state.
			# @raises [ArgumentError] if no block is provided.
			# @returns [Boolean] Returns true if processes were yielded for termination, false otherwise.
			protected def enforce_free_size_minimum!(free_size_minimum = @free_size_minimum, &block)
				return false unless free_size_minimum
				
				host_memory = Process::Metrics::Host::Memory.capture
				return false unless host_memory
				
				free_size = host_memory.free_size
				
				if free_size < free_size_minimum
					Console.warn(self, "Free memory below minimum.", free_size: free_size, free_size_minimum: free_size_minimum, host_memory: host_memory)
				else
					Console.info(self, "Free memory above minimum.", free_size: free_size, free_size_minimum: free_size_minimum, host_memory: host_memory)
					return false
				end
				
				# Only processes with known private size can be considered:
				monitors = @processes.values.select do |monitor|
					monitor.current_private_size != nil
				end
				
				# Sort by private memory size (descending) to terminate largest processes first:
				monitors.sort_by! do |monitor|
					-monitor.current_private_size
				end
				
				# Track how much private memory we've freed by terminating processes.
				# Note: This is an estimate based on process private memory sizes.
				# Actual free memory may differ due to OS memory management and other processes.
				freed_private_size = 0
				
				monitors.each do |monitor|
					if free_size + freed_private_size < free_size_minimum
						# Capture private size before yielding (process may be removed):
						private_size = monitor.current_private_size
						
						yield(monitor.process_id, monitor, free_size + freed_private_size)
						
						# Incrementally track freed memory:
						freed_private_size += private_size
					else
						break
					end
				end
			end
			
			# Sample the memory usage of all processes in the cluster.
			def sample!
				@processes.each_value(&:sample!)
			end
			
			# Check all processes in the cluster for memory leaks.
			#
			# @yields {|process_id, monitor| ...} each process ID and monitor that is leaking or exceeds the memory limit.
			def check!(&block)
				self.sample!
				
				leaking = []
				
				@processes.each do |process_id, monitor|
					if monitor.leaking?
						Console.debug(self, "Memory Leak Detected!", process_id: process_id, monitor: monitor)
						
						leaking << [process_id, monitor]
					end
				end
				
				if block_given?
					leaking.each(&block)
					
					# Finally, enforce any per-cluster memory limits:
					if @total_size_limit
						enforce_total_size_limit!(@total_size_limit, &block)
					end
					
					# Enforce minimum free memory requirement:
					if @free_size_minimum
						enforce_free_size_minimum!(@free_size_minimum, &block)
					end
				end
				
				return leaking
			end
		end
	end
end
