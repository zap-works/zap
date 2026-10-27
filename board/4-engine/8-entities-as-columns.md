---
needs: [engine-7]
size: XL
---
# Entities are stored in columns and walked in parallel

This needs engine-7. Entities are stored one record each; storing each field in its own array
(struct of arrays, as Unity's DOTS and Bevy do) lets the cores walk them in parallel, which is what
a phone's small cores can take. Measure on skyrim's crowd and minecraft.

- [ ] a `Transforms` store in columns with a dirty-flagged hierarchy, uploaded to the GPU in one
  write (in `engine/scene`); skyrim's crowd uploads its transforms in one write per frame
- [ ] walk the projects' entity sets with `.parallel()` over the columns, with a per-frame arena
  reset (Odin, Jai); skyrim's crowd and minecraft frame times fall
- [ ] skyrim's particles allocate each frame (`particles.push` per particle, `shakes` and the quads'
  `out` pushed each frame): keep them in columns without per-frame pushes
- [ ] skyrim's physics keeps `bodyPairs` and the manifolds in lists and runs each pair's SAT in
  turn: keep them in columns and run the pairs in parallel; the physics step's time falls
