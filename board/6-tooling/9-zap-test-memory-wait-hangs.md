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

- [x] reproduce with the whole suite (the files after tests/memory/isRun.zap in the order)
- [x] the wait wakes on every finished file and on the free memory changing
- [x] a wait with nothing running and a file that never fits starts it alone or fails it, named

## Handoff

- `zap test tests --only tests` (201 files, ~20 min, 1.3 GB free of other agents' load) ended with
  every wait answered: no hang reproduced, so the cause is not proven. `runGroups` polls every
  20 ms, so a wait wakes on any ended file or memory change; with no group running a file,
  `fitsBeside` starts the first waiting file whatever its peak (tests in compiler/zap.zap).
- Fixed on this branch: `endedEarly` no longer waits for an abandoned zap, and the wait for the
  groups' zaps after the last file is bounded (`waitWithin(stopWaitMs)`, then killTree).
- Left: a silence with the scheduler's last line "waiting" means `runGroups` was blocked in a
  call (eprint into a pipe nobody reads is the one untested suspect) or the whole `zap test`
  (all kinds, not only tests) was not run; run the root `zap test` once to confirm, then `git rm`
  this card.
