---
size: S
blocked: waits for the failure to show again, to reduce it
---
# An optional list's field overwritten

A list of structs with a field of type `i64[]?[]` had that field overwritten, met grouping the
test files; 900 fuzzed programs of that shape (tests/fuzz/memory.zap) ran right. Reduce it to a
test in tests/memory/openbugs.zap.txt when it shows again, then fix it.
