---
size: XL
---
# The lowering and the check per function on every processor

for a single large program (a
build cut in parts already fills every processor). Go's way: the frontend finishes every type,
layout and instance before the backend (Go stencils generics there), so the lowering only reads
the checker's state and each function lowers alone. The passes already run as jobs while the
round's lowering goes on (irPipe.zap), so a cold build waits on the serial lowering (recompShape:
61 s of 100 s, 4,089 functions none over 0.2 s; `ZAP_RUN=lowershared` counts what each adds to
the shared state: most add nothing). The lowering no longer writes the nodes, but the checker
calls it reaches still do and write about 20 module variables (typeIndex and typesMet,
dropsHeld, waitingBodies, the kept stages' asks, the errors' state, the lint's notes...). The
parallel effect check judges every path, not the one taken, so a `.parallel()` body needs
lookup-only copies of the checker's chains (sizeOf, resolveType, isPlainType and their callees:
days of work), or a stop-and-redo path from about 190 call sites; or parts as processes that
load and check the program and send back their lowered forms renamed as kept forms are.
