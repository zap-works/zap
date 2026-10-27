---
size: L
---
# SNES: widescreen looks right in every scene without a per-game hook

The SNES recompiler (`projects/recomp/snes`) widens the picture generically by repeating or blanking
what the tilemaps do not hold past the screen's edges (`console/wide.zap`, `wideDraw.zap`). Where a
game has hooks (DKC's), they do better than the generic repeat, so some scenes look worse without
them.

- [ ] list the scenes of SMW, Zelda and DKC where the generic widescreen looks wrong (a repeated
  edge, a blank band), as widescreen shots under `projects/recomp/snes/tests`; the list is written
  in this card
- [ ] improve the generic rule (`console/wide.zap`) for the worst of them without a game hook; its
  shot now looks right, and the other games' widescreen frame checks are unchanged
