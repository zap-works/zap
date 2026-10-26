---
size: XL
---
# Skyrim's seams

(each measured by skyrim's frame or the duplicate code it removes):
- [ ] One up axis: physics, navmesh and particles are Z-up, the scene and renderer Y-up; skyrim
  converts at the seam (`yUp` in game/cell.zap, `skyrimPoint` in sound/scene.zap, 17 uses).
- [ ] A pose of N layers: skin.zap's `Pose{clip, from, blend}` blends two clips; `Pose.layers {clip,
  time, weight, mask}[]` with a mask a bone (`turned` a bool[], a linear search a node today);
  game/graph.zap drops the layers past two and finds clips by name a frame.
- [ ] A state machine for behaviour graphs (engine/scene/stateMachine.zap): game/graph.zap's 469
  lines and skyrim/hkx/graph.zap are generic but `moveStart`/`Speed`; node state in 9 parallel
  maps, `reached = {}` and `queue.remove(0)` a frame, bounds found by name.
- [ ] One skinning and pose, after the pose layers: actor/skinning.zap (CPU, `boneWorld @
  skinToBone` again a call, the Part copied to change positions) and actor/pose.zap repeat
  skin.zap's `poseWorlds`; hkx/spline.zap is a B-spline beside engine/scene/curve.zap.
- [ ] An audio bus (engine/audio/bus.zap): categories with inherited volume, distance curves,
  ducking, crossfade and music by priority, from game/sound/book.zap and music.zap.
- [ ] engine/swf's AVM1: bindings resolved once and `player.on("CloseMenu", fn)` (interface/hud.zap
  builds `"{base}.Set{name}MeterPercent"` a frame; each menu compares names).
