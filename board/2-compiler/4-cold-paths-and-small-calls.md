---
size: M
priority: P1
---
# Cold paths and small calls in generated code

A small method's cold path is inlined into every
caller with what it formats: recomp.switch's `Memory.index` noting a fault as `"{n} bytes at
{at:x}..."` put the formatting and a 1.5 KB frame, zeroed at each entry, into every translated
function (190 bytes of x64 a guest instruction, 90 without it); written with the fault kept as
numbers (Memory.faultAt) and formatted where it is read. And small functions called a pixel at a
time are not inlined (recomp's layerColor, combineWindows, the colour math's channels: worked
around by hand).
