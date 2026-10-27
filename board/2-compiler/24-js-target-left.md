---
priority: P2
size: M
check: zap test --target js spec, every block a browser program uses passing or refused by name
---
# The JS target runs the spec's browser blocks

compiler-23 landed `--target js` (`compiler/targets/js/README.md`). Four things are left before
the web target is complete.

- [ ] `spec/modules.zap`'s bit cursor needs `u64` values past 2^53 and stops at run time under JS;
  make 64-bit integers exact under JS (or refuse the block by name); the block passes under
  `zap test --target js spec`
- [ ] types with a drop function and raw word reads are refused under JS: write them for JS or
  keep them refused, each refusal with a message naming the construct
- [ ] run `zap test --target js spec` whole and judge each failure: fix it or refuse it by name
- [ ] `runtime/js/prelude.js` holds JS copies of runtime functions whose Zap reads raw memory; move
  it to a `js/` runtime dir beside `runtime/linux/`, written in Zap where the memory reads allow,
  and the same `zap test --target js spec` run passes
