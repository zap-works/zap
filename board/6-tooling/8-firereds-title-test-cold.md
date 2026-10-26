---
size: S
check: zap test projects/firered --full passes with the player's dump present
---
# Firered's title test past the cold limit

projects/firered/tests/title.zap passes the 60 s of processor time a test file has (spec 13.1)
when the game builds cold, after a change of the compiler: the build alone is about 60 s on every
processor (10 to 12 s warm, the executable kept), so the runner stops it. Lighter: the game's
build made cheaper (compiler-side), or the test split so that the build is not inside a file's
limit. The dump (projects/firered/rom) is not in every checkout, so measure where it is.

Also to run again after the tooling cards: `zap test --full` at the root (fmt, the measures), and
BotW's boot past turn 1114 after the syncpoint fixes (projects/recomp/switch/TODO.md Slice 1 item 1).
