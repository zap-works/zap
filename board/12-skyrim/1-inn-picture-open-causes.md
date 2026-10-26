---
size: L
---
# The inn's picture (milestone 4)

- [ ] Orgnar's place in the captures, and the fire's and smoke's random draws.
- [ ] Thin bluish lines at the top of the fire's mesh flames (FireplaceWood01Burning.nif, FXFireAtlas04
  through GradFireExplosion, billboard mode 1, V scrolled over 5.67 s) at eye height, which the game
  does not show; their cause is not found from the files alone.
- [ ] The ambient's true form (the executable's, at full strength) totalled less than the flat mean
  when it was measured: the reason is unfound, floors being where the game is darker than any
  ambient gradient gives.
- [ ] Light flicker in play: `flicker.zap` stays the measured form until the term of ours that is about
  20% too bright is found (the executable's form ported totalled 346.6 then; the render captures
  pin the executable's dimmers per pose).
- [ ] TAA's BlendParams (0.8 at rest, 0.5 at speed, post sharpen and overlay 0.21) took backroom from
  95.1 to 91.1 with the weight alone: the cause is unfound.
- [ ] The ambient occlusion's motion vectors are ours, from the depths and the views, not the game's.
- [ ] Remeasure the up, down and side bias by facing per pose under the y fix: normals drawn through
  the `--ids` pass (n * 0.5 + 0.5), then ours minus the game's by normal y.
- [ ] The depth bias of the interior shadow lights: fShadowBiasScale 0.15 comes from the mod guides'
  default prefs; the executable holds the name, the value was not read.
