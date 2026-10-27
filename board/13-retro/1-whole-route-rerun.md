---
size: L
---
# DKC: the whole route is replayed again, keyed by the joypad reads

The 148,700-frame route (TASVideos movie 3415M turned into joypad-read-keyed inputs by
`projects/recomp/snes/tools/bk2Route.zap`; see `projects/dkc/README.md`, "Whole-game route") must be
replayed after the changes made since, and its pictures looked at.

- [ ] play the route: `build/dkc.exe --headless --frames 148700 --route build/tas/route.txt
  --hashes ...` (about 45 minutes), then `projects/recomp/snes/compare.zap` against
  `build/tas/full.txt`; no frame differs from Mesen 2's
- [ ] look at the shots taken every 10,000 frames, by world, and note anything wrong here
- [ ] run `zap test projects/dkc` once (routes, walkthrough, wide); it passes
