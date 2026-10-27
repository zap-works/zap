---
size: M
priority: P0
check: zap test of the whole tree ends, with no `waiting to start` line left unanswered
---
# `zap test` never waits for memory forever

A whole `zap test` (pid 6296, started 22:38) stopped printing at 22:54 and was killed by hand 40
minutes later, with no child process left and the scheduler silent. The last line of its log was:

```
tests: waiting to start tests/memory/leakReport.zap (1536 MB; 3671 MB free; tests/io/measured.zap 1536 MB, tests/memory/isRun.zap 1536 MB)
```

3671 MB were free and 1536 MB needed, so the file fitted, yet it never started; the two files named
as running had already printed `ok` (isRun) or no longer ran. The scheduler is
`compiler/tools/test/groups.zap`: `runGroups` (line 132) and `nextFitting` (line 207).

- [ ] reproduce with the whole suite (the files after `tests/memory/isRun.zap` in the order); write
  here how long it takes to show
- [ ] find why the wait does not wake, or does not pick a fitting file, when the running set
  empties; make the wait wake on every finished file and on the free memory changing
- [ ] a wait with nothing running and a file that never fits starts it alone or fails it by name,
  an error with the files left, never a silence; the check above passes
