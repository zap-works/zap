---
priority: P1
size: M
check: zap test --target js spec, every block a browser program uses passing or refused by name
---
# The JS target: what is left

compiler-23 landed `--target js` (compiler/targets/js/README.md); left of it:

- [ ] spec/modules' bit cursor needs u64 values past 2^53 and stops at run time under JS.
- [ ] Types with a drop function and raw word reads are refused: written for JS or kept refused.
- [ ] `zap test --target js spec` run whole and judged.
- [ ] runtime/js/prelude.js holds JS copies of runtime functions whose Zap reads raw memory: a
  `js/` runtime dir beside `linux/` instead.
