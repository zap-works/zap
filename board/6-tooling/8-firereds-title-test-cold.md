---
size: S
check: zap test projects/firered --full passes with the player's dump present
---
# FireRed's title test fits the cold build limit

`projects/firered/tests/title.zap` passes the 60 s of processor time a test file has (spec 13.1)
when the game builds cold after a change of the compiler. The build alone is about 60 s on every
processor (10 to 12 s warm, the executable kept), so the runner stops the test. The dump
(`projects/firered/rom`) is not in every checkout, so measure where it is.

- [ ] make the game's cold build cheaper (a compiler-side fix), or split the test so the build is
  not inside one file's limit; `zap test projects/firered --full` passes cold
- [ ] run `zap test --full` at the root once (fmt and the measures) after the tooling cards; it
  passes
- [ ] run BotW's boot past turn 1114 after the syncpoint fixes (that is switch-2's first task);
  switch-2 records the result
