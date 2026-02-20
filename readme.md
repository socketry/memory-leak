# Memory::Leak

Detects memory leaks in Ruby applications.

[![Development Status](https://github.com/socketry/memory-leak/workflows/Test/badge.svg)](https://github.com/socketry/memory-leak/actions?workflow=Test)

## Usage

Please see the [project documentation](https://socketry.github.io/memory-leak/) for more details.

  - [Getting Started](https://socketry.github.io/memory-leak/guides/getting-started/index) - This guide explains how to use `memory-leak` to detect and prevent memory leaks in your Ruby applications.

## Releases

Please see the [project releases](https://socketry.github.io/memory-leak/releases/index) for all releases.

### v0.10.2

  - Disable default `increase_limit: nil`.

### v0.10.0

  - Introduce `free_size_minimum` to monitor minimum free memory size, which can be used to trigger alerts or actions when available memory is critically low.

### v0.9.2

  - Also log host memory in total memory usage logs.

### v0.9.0

  - Use `process-metrics` gem for accessing both private and shared memory where possible.
  - Better implementation of cluster `total_size_limit` that takes into account shared and private memory.

### v0.8.0

  - `Memory::Leak::System.total_memory_size` now considers `cgroup` memory limits.

### v0.7.0

  - Make both `increase_limit` and `maximum_size_limit` optional (if `nil`).

### v0.6.0

  - Added `sample_count` attribute to monitor to track number of samples taken.
  - `check!` method in cluster now returns an array of leaking monitors if no block is given.
  - `Cluster#check!` now invokes `Monitor#sample!` to ensure memory usage is updated before checking for leaks.

### v0.5.0

  - Improved variable names.
  - Added `maximum_size_limit` to process monitor.

### v0.1.0

  - Initial implementation.

## Contributing

We welcome contributions to this project.

1.  Fork it.
2.  Create your feature branch (`git checkout -b my-new-feature`).
3.  Commit your changes (`git commit -am 'Add some feature'`).
4.  Push to the branch (`git push origin my-new-feature`).
5.  Create new Pull Request.

### Developer Certificate of Origin

In order to protect users of this project, we require all contributors to comply with the [Developer Certificate of Origin](https://developercertificate.org/). This ensures that all contributions are properly licensed and attributed.

### Community Guidelines

This project is best served by a collaborative and respectful environment. Treat each other professionally, respect differing viewpoints, and engage constructively. Harassment, discrimination, or harmful behavior is not tolerated. Communicate clearly, listen actively, and support one another. If any issues arise, please inform the project maintainers.
