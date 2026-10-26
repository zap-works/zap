---
size: L
---
# The per-frame costs

each measured by frame time (`projects/examples/stress`, `--bench N`,
`--case boxes|sprites|crowd`, `--unsorted`): `readBuffer` and `readStorage` on `waitIdle` (a
readback ring read one frame late, once a program reads back each frame); HDR and MSAA targets
in RGBA16F (R11G11B10F, a transient MSAA target, reverse-Z). For the phone, where the fragment is
the bottleneck: lights by cluster (skyrim's `paramsOf` sends every light and each fragment walks
`lightCount`), shadows of lights that do not move made once (the inn's, when skyrim's milestone 5
adds them), an `f16` type in the shaders' language for colours, normals and uvs (Mali's
`mediump` doubles the throughput), and `Frames` with a target rate and pacing (vsync,
`VK_GOOGLE_display_timing`) so a phone does not heat and lose its clock.
