---
size: M
---
# Lemmings: levels with two entrances open at the DOS game's iteration

On the two-entrance levels (Tricky 10 and Mayhem 15) the entrances open at a different iteration
than in DOS, so the first 80 pictures do not align with the DOS game (offset -8, as Fun 11 had).

- [ ] with `compare.zap` (`projects/lemmings`), find in the DOS memory dump (`--mem`) the iteration
  at which each entrance opens, for Tricky 10 and Mayhem 15, and write it here
- [ ] change the entrance timing in `game/` to match; `zap run projects/lemmings/compare.zap
  --rating 2 --level 10 --route ROUTE --iterations 450` (and Mayhem 15) prints no differing
  iteration, with the existing recipes for those levels' skills
