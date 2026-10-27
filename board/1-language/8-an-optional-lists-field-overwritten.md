---
size: S
blocked: waits for the failure to show again, to reduce it
---
# A list of structs keeps its `i64[]?[]` field intact

A list of structs with a field of type `i64[]?[]` (a list of optional integer lists) had that field
overwritten. It was met while grouping the test files, and 900 fuzzed programs of that shape
(`tests/fuzz/memory.zap`) ran right, so the cause is not known and there is no small program that
shows it yet.

- [ ] when the failure shows again, reduce it to a test in `tests/memory/openbugs.zap.txt`; seeing
  it work is that test failing on its own
- [ ] fix it (the ownership code in `compiler/ownership` or the code generator) and move the test
  to `tests/memory/fuzzFound.zap`; `zap test tests/memory` passes
