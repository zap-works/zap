---
size: XL
---
# Skyrim's engine seams become generic engine code

Skyrim's code converts or works around the engine in several places, and the generic parts belong
in `engine/`. Each item is measured by skyrim's frame time or by the duplicate code it removes.
Skyrim files are under `projects/skyrim`.

- [ ] one up axis: physics, navmesh and particles are Z-up, the scene and renderer Y-up, and skyrim
  converts at the seam (`yUp` in `game/cell.zap`, `skyrimPoint` in `game/sound/scene.zap`, 17
  uses). Pick one convention in the engine, delete the conversions, and skyrim's shots stay equal
- [ ] a pose of N layers: `engine/scene/skin.zap`'s `Pose{clip, from, blend}` blends two clips; make
  it `Pose.layers {clip, time, weight, mask}[]` with a bone mask (`turned` is a `bool[]` and a
  linear search a node today); `game/graph.zap` stops dropping layers past two and finding clips by
  name each frame
- [ ] a state machine for behaviour graphs (`engine/scene/stateMachine.zap`, new): `game/graph.zap`
  (469 lines) and `skyrim/hkx/graph.zap` are generic except `moveStart` and `Speed`, with node state
  in 9 parallel maps, `reached = {}` and `queue.remove(0)` each frame, and bounds found by name
- [ ] one skinning and pose implementation, after the pose layers: `skyrim/actor/skinning.zap` (CPU;
  `boneWorld @ skinToBone` is a call again, the Part is copied to change positions) and
  `skyrim/actor/pose.zap` repeat `skin.zap`'s `poseWorlds`; `skyrim/hkx/spline.zap` is a B-spline
  beside `engine/scene/curve.zap`; one remains
- [ ] an audio bus (`engine/audio/bus.zap`, new): categories with inherited volume, distance
  curves, ducking, crossfade and music by priority, taken from `game/sound/book.zap` and
  `music.zap`
- [ ] `engine/swf`'s AVM1 resolves bindings once and offers `player.on("CloseMenu", fn)`
  (`interface/hud.zap` builds `"{base}.Set{name}MeterPercent"` each frame and each menu compares
  names); skyrim's menus use it and the per-frame string building is gone
