---
size: XL
---
# Skate 3: the skater moves with the game's animations

The skater is drawn in his bind pose (`projects/skate3/skate/skater.zap`). He needs the skeleton
and the animations, then skinning. The skeleton is in the model data (`tRModelData`, type
0x00EB0001: inverse bind matrices and bone names); the hierarchy is in the `.abin` animation
database (`data/anim/` in `miscload.big`).

- [ ] read the skeleton: the inverse bind matrices and bone names from `tRModelData`, the hierarchy
  from the `.abin` files (a new reader beside `projects/skate3/rw4`); a tool prints the bone tree
- [ ] read the `.abin` animations (`data/anim/`): the clips' channels and keyframes; a tool prints
  a clip's length and the bone transforms at a time
- [ ] skin the skater's meshes with the pose in `projects/skate3/graphics` (the engine's skinning in
  `engine/scene/skin.zap`); a headless shot shows him in an idle pose instead of the bind pose
