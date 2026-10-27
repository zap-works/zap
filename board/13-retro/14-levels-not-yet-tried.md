---
size: L
---
# Lemmings: the levels not yet compared with DOS are compared

`projects/lemmings/README.md` lists the levels compared with the DOS game: the first five of each
rating and levels 10, 15, 20, 25 and 30. The others (levels 6 to 9, 11 to 14, 16 to 19, 21 to 24
and 26 to 29 of each rating where not already listed) have never been run against the oracle.

- [ ] for each untried level, write a recipe of a few skills (`--route`, and `--sim-route` when a
  click lands one iteration late), run `zap run projects/lemmings/compare.zap --rating R --level L
  --route ROUTE --iterations 400` (one oracle run at a time), and note in the README the recipes
  that match
- [ ] for each level that differs, add a card, or fix it when the cause is small
