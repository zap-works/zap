---
size: S
---
# The seeds' `ZAP_RUNTIME`

they know it, not ZAP_RUN's `runtime=` (compiler/driver/seeds.zap
sets it when it builds with a seed): that line goes once the seeds are promoted. So do the
compiler's workarounds of checker bugs fixed since: irLowerLet.zap's `k i64 = nodes[s].kind`
(a part before an `is` test narrowed its else) is `k = nodes[s].kind`; checkExprGenerics.zap's
`nodes[callee].part[0].names[0]` is `nodes[callee].names()[0]`, and the index loops over a
node's `sub()` written for the change of another node can be `for` loops.
