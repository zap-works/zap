---
size: XL
priority: P1
---
# Memory per line

, so a 16 GB machine builds many parts at once. A node is 72 bytes (kind,
place and ival narrow; its children kidsLen ids from kidsAt in the arena's one list kidIds,
written anew at its end on a change; its text and part, the none-or-one NodePart holding the
rare lists, the second text and the origin, syntax/node.zap). recompShape's program (240,000
lines, 1.95 M nodes, 1.5 M children) peaks at 0.46 GB (`zap test --only size`; 0.52 before the
span, 0.70 at first): 231 MB held after loading (372 MB at most there), 274 MB after the check,
then the code phase holds 360 MB at its end and peaks at 475 MB, the jobs' forms in flight
over the assembler's tables (841,000 labels and 747,000 fixups, now 4 and 14 bytes each, 2 M
words of debug lines at 4 bytes; 8 MB of code). Next: the part out of the node as an index into
a table of NodePart (24 bytes to 4, for 56 bytes a node, its accessors one load more); fixups'
targets in an i32 (a jump table's entry keeps its two labels as label << 32 | table); the
forms in flight bounded. The span's accessors made the compiler's executable 3.6% larger (16.2
to 16.8 MB), the part's 4% before. Before the node shrank, 357,000 lines of
`c.x[1] = c.x[2] + u64(7)` in 3,000 functions peaked at 2.1 GB (`ZAP_RUN=memstats`); a
generated file of N functions of 117 such lines reproduces it. BotW's parts build only on
recomp.switch's branch: measure there once it lands. BotW's part 36 (f881b6b8, one function of
33,045 lines; tools/hugeFnShape.zap its shape, 0.21 GB) peaked at 1.25 GB cold for Windows
(0.71 GB at the check's end); for linux-arm64 it ran out of memory in the register allocator's
live ranges (irRegs.zap's irFlush, under irAllocateIntervals) before liveness kept sparse rows;
all 131 parts now build for linux-arm64 (17 minutes cold, two at a time).
