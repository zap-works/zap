---
size: L
---
# SMW: every sprite kind is drawn in the widescreen margins

The widescreen widens the windows that the main sprites cull by (GetDrawInfo, SubOffscreen, the
spawner; see `projects/smw/README.md`). Some sprite kinds cull by their own windows and still
vanish at the native edges: extended sprites (fireballs, Banzai Bill's smoke), cluster sprites (the
Boo ceiling at $02:FC8D, not reached by the flow yet), and bounce, smoke, score and minor extended
sprites.

- [ ] for each kind, find its own window test in the cartridge (SMWCentral's ROM map and
  snesrev/smw name the routines) and widen it in `projects/smw/cartridge/patches.zap`
- [ ] a wide shot at 486 pixels (`tests/wide.zap` style) shows a fireball, a Banzai Bill's smoke
  and a Boo ceiling inside the margins, and the native-logic route still matches Mesen 2
