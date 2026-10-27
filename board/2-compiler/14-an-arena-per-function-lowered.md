---
size: M
branch: arenas
by: 05c1402a-077b-4bef-a22a-b65dbb8e7ce8
priority: P2
---
# The lowering allocates less on the heap

Other compilers (Go, Jai, Zig) put the lowering's temporaries in one block freed at the function's
end. In Zap, `allocPop`, `listGrow` and `rtFree` cost about 8% of the main thread during the
lowering, so fewer or cheaper heap allocations there is the aim.

- [x] the language's means: `arena:` pauses every statement that calls a function with `mut g`
  (`irStoresOutside`), so an arena around the lowering or the ownership check would allocate on
  the heap all the same; it is not usable until the lowering's functions stop taking `mut g` for
  state they do not change
- [x] lists read only are no longer copied: node kids and subs by index (irDecide, irNotes, copies,
  layout, mutability, givenDef, purity), irReachOf read in place, irOriginStep's call and store
  without a list per instruction, irInScope for the name tests that copied the leaves, the
  taken-out instructions dropped by moving the survivors (irDropTakenOut)
- [ ] remove the lists that remain: `irOriginsOf`'s per-vreg points and holds, `irAppend`'s growth
  of big blocks, and the `.copy()` of an instruction in `irOnFrame` and `irMoveAs`; a profile of the
  compiler's own build shows `allocPop`, `listGrow` and `rtFree` below the 8% of the main thread
