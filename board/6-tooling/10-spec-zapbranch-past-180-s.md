---
size: S
priority: P1
check: zap test spec/zapBranch.zap passes inside the clock limit
---
# spec/zapBranch.zap runs past the clock limit

In a whole `zap test` on main (eddccb49), with the agents' hosts and lands running beside it:

```
FAIL spec/zapBranch.zap: the tests ran past 180 s on the clock and were stopped
```

The file peaks at 2289 MB (the scheduler lines show it) and holds the others back while it runs.
Measure it alone and under load: if it passes alone, split its tests so that no file passes the
limit under the runner's own parallelism; if it fails alone, the branch commands it drives got
slower and that is the bug.

- [ ] its time alone, and under a whole run
- [ ] split or fixed so it ends under the limit
