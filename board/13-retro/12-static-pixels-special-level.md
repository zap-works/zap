---
size: M
---
# Lemmings: Taxing 15 and Fun 15 match the DOS pictures exactly

Two small differences with the DOS game remain in `projects/lemmings`: Taxing 15 (a special level)
has 13 static olive pixels (palette colour 4, on the terrain's slanted edge) in the DOS picture
that are not in ours, from the first iteration; and Fun 15 shows one stray pixel under the roof
for two iterations at DOS iteration 295, unexplained.

- [ ] find where the DOS game draws Taxing 15's 13 pixels (an object, a special terrain piece, the
  level's palette) from its level file or a dump of its memory, and draw them in `game/`; the
  comparison (`compare.zap`) of Taxing 15 shows no differing pixel at iteration 1
- [ ] find what draws Fun 15's stray pixel at DOS iteration 295 (its route is `climber@100
  bomber@180 miner@260 blocker@340`, sim route `bomber@181 miner@261`) and match it; Fun 15 matches
  for 450 iterations
