---
size: XL
priority: P1
---
# Leads in codegen

each measured alone by A/B and fired beyond its benchmark:
- [ ] Alias facts from ownership (rustc's `noalias`): a store through one owned list cannot alias a
  load from another or from a `self` field, so loads live across it and leave loops; memory
  versions per block (LLVM's MemorySSA) make cross-block reuse cheap once split by owner.
- [ ] Loops: i32 counters widened to i64; an `i * stride` index as a stepped pointer; fill and copy
  loops to the runtime's wide copies; `while` loops with an early exit vectorized by an exit
  mask (GCC 16); a loop's blocks contiguous (.NET 10).
- [ ] irPairs grown into an SLP vectorizer over stores and reductions, with identity lanes for a
  missing twin (LLVM 22): the engine's vec3 and matrix code by the path raytrace's takes.
- [ ] Inlining limits: 40 nodes for the program's own bodies and for runtime bodies called outside a
  loop in a function with no loop (irLowerFunction.zap), 24 inside a loop (`ZAP_RUN=irinline`).
- [ ] A box or list made and dropped in one function in the frame (.NET 10's escape analysis); a drop
  followed by an allocation of the same size class reusing the block (Koka's Perceus); irOwnTake
  run again after inlining (Swift's OSSA); `nothrow` and `terminates` beside purity.zap's pure.
- [ ] One table of rewrites read by irOpt and by fold (Cranelift's rules); tiling and interchange
  beside irJam, chosen by a small cost model, nests versioned by size (Halide, Futhark).
- [ ] The compiler's own time: the ownership pass's snapshots of every variable at each branch
  (`snapshotMoved`); checkEffects' addChanged (effects.zap), quadratic, 8% of a check.
