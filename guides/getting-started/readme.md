# Getting Started

This guide explains how to use `memory-leak` to detect and prevent memory leaks in your Ruby applications.

## Installation

Add the gem to your project:

``` bash
$ bundle add memory-leak
```

## What is Memory Leak Detection?

Memory leaks occur when your application continuously allocates memory without releasing it, leading to growing memory usage over time. This eventually causes performance degradation or application crashes. The `memory-leak` gem helps you detect these issues by monitoring process memory usage and identifying problematic patterns.

Use `memory-leak` when you need:
- **Leak Detection**: Automatically identify processes with continuously increasing memory usage.
- **Memory Limits**: Enforce cluster-wide total memory limits to prevent excessive resource consumption.
- **System Protection**: Maintain minimum free memory on the host system to prevent out-of-memory conditions.
- **Process Management**: Terminate problematic processes before they impact service availability.

## Core Concepts

### Monitor

A `Monitor` tracks memory usage for a single process. It samples memory periodically and detects when memory usage continues to increase beyond acceptable thresholds.

### Cluster

A `Cluster` manages multiple process monitors and enforces memory policies across all processes. It provides two types of limits:

1. **Total Size Limit**: Caps the combined memory usage of all processes.
2. **Free Size Minimum**: Ensures the host maintains adequate free memory.

## Usage

### Monitoring a Single Process

Create a monitor to track memory usage for a specific process:

``` ruby
require "memory/leak"

# Monitor the current process
monitor = Memory::Leak::Monitor.new(Process.pid)

# Sample memory usage periodically (e.g., every 10 seconds)
loop do
	monitor.sample!
	
	if monitor.leaking?
		puts "Memory leak detected!"
		puts "Current size: #{monitor.current_size} bytes"
		puts "Maximum size: #{monitor.maximum_size} bytes"
		puts "Increase count: #{monitor.increase_count}/#{monitor.increase_limit}"
		
		# Take action: restart process, alert operators, etc.
		break
	end
	
	sleep 10
end
```

### Managing a Process Cluster

When managing multiple worker processes, use a `Cluster` to monitor all of them:

``` ruby
require "memory/leak"

cluster = Memory::Leak::Cluster.new

# Add workers to the cluster
worker_pids = [12345, 12346, 12347]
worker_pids.each do |pid|
	cluster.add(pid, increase_limit: 10)
end

# Check for leaks across all processes
cluster.check! do |process_id, monitor|
	puts "Process #{process_id} is leaking memory!"
	
	# Terminate the leaking process
	Process.kill("TERM", process_id)
	
	# Remove from cluster
	cluster.remove(process_id)
	
	# Spawn replacement worker...
end
```

## Enforcing Memory Limits

### Total Cluster Memory Limit

Prevent your application cluster from consuming too much total memory:

``` ruby
cluster = Memory::Leak::Cluster.new(
	total_size_limit: 1024 * 1024 * 1024 * 4  # 4 GB total
)

# Add worker processes
worker_pids.each{|pid| cluster.add(pid)}

# Check limits and terminate processes if exceeded
cluster.check! do |process_id, monitor, total_size|
	puts "Total memory (#{total_size} bytes) exceeded limit"
	puts "Terminating process #{process_id} (#{monitor.current_private_size} bytes private)"
	
	Process.kill("TERM", process_id)
	cluster.remove(process_id)
end
```

When the total cluster memory exceeds the limit, `check!` yields processes in order of largest private memory first. This maximizes the impact of each termination. The cluster automatically stops terminating processes once memory drops below the limit.

### Minimum Free Memory

Ensure your host system maintains adequate free memory:

``` ruby
cluster = Memory::Leak::Cluster.new(
	free_size_minimum: 1024 * 1024 * 1024 * 2  # Keep at least 2 GB free
)

worker_pids.each{|pid| cluster.add(pid)}

cluster.check! do |process_id, monitor, free_memory|
	puts "Free memory (#{free_memory} bytes) below minimum"
	puts "Terminating process #{process_id} to free memory"
	
	Process.kill("TERM", process_id)
	cluster.remove(process_id)
end
```

This is particularly useful in containerized environments or systems running multiple applications, where maintaining free memory prevents system-wide issues.

### Combined Limits

Both limits can be active simultaneously:

``` ruby
cluster = Memory::Leak::Cluster.new(
	total_size_limit: 1024 * 1024 * 1024 * 4,      # 4 GB total
	free_size_minimum: 1024 * 1024 * 1024 * 2      # 2 GB free minimum
)

cluster.check! do |process_id, monitor, metric|
	# metric is either total_size or free_memory depending on which limit was violated
	puts "Memory limit exceeded, terminating process #{process_id}"
	
	Process.kill("TERM", process_id)
	cluster.remove(process_id)
end
```

## Configuration Options

### Monitor Options

When adding processes to a cluster, you can customize detection parameters:

``` ruby
cluster.add(process_id,
	# Maximum size increases before assuming a leak (default: 20)
	increase_limit: 10,
	
	# Threshold for significant size increases in bytes (default: 10 MB)
	threshold_size: 1024 * 1024 * 5,  # 5 MB
	
	# Hard limit for process size (optional)
	maximum_size_limit: 1024 * 1024 * 1024  # 1 GB
)
```

### Understanding Detection

A memory leak is detected when:
1. The process memory increases by more than `threshold_size`.
2. This happens `increase_limit` consecutive times.
3. Memory usage is not stabilizing.

This prevents false positives from normal memory allocation patterns while catching genuine leaks.

### Platform Differences

Memory measurement capabilities vary by platform:
- **Linux**: Full support for shared/private memory breakdown
- **macOS**: Limited memory metrics
- **Other Unix**: Basic RSS measurements only

Use `Process::Metrics::Host::Memory.supported?` to check platform capabilities before using `free_size_minimum`.
