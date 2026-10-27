---
size: XL
---
# DKC: the game's logic runs above 60 frames a second

Today a frame rate above the cartridge's 60 frames a second raises only the picture, by
interpolation between two frames (`--fps N` with `--wide`, `console/interpolate.zap` in
`projects/recomp/snes`); the game's logic still steps 60 times a second. The aim is the logic
itself running faster, so motion and input response also improve.

- [ ] design how the game's logic can step at a higher rate without breaking its timing (lag
  frames, music tempo, physics), write the design here, and ask the user if the design changes
  how the game plays
- [ ] implement it for DKC's main loop; at 120 steps a second the game's objects move the same
  distance per real second as at 60, and `zap test projects/dkc` still passes at 60
