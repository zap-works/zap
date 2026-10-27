---
size: M
priority: P2
---
# Scripts: derived functions are kept, not lowered in each build

Functions the compiler derives (readers, printers, comparisons) are named by a count, so a kept
stage cannot keep them, except an equality's or an order's of built-in types. A script lowers them
in every build: the readers of the program's own types (`tests/scripts/jsonq.zap`'s `$unjson`, 4
ms, with the runtime's `jsonChar` and `jsonCharSpaced` inlined at each call) and the printing of a
kept stage's type (`$str` and `$fmt` of fs's error, in every script).

- [ ] name these derived functions by their text (the type they read or print) instead of a count,
  so they can be kept (compiler code under `compiler/targets/x64/`, beside `keptEntry.zap`); the
  scripts bench (`zap test --only bench tests/scripts`) shows `jsonq` losing most of the 4 ms
- [ ] keep the printing of fs's error in the kept stage, so no script lowers it; any script's build
  timing no longer lists `$str` or `$fmt` of that type
