---
needs: [retro-2]
size: M
---
# DKC: widescreen is measured by level on the full routes

DKC's widescreen (`projects/dkc/wide`) was measured on the whole TAS route, which reaches no water,
vertical or moving-margin level (Slip-Slide Ride), so the calibration for those is unproven: where
it fails the scene is centred, never wrong. Retro-2 gives routes that reach them.

- [ ] play `--wide --wide-native-logic` over the routes of retro-2 and record, per level (by
  source: tilemap, vertical, water, moving margin), how many frames are widened and how many are
  centred; write the table in the README
- [ ] for each level kind that is centred where it should be wide, fix the scene gate and the
  camera range in `projects/dkc/wide`; the work RAM and native pictures still match Mesen 2's
