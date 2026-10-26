# Benchmarks

25 problems against C, C++ and Rust.

Twenty-five problems, every one under 1.00x against the best of C, C++ and Rust at `--full`, the
rivals improved within the rules as Zap is; `bench.baseline` is recorded again then (it holds the
ratios against the old rivals). Now, geometric means: Zap's time 0.71x C's, 0.80x C++'s, 0.80x
Rust's; memory 0.83x, 0.74x, 0.72x; tokens: C 2.16x Zap's, C++ 2.35x, Rust 2.10x, Python 1.06x.
Ratios below are cycles (`--fresh all`, one problem at a time on Windows) unless said.
