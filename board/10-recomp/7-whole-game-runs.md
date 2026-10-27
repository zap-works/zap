---
size: L
---
# SNES: Zelda and DKC are replayed from power-on to the end and match Mesen 2

Whole-game runs compare the recompiled game with Mesen 2 frame by frame over a full playthrough.
`projects/recomp/snes/tests/routes` holds the input routes.

- [ ] Zelda: no USA Zelda movie syncs in Mesen 2 (TASVideos' are made for Snes9x 1.43), but
  zelda3's reference saves (snesrev/zelda3 on GitHub: 13 chapters with input logs, chapter 1 from
  power-on) can drive it once each input is anchored to the game's state changes, since zelda3
  counts the polyhedral cutscenes' frames its own way. Make the route and replay it; the recompiled
  frames equal Mesen 2's through all 13 chapters
- [ ] DKC: replay TASVideos movie 3415M (the 101% run, recorded in BizHawk) with
  `projects/recomp/snes/tools/bk2Route.zap`; the recompiled frames equal Mesen 2's to the movie's
  last frame. A route keyed by frame drifts when a level's load lags a frame more or less in Mesen
  than in BizHawk, so anchor the inputs to the game's state if it drifts
