---
size: XL
priority: P2
---
# An edit rebuilds only what it changed in the program's own module

Spec 14.2 describes the kept stages: the runtime, std and chosen modules are stored already checked,
lowered and as machine code, so a build reads them instead of redoing them. With the cpu and game
modules kept, recompShape's program (`tools/recompShape.zap`) rebuilds after an edit of its entry in
1.9 s instead of 11.4, now mostly its load (1.0 s) and write. FireRed's
(`projects/firered/recomp/firered.zap`, every stage kept through game) takes 4.3 s: load 0.5,
check 1.7 (`findEffects` over the whole game: compiler-21), code setup 0.7, code 0.6, write 0.7.

The program's own functions keep their forms (`compiler/targets/x64/keptEntry.zap`), keyed per
declaration with an early cutoff (`keptEntryKeys.zap`), and those nothing calls keep their checks:
an edit of the compiler remakes 16 forms (a body), 23 (a new function), 57 to 62 (a signature, a
callee's effects, lines added in a body) of 3,723, its code phase 3.4 to 4.2 G cycles against 19
to 22 when all are made; a field of `Ty`, which most of the checker reads, remakes 2,172. The check
is now the largest phase (6.3 to 7.0 G cycles; its bodies 2.6 to 2.8 G of the entry's).

Of the entry's 5,074 declarations checked, 3,399 add nothing to the checker's shared state but cost
8 M cycles; 1,351 more append nodes (results written, lambdas made of placeholders) and 324 make
types, instances or lambdas (1.9 G). They all happen in the order a cold check makes them, which a
kept check would have to replay (the arena's nodes, the types' ids, the instances, the lambdas'
numbers) along with the node fields its walk writes and what it decides for other functions
(inferred results, receivers made mut). A function that makes lambdas or instances of the program's
generics never keeps its form, and a build that makes every form holds them all (the compiler's
peak is 0.54 GB, 0.76 with all forms).

- [ ] index a module that has GPU files, a shader call or `parts` (engine, rhi.d3d12) in
  `compiler/driver/moduleIndex.zap`, so a kept stage holding it stops it from being parsed and
  walked; the load time of an engine program with a kept stage drops
- [ ] keep a function's check between builds (as Roslyn and rust-analyzer do): record what a check
  adds to the shared state and replay it in a cold check's order, so the 3,399 functions that add
  nothing are skipped first; the compiler's edit-and-rebuild check phase falls below 6 G cycles
  while the executable stays byte for byte the same
