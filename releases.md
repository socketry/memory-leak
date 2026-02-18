# Releases

## v0.9.0

  - Use `process-metrics` gem for accessing both private and shared memory where possible.
  - Better implementation of cluster `total_size_limit` that takes into account shared and private memory.

## v0.8.0

  - `Memory::Leak::System.total_memory_size` now considers `cgroup` memory limits.

## v0.7.0

  - Make both `increase_limit` and `maximum_size_limit` optional (if `nil`).

## v0.6.0

  - Added `sample_count` attribute to monitor to track number of samples taken.
  - `check!` method in cluster now returns an array of leaking monitors if no block is given.
  - `Cluster#check!` now invokes `Monitor#sample!` to ensure memory usage is updated before checking for leaks.

## v0.5.0

  - Improved variable names.
  - Added `maximum_size_limit` to process monitor.

## v0.1.0

  - Initial implementation.
