---
size: M
blocked: set aside
priority: P3
---
# Excel: About shows 99% free memory, as the screenshot does

The Excel 1 port (`projects/excel1`) shows 98% free memory in its About box where the original's
screenshot shows 99%. The number depends on how much of the Toolbox's heap the program itself uses,
set against the ROM's.

- [ ] find how the ROM computes the free-memory percentage and the heap use that feeds it, and make
  the port's heap use match; the About screen's shot equals the screenshot in
  `projects/excel1/disks/extras/` (the percentage reads 99%)
