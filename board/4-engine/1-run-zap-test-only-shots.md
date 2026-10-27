---
size: S
---
# The engine's shot tests are run after the per-frame changes

The per-frame cost changes that already landed (sorted draws, ring sizing, sprite batch, silent
voices, skinning passes) went in without running the shot tests, which compare rendered pictures
with kept ones.

- [ ] run `zap test --only shots` over `engine` and the projects that have shots; every shot that
  differs is either a bug to fix or a picture to look at and update with `--update`; the run passes
