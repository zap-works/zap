---
size: XL
priority: P1
---
# The compiler uses less memory per line of source

A 16 GB machine builds many parts of a big program at once, so each build's peak memory decides how
many run side by side. A syntax node is 72 bytes (`compiler/syntax/node.zap`: kind, place and ival
narrow; its children are `kidsLen` ids from `kidsAt` in the arena's one list `kidIds`; the rare
fields live in a none-or-one `NodePart`: the lists, the second text and the origin).
`tools/recompShape.zap` (240,000 lines, 1.95 M nodes, 1.5 M children) peaks at 0.46 GB under
`zap test --only size` (0.70 at first): 231 MB held after loading, 274 MB after the check, then the
code phase holds 360 MB and peaks at 475 MB, with the jobs' forms in flight over the assembler's
tables (841,000 labels and 747,000 fixups, 4 and 14 bytes each; 2 M words of debug lines; 8 MB of
code). The accessors added so far made the compiler's executable 3.6% larger (16.2 to 16.8 MB).

Before the node shrank, 357,000 lines of `c.x[1] = c.x[2] + u64(7)` in 3,000 functions peaked at
2.1 GB (`ZAP_RUN=memstats`); a generated file of N functions of 117 such lines reproduces it. BotW's
part 36 (one function of 33,045 lines; `tools/hugeFnShape.zap` writes its shape, 0.21 GB) peaked at
1.25 GB cold for Windows. For linux-arm64 it ran out of memory in the register allocator's live
ranges (`irFlush` under `irAllocateIntervals`, `compiler/targets/x64/irRegs.zap`) before liveness
kept sparse rows; all 131 parts now build for linux-arm64 (17 minutes cold, two at a time).

- [ ] move `NodePart` out of the node into a table, the node keeping a 4-byte index instead of the
  24-byte part (72 to 56 bytes a node, its accessors one load more): change
  `compiler/syntax/node.zap`; `zap test --only size` shows recompShape's peak under its present
  0.46 GB and the executable growing by under 1%
- [ ] keep the fixups' targets in an `i32` (a jump table's entry keeps its two labels as
  `label << 32 | table` today): change the assembler in `compiler/targets/x64`; the peak above
  drops again
- [ ] bound the jobs' forms in flight so the code phase's 475 MB peak falls toward its 360 MB end
  level: `ZAP_RUN=memstats` on recompShape shows the lower peak
- [ ] measure BotW's parts on the recomp.switch branch once it lands, and record the peak
