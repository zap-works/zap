---
size: L
priority: P2
---
# Scripts: the small fixed costs of each build shrink

A script's build still pays several costs of 1 to 2 ms each; together they matter against Python's
21 to 54 ms. Each is read in the compiler's timing output for a small script.

- [ ] summarize the effects of the kept stages' functions once, in the stage, not again each build
  (`findEffects`, 2 ms of a small build; `compiler/check/effects.zap`), and read their facts in
  parts instead of whole (1 ms)
- [ ] cut the page faults of a build, some 1,900 (fresh big blocks, lists grown into new pages, kept
  files read into buffers). The heap's chunks on huge pages took 160 off, 130 are mmaps; a
  build's fault count (`ZAP_RUN=memstats`) falls further
- [ ] on Windows every look at a file costs about 50 us (a directory listing 100): look at fewer
  files per build. A new executable's first start costs 8 ms more than its next, since the
  antivirus reads it; a loader that maps it as data took 4.6 ms off, so try that again
- [ ] the backend's merge of the same code (its signatures made once, 1 ms), the jumps' relaxation
  and the executable's writing (1 ms each) take less in the same timing
