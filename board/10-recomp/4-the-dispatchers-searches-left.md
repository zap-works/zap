---
size: M
priority: P1
---
# The recompilers' dispatch matches do fewer comparisons

A recompiled program jumps through large `match` statements keyed by address. The optimizer's
`irDispatch.zap` (`compiler/optimize`) already sends an arm that sets a translated function's
match key to a constant straight to that key's arm (in recomp.snes every way in, so the match is
gone; in the Switch's `translate/emit.zap` all but the entry's `label = c.pc` and a `br`'s), and
splits a sparse match in pages of `key >> s` when a case then takes fewer tests (BotW's labels by
their key sets: 4.4 tests a case down to 3.0). Left are the generated `game/dispatch.zap`'s
`callExact` and `callStart` for SMW (769 and 663 keys over the widths and the banks, about 10
compares a call), whose pages make no dense run.

- [ ] count how often `callExact` and `callStart` run in an SMW and a DKC frame, and write it here
- [ ] if often enough to matter, dispatch them by a level per field (widths, then bank, then
  pages) or a hashed table; the games' cycles a frame (SMW about 13.6 M, DKC about 12 M on the TAS
  route) fall and `zap test --only size` shows the executable size not larger
