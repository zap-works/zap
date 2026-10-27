---
size: S
priority: P2
---
# The compiler drops its workarounds for old seeds

The seeds (the old compilers that build the new one) know `ZAP_RUNTIME` but not `ZAP_RUN`'s
`runtime=` word, so `compiler/driver/seeds.zap` sets `ZAP_RUNTIME` when it builds with a seed. That
line goes once the seeds are promoted (the user does that; agents never promote). The compiler also
keeps workarounds for checker bugs fixed since:

- [ ] `compiler/ir/irLowerLet.zap`: `k i64 = nodes[s].kind` (a part before an `is` test narrowed its
  else) becomes `k = nodes[s].kind`
- [ ] `compiler/check/checkExprGenerics.zap`: `nodes[callee].part[0].names[0]` becomes
  `nodes[callee].names()[0]`; and the index loops over a node's `sub()` written for the change of
  another node become `for` loops
- [ ] after the seeds are promoted, delete the `ZAP_RUNTIME` line in `seeds.zap`; the bootstrap
  (`zap build --seeds` check) and `zap test compiler` pass
