---
size: XL
---
# The kept stages' leftovers

(spec 14.2). With cpu and game modules kept, recompShape's program
rebuilds after an edit of its entry in 1.9 s instead of 11.4, now mostly its load (1.0 s; Scripts
3) and write; FireRed's (projects/firered/recomp/firered.zap, every stage kept through game) in
4.3 s: load 0.5, check 1.7 (findEffects over the whole game: compiler-21), code setup 0.7, code
0.6, write 0.7. Left: a module with GPU files, a shader's call or `parts` (engine, rhi.d3d12)
has no index (moduleIndex.zap), so it is parsed and walked though a kept stage holds it.
The program's own functions keep their forms (keptEntry.zap), keyed per declaration with an
early cutoff (keptEntryKeys.zap), and those nothing calls keep their checks: an edit of the
compiler remakes 16 forms (a body), 23 (a new function), 57 to 62 (a signature, a callee's
effects, lines added in a body) of 3,723, its code phase 3.4 to 4.2 G cycles against 19 to 22
when all are made; a field of `Ty`, which most of the checker reads, remakes 2,172. The check is
now the largest phase (6.3 to 7.0 G cycles; its bodies 2.6 to 2.8 G of the entry's). Left: the
check per function kept (Roslyn, rust-analyzer): of the entry's 5,074 declarations checked, 3,399
add nothing to the checker's shared state but cost 8 M cycles; 1,351 more append nodes (results
written, lambdas made of placeholders) and 324 make types, instances or lambdas (1.9 G), all in
the order a cold check makes them, which a kept check would have to replay (the arena's nodes,
the types' ids, the instances, the lambdas' numbers) with the node fields its walk writes and
what it decides for other functions (inferred results, receivers made mut); a function that
makes lambdas or instances of the program's generics never keeps its form; a build that makes
every form holds them all (the compiler's peak 0.54 GB to 0.76).
