# Engine

A 2D, 2.5D and 3D engine written in Zap, over Vulkan 1.4 (1.3
where the driver has no 1.4) or Direct3D 12.

- **`engine/`**: windows and input, sprite batches, meshes (OBJ, glTF with skinning), textures
  (PNG read by std's `image`), text from system fonts, render targets, screen passes and
  shaders written in Zap. Beside them, what games keep needing:
  - `scene/camera.zap`: an orbit camera (a drag turns and tilts it, the wheel zooms), a free flying one
    (W A S D, E Q, Shift), and the ground under a screen pixel (`rayThrough`, `groundHit` against
    a height function);
  - `color.zap`: `rgb8`, `white` and `black` (the projections, views, placements and turns are
    std's `math`: `Mat4.perspective`, `Mat4.placement`, `Quat.about`, `q.rotate(v)`);
  - `post/post.zap` and `post/post.gpu.zap`: bloom (a bright pass, then a blur across and up between two
    half-size HDR targets), ACES tone mapping and FXAA; a program with its own composite draws it
    between the bloom and the FXAA (`projects/examples/post/main.zap` checks it on either backend);
  - `scene/mesh.zap`: smooth normals of triangles, per vertex or per corner within smoothing groups;
  - `app.zap`: the frame loop's command line (`--frames N`, `--uncapped`, `--shot x.png`,
    `--frametimes` with `printFrames` and `fpsText`, `--step MS` for frames of a fixed length so a
    scripted run draws the same pictures every time, `--bench N` for N measured frames after a
    60-frame warm-up: time, processor cycles and memory printed);
  - `window.zap`'s input: `keyDown` (held now) and `keyPressed` (went down this frame) of a
    `Key` (`.Char('W')`, `.Space`, `.F(1)`), `keyAxis`, the same pair for the mouse (`mouseDown`,
    `mousePressed`), `mousePosition` and `mouseMotion` as an `IVec2`, `wheelTurn` in notches and
    their fractions, `lockMouse` and `captureMouse` (`isMouseLocked`, `isMouseCaptured`);
    `font.zap`'s `drawLabel` and `drawTextCentered`.
- **`engine/audio/`** (`import engine.audio`): sound through WASAPI on a thread of its own:
  effects played by voices (volume, pan, pitch, looping, fades, 3D placement from a listener),
  music streamed with crossfades, and decoders written in Zap for WAV (PCM, float, IMA and
  Microsoft ADPCM), MP3 (MPEG-1/2/2.5 Layer III) and Ogg Vorbis. `projects/examples/audio/main.zap` plays
  them, `projects/examples/audio/check.zap` compares the decoders with ffmpeg, `projects/examples/audio/bench.zap`
  measures the mixer.
- **`engine/memoryMap/`** (`import engine.memoryMap`): a guest's memory map as page tables, for
  the recompilers (projects/recomp): one list of bytes holding every memory and tables of where
  each page's reads and writes land (-1: the caller's function answers); `PageMap` one level (the
  SNES's 24 bits in 8 KB pages), `WideMap` two (a 48-bit space in 4 KB pages, the last table kept).
- **`rhi/`**: the render hardware interface, one API over two backends (`rhi/vulkan`,
  `rhi/d3d12`). Vulkan is the default; `ZAP_RUN=gpu=d3d12` or `--d3d12` picks Direct3D 12.

A program imports it as it imports std (`import engine`, `import engine.audio`), wherever it is.
Its tests are `zap test engine/tests`.

## Environment variables

Each variable the engine reads is declared where it is read, with a line saying what it does:
`zap doc environment` lists them.

## Shaders

Shaders are Zap in `*.gpu.zap` files (spec, *Shaders*): typed vertex, instance and
parameters structs, `fn vertex(v Vertex, p Params) (Vec4, Between)` and
`fn pixel(b Between, p Params) Vec4`. The CPU side uses the same structs:

```zap
lit = engine.newProgram(shader(world.vertex, world.pixel))   # a Program: its layout read from the reflection
model = engine.newModel(vertices)   # world.Vertex[]: one buffer, no conversion
mut r = engine.newRenderer()   # the drawing state: the target, depth, blending...
engine.setDepth(r, true, true, true)
engine.setParams(lit, world.Params(viewProjection = vp, picture = stone, lights = lights))
engine.drawModel(r, lit, model)
engine.drawInstances(r, lit, model, copies)   # world.Copy[]: the instance stream
engine.drawGenerated(r, lit, 3)   # a vertex stage of `v i32`: no buffers

post = engine.newScreenPass(shader(post.pixel))   # pixel(uv Vec2, p PostParams)
engine.drawScreenPass(r, post, PostParams(scene = target.colorTexture(), exposure = 1.2))
```

`setParams` writes the struct through the packer the compiler generated for it (numbers into the
program's std140 block, textures by id, `T[]` fields uploaded as storage buffers) and the RHI
uploads the block when it changed; a storage buffer is uploaded only when its elements changed, and
once for every program whose parameters list the same elements (they share it).
A program's parameters stay set until set again. `Mesh` (`newMesh`, `setMeshVertices`,
`drawMesh`) holds vertices that change, `newDynamicModel` and `fillModel` a model refilled each
frame, `drawModelRange` draws a run of a model's vertices. `engine/render/shaders.gpu.zap` holds the
engine's own stages: sprites and skinned bodies (`skinnedVertex`, which a project's pixel stage
pairs with through `Skinned`).

### Bindless textures

A `Texture[]` parameter is a texture array read at an index the shader computes. A
`TextureTable` gives each texture an index once; vertices or a storage buffer of materials name
textures by it, so a scene of many textures and materials is a few draws:

```zap
mut table = engine.TextureTable()
materials.push(Material(color = table.indexOf(stone), lightmap = table.indexOf(page)))
engine.setParams(world, WorldParams(textures = table.textures, materials = materials))
# world.gpu.zap: m = p.materials[b.material]; c = p.textures[m.color].sample(b.uv)
```

The RHI keeps the array's descriptors from draw to draw, one table per frame in flight, written
again only when the list (or a texture in it) changes: on Vulkan a descriptor set of set 1
(descriptor indexing: partially bound, of a variable count, updated after bind), on Direct3D 12
ranges of the shader-visible view and sampler heaps (space 1 + the binding). Each texture keeps
its own sampler. Direct3D 12's sampler heap holds 2048 samplers, so an array there holds fewer
than that.

### Texture formats

`newTexture` and `loadTexture` give a `GpuTexture`, destroyed where it is dropped; shaders and
the sprite batch read its handle, `t.texture()` (a `Texture`). Textures are 8-bit RGBA by default.
`newTexture(w, h, pixels, sampling, format, mips)` makes one
of another `TextureFormat` from its levels' bytes (`pixels` the first, `mips` the smaller ones):
`Rgba8Srgb` (sRGB-encoded, read as linear), `Bc1` and `Bc3` (blocks of 4x4 pixels in 8 or 16
bytes; sizes multiples of 4, their mip levels written, not made) and their sRGB forms;
`levelBytes` says how many bytes a level takes. `projects/examples/compressed/main.zap` checks each reads right on either backend.

### Indexed and indirect draws

For GPU-driven rendering a model is drawn through indices of its own (`IndexBuffer`), a run at a
time or many runs in one call from commands the GPU reads (`DrawCommands`: Vulkan's
`vkCmdDrawIndexedIndirect(Count)`, Direct3D 12's `ExecuteIndirect`), counted by the CPU or by the
GPU (the commands' counter, which a culling pass may write):

```zap
ib = engine.newIndexBuffer(indices)   # u32[]
engine.drawIndexed(r, lit, model, ib, 36, firstIndex = 72, vertexOffset = 1200, instances = 4, firstInstance = 8, copies = places)
commands = engine.newDrawCommands(list)   # engine.DrawCommand[]
engine.drawIndirect(r, lit, model, ib, commands, counted = true, copies = places)
```

Instances come from a model of the program's instance struct (`copies`), read from each draw's
first instance; Direct3D 12 numbers a draw's instances from 0 whatever its first one (Vulkan from
the first), so per-instance values come from the instance stream. `projects/examples/indirect/main.zap`
draws the same quads the three ways on either backend and checks the frames are the same.

## The GPU's time

`ZAP_RUN=gputime` prints every 120 frames (`gputime=N`: every N) the mean GPU milliseconds of
each pass of a frame, named by its targets, from timestamps written before and after each pass
(Vulkan's timestamp queries, Direct3D 12's), read once the frame is done; `ZAP_RUN=draws`
(`draws=N`: every N frames) prints what the draws bound and uploaded.

## Pipelines kept between runs

A pipeline is made the first time a draw needs it (its program, vertex layout, blending and
targets). The RHI keeps the ones a program was drawn with beside the executable
(`<exe>.vulkan-pipelines`, `<exe>.d3d12-pipelines`) with the driver's cache of them (Vulkan's
pipeline cache data, a Direct3D 12 pipeline library), written once no pipeline has been made for
a while and when the window closes. The next run makes them as each program is made, from the
driver's cache, so its first frames make none: Zapnarok's worst frame 82 ms to 2.4 ms on a cold
driver cache, Mario's pipelines 230 ms to 12 ms. A file of another driver or device is used
without the driver's part, a damaged one not at all. `pipelinecache=off` in ZAP_RUN keeps none;
`ZAP_RUN=gpuinfo` prints what the pipelines cost.
