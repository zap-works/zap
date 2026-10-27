---
size: M
---
# Lemmings: skill clicks land on the same lemming as in DOS

`projects/lemmings` is checked frame by frame against the DOS game (`compare.zap`, see
`projects/lemmings/README.md`). In crowds, a skill click gives the skill to a different lemming in
DOS than in our build. These recipes still differ from the first iteration listed: Fun 30 (DOS
iteration 263, 7 pixels), Taxing 20 (263, 7 pixels), Tricky 25, Taxing 10 and Mayhem 20. The click's
hit box (`clickLeft` and `clickTop` in `game/game.zap`) was fitted on few cases.

- [ ] for each of the five recipes, dump the DOS memory at the click (`compare.zap --mem "n ..."`)
  and print which lemming got the skill in DOS, then print ours with `lemmingsAt.zap`; write the
  differences here
- [ ] check each recipe's aim is on the screen (a target past the view's right edge makes the DOS
  cursor clamp and scroll the view)
- [ ] fix the hit rule in `game/` so all five recipes match for their 450 iterations
  (`zap run projects/lemmings/compare.zap --rating R --level L --route ROUTE --iterations 450`
  prints no differing iteration)
