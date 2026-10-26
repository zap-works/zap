---
size: L
---
# The 2D frame in the engine

(engine/tiles). compose.zap decides each pixel of each
layer by a call and several tests, `withBrightness` divides three times a pixel, and the windows
are tested a pixel at a time though they are x ranges; DKC's, Lemmings' and Prince of Persia's
frames do the same in their own words. `Layer` (a tilemap of entries, 2, 4 or 8 bits a pixel,
scroll, two priorities, a mosaic), `Sprites`, `Windows` (per layer: x ranges resolved to spans
once a line), a `Blend` (sub screen or fixed colour, add or subtract, halved, by layer) and
`Palette` (15-bit entries, a brightness table of 16 by 32); `composeLine(layers, sprites,
windows, blend, out u16[])` merges by priority in `Simd<16, u16>`, the window spans cutting the
loop's ranges. The SNES keeps its register decoding and feeds the engine's structures; mode 7 and
high resolution are its own layers through the same merge. Measured by frames a second headless
(140 today) and the frame checks against Mesen 2 unchanged.
