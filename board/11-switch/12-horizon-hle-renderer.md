---
needs: [switch-2]
size: XL
priority: P1
---
# Horizon services answer what the game asks and the 3D renderer draws

Horizon is the Switch's operating system; the recompiler answers its services in Zap
(`projects/recomp/switch/horizon`), a high-level emulation (HLE) of each. Two parts remain: the
services the game asks next, and the 3D renderer (`render/`).

The renderer must give the translated Maxwell shaders (see the README's section on them) what they
assume: the depth range the game set (the compiler maps z from -1..1 to 0..1, spec 11), the
picture's y as the guest's (`SR_Y_DIRECTION` reads 1.0), the vertex formats as `Vec4` floats, and
the constant buffer banks and the texture handles as the translation reads them.

- [ ] answer each service call the game makes next in `horizon/`, found by running the boot
  (`tools/run.zap`) until a call stops with "unimplemented"; the boot goes further each time
- [ ] set the depth range the game programmed instead of the default (`render/draw.zap`); a
  captured draw's depth values equal Eden's
- [ ] give the shaders `SR_Y_DIRECTION` = 1.0 and the vertex formats as `Vec4` floats
  (`render/vertices.zap`)
- [ ] bind the constant buffer banks and texture handles the way the translation reads them; a
  captured draw (`maxwell/drawCapture.zap`) renders the picture Eden draws
