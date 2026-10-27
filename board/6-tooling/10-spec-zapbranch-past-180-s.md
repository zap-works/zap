---
size: S
priority: P1
check: zap test spec/zapBranch.zap passes inside the clock limit
---
# `spec/zapBranch.zap` runs inside the clock limit

In a whole `zap test` on main (commit eddccb49), with the agents' hosts and lands running beside it:

```
FAIL spec/zapBranch.zap: the tests ran past 180 s on the clock and were stopped
```

The file peaks at 2289 MB (the scheduler lines show it) and holds the others back while it runs.

- [ ] measure `zap test spec/zapBranch.zap` alone, then inside a whole run; write both times here
- [ ] if it passes alone, split its tests into files so none passes 180 s under the runner's own
  parallelism; if it fails alone, the branch commands it drives (`zap branch`) got slower, and
  that is the bug to fix
- [ ] `zap test spec/zapBranch.zap` passes, and a whole `zap test` shows no clock failure for it
