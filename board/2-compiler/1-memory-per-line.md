---
size: XL
priority: P1
branch: compiler-1
by: 7128734f-ad86-4246-9f69-458faff886f2
---
# Memory per line

A build's memory grows with its lines, so a 16 GB machine builds many parts at once. A node is
72 bytes (kind, place and ival narrow; its children kidsLen ids from kidsAt in the arena's one
list kidIds, written anew at its end on a change; its text and part, the none-or-one NodePart
holding the rare lists, the second text and the origin, syntax/node.zap). recompShape's program
(240,000 lines, 1.94 M nodes, 1.96 M children, 109,000 parts) peaks at 0.34 to 0.37 GB (`zap
test --only size`; 0.46 before this card, 0.70 at first; `ZAP_RUN=phases`): 252 MB held after
loading (307 at most there), 267 after the check (341 at most), then the code phase holds 322
MB at its end and peaks at 363. A held code waits for its place packed in one block
(IrMade.heldCode); the lowering runs at most 64 forms ahead of the passes (irFlightMost; with one
job, unbounded, it held thousands: 1.15 GB with two); a big list grown in place commits only its
new pages and a reserve of one grows it by a quarter (runtime/core). An IR instruction is about
150 bytes (its vregs and blocks i64, its narrow fields packed last). hugeFnShape (one function
of 33,045 lines, BotW's part 36's shape) peaks at 0.19 to 0.20 GB, its lowered form 80 MB of
it. BotW's parts build only on recomp.switch's branch: measure there once it lands (part 36
peaked at 1.25 GB cold for Windows before this card).

Next: the IR instruction's vregs and blocks (dst, a, b, c, d, target, other) in i32, 150 bytes
to about 124: as fields alone that is 1,000 conversions at its 610 constructors, so the vreg
numbers become i32 where made (irVreg) and the change follows them; the node's part as an index
(72 bytes to 64); fixups' targets in an i32 (a jump table's entry keeps its two labels as
label << 32 | table; 3 MB of 340).

## Handoff

- Landed here: held codes packed, forms in flight bounded, the commit charged twice fixed, a
  big list's reserve by a quarter, the IR instruction's narrow fields packed; size.baseline's
  peaks locked.
- Tried and dropped: waiting for all of a load's parsed files to reserve the arena once (held
  113 MB more: an exact room then doubled); narrowing the IR's vreg fields alone (1,174 errors).
- The node's part as an index into a module table does not fit: the parse jobs make parts in
  arenas of their own and may not touch a module variable, and `.copy()` of a node would share
  its part. Its table goes beside the arena as kidIds does (passed in), or the idea changes.
