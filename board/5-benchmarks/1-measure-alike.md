---
size: M
priority: P3
---
# Measure alike

Linux's cycles leave out the kernel (std/perf/linux/perf.zap:31) where
Windows' include it, so syscall-heavy problems read worse on arm64: check wall time too before
attacking the 5x ratios. httpJson's Rust rival does not parse HTTP (`starts_with("GET
/plaintext ")`, the id at offset 13; httpJson.rs:89): the rival parses headers as Zap does, or
both scan alike, and http.zap's headEnd and byteIndex go through the vector `byteIndexIn`.
