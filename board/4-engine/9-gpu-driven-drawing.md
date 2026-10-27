---
needs: [engine-8]
size: XL
---
# The GPU decides what to draw

This needs engine-8. Nothing in `engine/` culls: every mesh is submitted by a CPU draw
(`engine/scene/mesh.zap`, `model.zap`). Measure with `ZAP_RUN=gputime` and frame time on skyrim and
minecraft.

- [ ] give each mesh an `Aabb` and the camera a `Frustum`
- [ ] a compute pass culls by frustum and by a two-pass HiZ occlusion test and compacts the
  survivors into `DrawCommands`; one counted `drawIndirect` per material draws them (the indirect
  path and `setDrawCount` already exist). Skyrim and minecraft draw the same pictures (shots) with
  less CPU time
- [ ] skins are posed only when visible, and by a distance LOD; the posing cost falls on skyrim's
  crowd
