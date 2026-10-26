---
size: M
branch: arenas
by: 05c1402a-077b-4bef-a22a-b65dbb8e7ce8
priority: P1
---
# An arena per function lowered

(Go, Jai, Zig): the lowering's temporaries in one block freed at the function's end; allocPop,
listGrow and rtFree are about 8% of the main thread.

- [x] the language's means: `arena:` pauses every statement that calls a function with `mut g`
  (irStoresOutside), so an arena around the lowering or the ownership check would allocate on
  the heap all the same; not usable until the lowering's functions stop taking `mut g` for state
  they do not change
- [x] lists read only are no longer copied: node kids and subs by index (irDecide, irNotes, copies,
  layout, mutability, givenDef, purity), irReachOf read in place, irOriginStep's call and store
  without a list per instruction, irInScope for the name tests that copied the leaves, the
  taken-out instructions dropped by moving the survivors (irDropTakenOut)
- [ ] the lists that remain: irOriginsOf's per-vreg points and holds, irAppend's growth of big
  blocks, the `.copy()` of an instruction in irOnFrame and irMoveAs
