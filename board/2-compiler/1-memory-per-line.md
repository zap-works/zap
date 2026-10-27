---
size: XL
priority: P1
branch: compiler-1
by: 7534e27a-8ea6-4b29-917f-33acde77f9d7
---
# Memory per line

A build's memory grows with its lines, so a 16 GB machine builds many parts at once. A node is
64 bytes (kind, place and ival narrow; its children kidsLen ids from kidsAt and its part an
index, both into the lists kept beside the arena, kidIds a NodeLists; syntax/node.zap). Its part
(NodePart, 56 bytes; entry 0 the empty one) holds sub and types, which most parts hold alone,
and the rarer texts, names and origin apart again (NodeMore). recompShape's program (240,000
lines, 1.94 M nodes, 1.96 M children, 109,000 parts) peaks at 0.31 GB (`zap test --only size`;
0.46 before this card, 0.70 at first; `ZAP_RUN=phases` gives each phase's). A held code waits for its place packed in one block
(IrMade.heldCode); the lowering runs at most 64 forms ahead of the passes (irFlightMost); a big
list grown in place commits only its new pages and a reserve of one grows it by a quarter
(runtime/core). An IR instruction is 96 bytes: its vregs and blocks i64, op a u16, size and cond
a u8, the narrow fields packed last, a call's args and a key apart (IrInstPart). hugeFnShape (one
function of 33,045 lines, BotW's part 36's shape, about 340,000 instructions as lowered) peaks at
0.17 GB; the compiler's own build at 0.26. BotW's parts build only on recomp.switch's branch: measure there
once it lands (part 36 peaked at 1.25 GB cold for Windows before this card).

Next: the IR instruction's vregs and blocks (dst, a, b, c, d, target, other) in i32, 96 bytes
to 72; a node's text (24 bytes of its 64); fixups' targets in an i32 (a jump table's entry keeps its two labels as label << 32 | table; 3 MB of 310).

## Handoff

- Landed here: held codes packed, forms in flight bounded, the commit charged twice fixed, a big
  list's reserve by a quarter, the IR instruction's narrow fields packed and its args and key
  apart, NodePart split (NodeMore), op/size/cond narrow, the node's part an index into
  kidIds.parts (Node.copied gives a copy its own); size.baseline's peaks locked. Each refactor's
  code the same (tools/golden.zap).
- Vregs in i32: fields alone are 1,030 `i32()` at constructors; i32 from irVreg on spreads into
  lists (i32[] is no i64[]), ternaries and map keys (899 errors after the roots): pick one way.
- Build the compiler with `ZAP_RUN=nocache` after a struct's layout changes (compiler-25).
