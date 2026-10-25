# Examples: the engine's features checked

One dir a feature of the engine, each a program `zap test` runs on either backend (Vulkan, or
Direct3D 12 with `ZAP_RUN=gpu=d3d12`): `audio/` what mixing costs, rendered offline; `compressed/`
textures of other formats than 8-bit RGBA (BC1 and the others); `compute/` a compute stage;
`indirect/` GPU-driven draws; `post/` post-processing (bloom, tone mapping); `staged/` textures
staged through the frame's ring, which stays its size; `texels/` texels fetched by integer
coordinates (color and integer textures, outside a level 0); `volumes/` 3D textures, cubes and cube arrays, a
shadow map compared at a level and with a bias; `images/` storage images read, written and changed
by atomics in compute stages; `stress/` what the engine's frames cost
when they draw many things (`--bench N`, `--case boxes|sprites|crowd`, `--unsorted`), the
frame-time measure the engine's steps are judged by.
