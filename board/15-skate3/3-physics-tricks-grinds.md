---
needs: [skate3-1]
size: XL
---
# Skate 3: the skater rolls, does tricks and grinds as in the game

After the animations (skate3-1), the skater needs the game's physics and moves, then to be checked
against the game. mchughalex/skate3recomp (a native recompilation) is the reference for exact
behavior, as sm64ex was for Mario.

- [ ] physics: rolling, pushing, jumping and landing on the district's collision
  (`projects/skate3/game`)
- [ ] tricks, and grinds on the rails (`projects/skate3/rail.zap`; the game's Sim grind splines), and
  offboard (falling off the board)
- [ ] check frame by frame against the native recompilation (as Mario was checked against sm64ex):
  a scripted run of inputs gives the same positions in both
