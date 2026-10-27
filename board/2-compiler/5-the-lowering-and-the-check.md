---
size: XL
priority: P2
---
# The lowering and the check of one big program use every processor

A build cut into parts already fills every processor, but a single large program does not. The
passes already run as jobs while the round's lowering goes on (`compiler/targets/x64/irPipe.zap`),
so a cold build waits on the serial lowering (recompShape, `tools/recompShape.zap`: 61 s of 100 s,
4,089 functions none over 0.2 s). `ZAP_RUN=lowershared` counts what each adds to the shared state:
most add nothing. The lowering no longer writes the nodes, but the checker calls it reaches still
do, and write about 20 module variables (`typeIndex` and `typesMet`, `dropsHeld`, `waitingBodies`,
the kept stages' asks, the errors' state, the lint's notes and others).

Go's way is to finish every type, layout and instance before the backend (Go stencils generics
there), so the lowering only reads the checker's state and each function lowers alone. The parallel
effect check judges every path, not the one taken, so a `.parallel()` body needs lookup-only copies
of the checker's chains (`sizeOf`, `resolveType`, `isPlainType` and their callees: days of work), or
a stop-and-redo path from about 190 call sites. The other way is parts as processes that load and
check the program and send back their lowered forms, renamed as kept forms are.

- [ ] choose one of the three approaches above, writing the choice and why in this card, and make
  the lowering of independent functions run on several processors; recompShape's cold build no
  longer spends 61 s of its 100 s in serial lowering, and the executable is byte for byte the same
