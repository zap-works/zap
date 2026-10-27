---
size: XL
priority: P1
branch: compiler-1
by: 1e7c2c1e-fd9e-421e-8fef-abce9c81dd63
---
# The compiler uses less memory per line of source

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

- [x] move `NodePart` out of the node into a table, the node keeping a 4-byte index instead of the
  part (72 to 64 bytes a node; its part's rare fields apart again in NodeMore)
- [x] keep the fixups' targets in 32 bits (a jump table's entry's two labels a pair of
  Asm.tablePairs): the code phase holds 3 MB less
- [x] bound the jobs' forms in flight (irFlightMost) so the code phase's peak falls toward its
  end level
- [ ] measure BotW's parts on the recomp.switch branch once it lands, and record the peak
