---
size: M
priority: P3
---
# `bench.baseline` is recorded again against the improved rivals

`baselines/bench.baseline` holds the ratios against the old rival programs. The rivals (C, C++ and
Rust, in `tests/benchmarks/others`) have since been improved within the benchmark rules, so the
baseline is stale.

- [ ] record `bench.baseline` again with `zap test --only bench --full`, one problem at a time; the
  file changes
- [ ] check every problem is under 1.00x against the best rival; a problem above it gets a card (or
  its existing one stays)
