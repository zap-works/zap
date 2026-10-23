# TODO: Donkey Kong Country

1. The whole route again, keyed by the joypad reads: `build/dkc.exe --headless --frames 148700
   --route build/tas/route.txt --hashes ...` (about 45 minutes), `recomp.snes/compare.zap` against
   `build/tas/full.txt`, the shots at every 10,000 frames looked at by world, and `zap test
   projects/dkc` (routes, walkthrough, wide) run once.
2. Every level reached by a route (the rest of milestone 5).
3. The widescreen measured again on that route, by stage; water, vertical and moving-margin levels
   (Slip-Slide Ride) need a route that reaches them, their calibration unproven until one does.
4. The game's logic above the cartridge's 60 frames a second (today only the picture, by
   interpolation).
