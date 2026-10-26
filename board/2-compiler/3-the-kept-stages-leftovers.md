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
The program's own functions keep their forms too (keptEntry.zap): an edit of one body of the
compiler rebuilds it in 4.4 s against 10.3 (code 7.6 s to 1.0; check 1.5 to 2.0 is now the
largest). Left: the forms' key holds one hash of all the module's declarations and facts, so a
signature, a new function, a struct's field or a function whose effects change makes every form
again (a key per declaration the function's check read, facts per callee); the unreached
functions are still lowered and checked each build (0.3 s: keep their checks under the same
keys); a function that makes lambdas or instances of the program's generics is never kept; a
build that makes every form holds them all (the compiler's peak 0.54 GB to 0.76). The keys per
declaration cut off early, as Rust's red-green: a declaration checked again whose signature,
type and facts come out the same leaves its dependents' forms kept. The check per function
kept the same way (Roslyn, rust-analyzer): a body whose text and what it read are unchanged
takes its checked types and inferred result instead of being checked again.
