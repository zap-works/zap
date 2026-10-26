---
needs: [switch-11]
size: XL
---
# GPU: the renderer reads pools and programs

nothing reads the pools or the program bytes through the DrawCall yet (a renderer fetches TIC/TSC
entries by handle from the texture constant buffer); geometry's viewport index, stencil, logic ops, color
masks, transform feedback, indirect and instanced-by-macro draws are not decoded; a tessellation or
geometry program is recorded but not translated.
