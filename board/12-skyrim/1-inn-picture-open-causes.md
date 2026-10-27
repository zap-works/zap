---
size: L
---
# The inn's picture matches the game's captures (milestone 4)

The Sleeping Giant Inn is compared with captures of the real game (`projects/skyrim/compare.zap`,
the poses in `reference/poses.json`; the total error is 544.0 today). These differences have no
known cause yet. Each task is a hunt: find the cause in the game's files or code (the executable's
export in `C:/tools/skyrim-decomp`, `projects/recomp/tools/decompInfo.zap`), fix it, and see the
pose's error in `compare.zap` fall.

- [ ] Orgnar's place in the captures, and the fire's and smoke's random draws, differ from ours;
  match them to the captures
- [ ] thin bluish lines appear at the top of the fire's mesh flames at eye height
  (`FireplaceWood01Burning.nif`, `FXFireAtlas04` through `GradFireExplosion`, billboard mode 1, V
  scrolled over 5.67 s), which the game does not show; the cause is not found from the files alone,
  so read the executable's draw of that billboard; the lines are gone
- [ ] the ambient light's true form (the executable's, at full strength) totalled less than the flat
  mean when it was measured, and the reason is unfound, floors being where the game is darker than
  any ambient gradient gives; find it and use the true form
- [ ] light flicker in play: `world/flicker.zap` keeps the measured form until the term of ours that
  is about 20% too bright is found (the executable's form ported totalled 346.6 then; the render
  captures pin the executable's dimmers per pose); find the term
- [ ] TAA's `BlendParams` (0.8 at rest, 0.5 at speed, post sharpen and overlay 0.21) took the
  backroom pose from 95.1 to 91.1 with the weight alone; find why only the weight matched
- [ ] the ambient occlusion's motion vectors are ours, from the depths and the views, not the
  game's; compute them as the game does
- [ ] remeasure the up, down and side bias by facing per pose under the y fix: draw the normals
  through the `--ids` pass (`n * 0.5 + 0.5`), then ours minus the game's by normal y
- [ ] the depth bias of the interior shadow lights: `fShadowBiasScale` 0.15 comes from the mod
  guides' default preferences; the executable holds the name but the value was not read; read it
  and use it
