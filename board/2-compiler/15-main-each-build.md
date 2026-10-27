---
size: M
priority: P2
---
# Scripts: a script's `main` costs less in each build

The scripts bench (`zap test --only bench tests/scripts`, described in `board/2-compiler/README.md`)
compares an edited script's build against Python. Each build lowers a script's `main`, checks its
ownership, allocates its registers and inlines its calls (2 to 10 ms: `tests/scripts/loc.zap`'s
`main` takes 9, half of it the ownership check's origins), and writes its form for the IR cache's key
and looks it up (`irMadeReady`, 2 ms of `csvSum.zap`'s).

- [ ] make the ownership check's origins cheaper for a small `main` (`compiler/ownership`):
  `loc.zap`'s `main` falls below 9 ms in the compiler's timing output
- [ ] make the IR cache key cheaper to write and look up (`irMadeReady`): `csvSum.zap` saves
  most of its 2 ms; the bench ratio of both scripts falls
