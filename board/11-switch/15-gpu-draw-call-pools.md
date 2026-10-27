---
needs: [switch-12]
size: XL
priority: P1
---
# The renderer reads the texture pools and shader programs of each draw

Nothing reads the texture and sampler pools or the shader program bytes through the `DrawCall`
(`maxwell/draw.zap`) yet: a renderer must fetch TIC and TSC entries by handle from the texture
constant buffer. Parts of a draw are not decoded: the geometry's viewport index, stencil, logic
ops, color masks, transform feedback, and indirect and instanced-by-macro draws. A tessellation or
geometry program is recorded but not translated.

- [ ] read the TIC and TSC entries by handle from the texture constant buffer and the program bytes
  from the draw's state, in `render/draw.zap`; a captured draw (`maxwell/drawCapture.zap`) lists
  its textures and programs in a test (`tests/textures.zap`)
- [ ] decode the viewport index, stencil, logic ops, color masks and transform feedback in
  `maxwell/drawState.zap`, each with a test in `tests/maxwell.zap`
- [ ] decode indirect draws and draws instanced by a macro (`maxwell/macro.zap`), with a test
- [ ] translate the tessellation and geometry programs (needs the stages in switch-13)
