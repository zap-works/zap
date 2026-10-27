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
0.46 before this card, 0.70 at first). Cold (`ZAP_RUN=nocache,phases`) it holds 216 MB after
loading (286 at most there: its nine files parsed apart at once), 231 after the check (305 at
most), 288 at the code phase's end, and peaks at 336 there. A held code waits for its place packed in one block
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

- Landed here: held codes packed, forms in flight bounded, the double commit fixed, a list's
  reserve by a quarter, IrInst packed (args and key apart, op/size/cond narrow), NodeMore, the
  node's part an index into kidIds.parts (Node.copied); peaks locked, code the same (golden).
- Vregs in i32: 1,030 `i32()` at constructors, and i32 spreads into lists, ternaries and map
  keys (899 errors after the roots): pick one way.
- The instruction's 16 bytes saved 6 MB of recompShape's peak, the node's 8 about 10: the code
  phase's 57 MB growth and its forms in flight are what is left to find.
- After a struct's layout changes: build with `ZAP_RUN=nocache`, clear build/fixedpoint/1 and 2's
  build (compiler-25); fmt's trap (compiler-26) leaves node.zap and ir.zap unlaid.
