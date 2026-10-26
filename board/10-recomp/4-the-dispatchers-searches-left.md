---
size: M
---
# The dispatchers' searches left

(compiler). irOpt's irDispatch.zap sends an arm that sets a
translated function's match key to a constant straight to that key's arm (recomp.snes: every way
in, so the match is gone; the Switch's emit.zap: all but the entry's `label = c.pc` and a `br`'s),
and splits a sparse match in pages of `key >> s` when a case takes fewer tests (BotW's labels by
their key sets: 4.4 tests a case to 3.0). Left: game/dispatch.zap's `callExact` and `callStart`
(SMW: 769 and 663 keys over the widths and the banks, about 10 compares a call), whose pages make
no dense run: a level a field (widths, bank, then pages) or a hashed table, after measuring how
often they run. Measured by the games' cycles a frame (SMW about 13.6 M, DKC about 12 M on the
TAS route) and the exe size.
