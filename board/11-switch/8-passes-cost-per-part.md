---
size: L
priority: P0
---
# A cold part of the translated game costs a few processor-seconds

A cold build of one BotW part takes about 35 processor-seconds, nearly all in the optimizer passes
over the translated functions' form: one `match` of hundreds of integer arms over straight-line
arms of `u64` arithmetic. The settle rounds are compiler-2.

- [ ] measure with the compiler's pass counters what of that form each pass spends its rounds on,
  and write the table here; a few passes account for most of the time
- [ ] change the costliest pass, or the form the translator writes (`translate/emit.zap`), so a cold
  part builds in a few processor-seconds; the executable's behavior is unchanged (`lockstep` stays
  clean) and `zap test --only size` shows the part's time and memory down
