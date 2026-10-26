---
needs: [engine-7]
size: XL
---
# Entities as columns

(needs 7). A `Transforms` store in columns (struct of arrays) with a
dirty-flagged hierarchy, uploaded in one write, and the projects' entity sets walked by
`.parallel()` over the columns (Unity's DOTS, Bevy), with a per-frame arena reset (Odin, Jai).
Measured on skyrim's crowd and minecraft, skyrim's particles (`particles.push` per particle,
`shakes` and the quads' `out` pushed each frame) and physics (`bodyPairs` and the manifolds in
lists, each pair's SAT in turn): what a phone's small cores can take.
