---
size: L
---
# SMW: a route reaches a vertical level and a layer-2 level

The widescreen decode of `projects/smw/wide/level.zap` (both layouts, layer 2's palette for tileset
3) has not been seen against the live tilemap on vertical and layer-2 levels (Vanilla Secret 1,
Donut Secret 1's water, the layer-2 smash levels). Where the decode fails the judge centres the
scene, never wrong, so there is no wrong picture, only no widescreen there.

- [ ] record routes (with the oracle, `projects/recomp/snes/tools/oracle.lua`) into a vertical
  level and a layer-2 level, saved in `projects/smw/tests/routes`
- [ ] play them with `--wide`; check the decode matches the live BG1 and BG2 tilemaps (the judge
  widens those levels) and shots show the margins right. Fix `wide/level.zap` where it does not
