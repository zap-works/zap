---
size: S
priority: P1
---
# fmt writes what the seed misreads

`zap fmt` rewrites a method's `self.part = Box(NodePart())` as `part = Box(NodePart())`, and the
seed reads that line differently from main's zap: syntax/node.zap's nodePart formatted so, the
seed's zap1 recurses in it until the stack runs out, so `zap test --only build` fails. node.zap
and ir.zap keep `self.` in their part makers (nodePart, rarer, instPart) and are left out of
fmt's layout until this is fixed.

- [ ] the seed and fmt agree (the rewrite held back from the compiler's sources until the seeds
  read it, or the seeds promoted)
- [ ] node.zap and ir.zap laid out by fmt
