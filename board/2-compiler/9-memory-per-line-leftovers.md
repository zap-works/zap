---
size: L
priority: P2
---
# The IR instruction and the node smaller still

A node is 64 bytes (`compiler/syntax/node.zap`: its part an index into the arena's NodeLists) and
an IR instruction 96 (`compiler/ir/ir.zap`: vregs and blocks i64, op a u16, size and cond a u8, a
call's args and key apart). recompShape's program peaks at 0.29 GB (`zap test --only size`), BotW's
worst part (85: nine functions of 250,000 to 290,000 instructions as lowered) at 0.49 GB cold, part
36 at 0.36. The passes of big functions are bounded at 600,000 instructions in flight
(irFlightInstsMost, `compiler/targets/x64/irPipe.zap`): unbounded, part 85 peaked at 0.7 GB.

- [ ] the instruction's vregs and blocks (dst, a, b, c, d, target, other) in i32, 96 bytes to 72:
  tried by putting `i32()` at the constructors (1,030 sites, then 899 errors as i32 spread into
  lists, ternaries and map keys); pick one way first (a narrow type the accessors widen)
- [ ] a node's text (24 bytes of its 64) as an index into a table of texts
- [ ] the passes' own working memory of a big function (some 600 bytes an instruction past its
  form): `ZAP_RUN=nocache,phases` on part 85 shows the code phase's peak over its held level
