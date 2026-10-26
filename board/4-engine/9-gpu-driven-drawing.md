---
needs: [engine-8]
size: XL
---
# GPU-driven drawing

(needs 8). Nothing in engine/ culls: every mesh is submitted by a CPU draw
(scene/mesh.zap, scene/model.zap). An `Aabb` per mesh and a `Frustum` from the camera; a compute
pass culls by frustum and by a two-pass HiZ occlusion test, compacts the survivors into
`DrawCommands`, and one counted `drawIndirect` per material draws them (the indirect path and
`setDrawCount` exist); skins posed only when visible and by a distance LOD. Measured by
`gputime` and frame time on skyrim and minecraft.
