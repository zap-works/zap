---
needs: [switch-2]
size: XL
priority: P1
---
# Horizon HLE and the 3D renderer

whatever the game asks next; the 3D renderer.

The renderer gives the translated shaders (README.md, Maxwell shaders) what they assume: the depth
range the game set (the compiler maps z from -1..1 to 0..1, spec 11), the picture's y as the
guest's (SR_Y_DIRECTION reads 1.0), the vertex formats as Vec4 floats, the constant buffer banks
and the texture handles as the translation reads them.
