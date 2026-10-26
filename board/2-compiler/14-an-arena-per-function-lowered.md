---
size: M
---
# An arena per function lowered

(Go, Jai, Zig): the lowering's temporaries in one block freed
at the function's end; allocPop, listGrow and rtFree are about 8% of the main thread.
