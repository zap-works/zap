---
size: XL
priority: P1
branch: compiler-1
by: cf9531d3-0be3-4bab-871f-932ce9f92607
---
# Memory per line

A build's memory grows with its lines, so a 16 GB machine builds many parts at once. A node is
72 bytes (kind, place and ival narrow; its children kidsLen ids from kidsAt in the arena's one
list kidIds, written anew at its end on a change; its text and part, syntax/node.zap). Its part
(NodePart, 56 bytes) holds sub and types, which most parts hold alone, and the rarer texts,
names and origin apart again (NodeMore). recompShape's program (240,000 lines, 1.94 M nodes,
1.96 M children, 109,000 parts: 55,000 only sub, 24,000 only types, 25,000 empty) peaks at 0.33
GB (`zap test --only size`; 0.46 before this card, 0.70 at first; `ZAP_RUN=phases`): 232 MB
held after loading (290 at most there), 250 after the check (315 at most), then the code phase
holds 303 MB at its end and peaks at 343. A held code waits for its place packed in one block
(IrMade.heldCode); the lowering runs at most 64 forms ahead of the passes (irFlightMost); a big
list grown in place commits only its new pages and a reserve of one grows it by a quarter
(runtime/core). An IR instruction is 112 bytes: its vregs and blocks i64, its narrow fields
packed last, a call's args and a key apart (IrInstPart). hugeFnShape (one function of 33,045
lines, BotW's part 36's shape, about 340,000 instructions as lowered) peaks at 0.18 GB; the
compiler's own build at 0.27. BotW's parts build only on recomp.switch's branch: measure there
once it lands (part 36 peaked at 1.25 GB cold for Windows before this card).

Next: the IR instruction's vregs and blocks (dst, a, b, c, d, target, other) in i32, 112 bytes
to 88; the node's part as an index (72 bytes to 64); fixups' targets in an i32 (a jump table's
entry keeps its two labels as label << 32 | table; 3 MB of 340).

## Handoff

- Landed here: held codes packed, forms in flight bounded, the commit charged twice fixed, a big
  list's reserve by a quarter, the IR instruction's narrow fields packed and its args and key
  apart, NodePart split (NodeMore); size.baseline's peaks locked. Each refactor's code the same
  (tools/golden.zap).
- Vregs in i32: fields alone are 1,030 `i32()` at constructors; i32 from irVreg on spreads into
  lists (i32[] is no i64[]), ternaries and map keys (899 errors after the roots): pick one way.
- The node's part as an index: its table goes beside kidIds (one struct passed where kidIds is,
  about 1,900 accessor calls given it); the 28 `nodes[x].copy()` then copy their part.
- Build the compiler with `ZAP_RUN=nocache` after a struct's layout changes (compiler-25).
