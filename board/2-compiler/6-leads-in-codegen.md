---
size: XL
priority: P2
---
# Code generation ideas, each measured alone

Each idea below is tried alone, measured by A/B, then confirmed on programs beyond its own
benchmark (`zap test --only bench`); one that does not pay is dropped and its bullet deleted. The
code is in `compiler/optimize/` and `compiler/targets/x64/`.

- [ ] alias facts from ownership (rustc's `noalias`): a store through one owned list cannot alias a
  load from another list or from a `self` field, so loads live across it and leave loops; memory
  versions per block (LLVM's MemorySSA) make reuse across blocks cheap once split by owner
- [ ] loops: widen `i32` counters to `i64`; turn an `i * stride` index into a stepped pointer; send
  fill and copy loops to the runtime's wide copies; vectorize `while` loops with an early exit by an
  exit mask (GCC 16); lay a loop's blocks out contiguously (.NET 10)
- [ ] grow `irPairs` (`compiler/optimize/irPairs.zap`) into an SLP vectorizer over stores and
  reductions, with identity lanes for a missing twin (LLVM 22): the engine's vec3 and matrix code
  takes the path raytrace's takes
- [ ] inlining limits (`compiler/ir/irLowerFunction.zap`, `ZAP_RUN=irinline`): today 40 nodes for
  the program's own bodies and for runtime bodies called outside a loop in a function with no loop,
  24 inside a loop; measure other limits
- [ ] a box or list made and dropped in one function lives in the frame (.NET 10's escape
  analysis); a drop followed by an allocation of the same size class reuses the block (Koka's
  Perceus); run `irOwnTake` (`compiler/ownership/irOwnTake.zap`) again after inlining (Swift's
  OSSA); add `nothrow` and `terminates` beside `compiler/check/purity.zap`'s pure
- [ ] one table of rewrites read by both `irOpt` and the constant folder (Cranelift's rules); loop
  tiling and interchange beside `irJam`, chosen by a small cost model, nests versioned by size
  (Halide, Futhark)
- [ ] the compiler's own time: the ownership pass snapshots every variable at each branch (find it
  in `compiler/ownership`), and `checkEffects`' list of changed effects
  (`compiler/check/effects.zap`) is quadratic and costs 8% of a check; each falls in a timing of
  the compiler's own cold build
