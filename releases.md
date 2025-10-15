# Releases

## Unreleased

  - Added `sample_count` attribute to monitor to track number of samples taken.
  - `check!` method in cluster now returns an array of leaking monitors if no block is given.
  - `Cluster#check!` now invokes `Monitor#sample!` to ensure memory usage is updated before checking for leaks.

## v0.5.0

  - Improved variable names.
  - Added `maximum_size_limit` to process monitor.

## v0.1.0

  - Initial implementation.
