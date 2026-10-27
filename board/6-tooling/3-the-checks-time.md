---
size: M
priority: P2
---
# The check kind of `zap test` takes less time

`verifyNotes` (`compiler/tools/fmt/canon.zap`) loads the whole program again for each round, about
0.9 s each. The suite's kinds take: check 174 s warm, and cold about 415 s at `--jobs 2` with the
lint verifying inside the checking zap; build runs beside dups and limits; the tests kind's time
is what is left.

- [ ] load the program once for all of `verifyNotes`' rounds, not once per round; the check kind
  warm falls below 174 s
- [ ] measure the cold check kind and the tests kind again and write here what takes the time,
  then cut the largest part
