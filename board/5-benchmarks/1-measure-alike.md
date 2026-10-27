---
size: M
priority: P3
---
# Benchmarks measure Zap and its rivals the same way

Two measures are not alike across hosts and programs:

- Linux's cycle counter leaves out the kernel (`std/perf/linux/perf.zap`, line 31) where Windows'
  includes it, so syscall-heavy problems read worse on arm64.
- `httpJson`'s Rust rival does not parse HTTP: it matches `starts_with("GET /plaintext ")` and reads
  the id at offset 13 (`tests/benchmarks/others/httpJson.rs`, line 89), while Zap parses headers.

- [ ] before attacking an arm64 ratio near 5x, also compare wall time on arm64; a note in
  `tests/benchmarks/bench.zap`'s output shows both cycles and wall time for the problem
- [ ] make the rival and Zap parse alike: either the Rust program parses headers as Zap does, or
  both scan for the same bytes; `std/net/http.zap`'s `headEnd` and `byteIndex` use the vector
  `byteIndexIn`. `httpJson`'s ratio is then comparing the same work
