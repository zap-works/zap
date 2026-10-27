---
size: M
priority: P0
check: zap test of the whole tree ends, with no `waiting to start` line left unanswered
branch: tooling-9
by: 77b5b20e-dd87-423f-b607-a84f65959f33
---
# zap test hangs in its memory wait

A whole `zap test` (pid 6296, started 22:38) stopped printing at 22:54, 40 minutes before it was
killed by hand, with no child process left and the scheduler silent:

```
tests: waiting to start tests/memory/leakReport.zap (1536 MB; 3671 MB free; tests/io/measured.zap 1536 MB, tests/memory/isRun.zap 1536 MB)
```

The last line of the log. 3671 MB free and 1536 MB needed, so the file fitted, yet it never
started, and the two files named as running had already printed `ok` (isRun) or no longer ran.
The scheduler is compiler/tools/test/groups.zap, `runGroups` (line 132) and `nextFitting`
(line 207): find why the wait does not wake or does not pick a fitting file when the running set
empties, and make a wait that nothing can end an error with the files left, never a silence.

- [ ] reproduce with the whole suite (the files after tests/memory/isRun.zap in the order)
- [ ] the wait wakes on every finished file and on the free memory changing
- [ ] a wait with nothing running and a file that never fits starts it alone or fails it, named

## Handoff

- `zap test tests/io/measured.zap tests/memory` alone passes in 58 s with no memory wait: the hang
  needs the whole suite's memory pressure (3.6 GB free, 1536 MB per file).
- A file's default limit is 8 min (`testWallMs(testMaxMs)` plus half of `testTimeoutMs`), so a
  live group stuck on a file would have printed "ran past" long before 40 min: nothing was
  printed, so `runGroups`' loop was likely not iterating, or blocked in a call.
- Fixed in this branch: `endedEarly` no longer waits for an abandoned group's zap (it blocked
  forever). Left to check: a closed process handle makes `isDone` (`WaitForSingleObject`
  failing) false forever; and reproduce with the whole suite to confirm the hang is gone.
- `measured.zap` runs a nested `zap test`, one of the two files named as running in the hang.
