---
size: M
priority: P2
---
# Scripts: the kept code is placed faster and with smaller frames

Placing the kept stage's code in a script's executable takes about 4 ms for 150 to 200 functions
(each form record read, its asks made again, its code placed). Also the backend's functions that
move an `IrMade` (`irShip`, `irPipeDrain`, `irKeptForm`, `irEmitMade`) each zero a frame of 7 to 37
KB at every call, because their temporaries' slots are not shared.

- [ ] read and place a kept form's record without making its asks again; the timing of a script's
  build shows the placement below 4 ms
- [ ] share the temporaries' slots in those four functions (or move the `IrMade` by reference) so
  their frames shrink; the compiler's own frame sizes (the size baseline) show them under 7 KB
