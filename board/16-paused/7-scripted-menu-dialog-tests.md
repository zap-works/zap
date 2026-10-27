---
size: XL
blocked: set aside
priority: P3
---
# Excel: every menu, dialog and file path is run by a scripted test

In the Excel 1 port (`projects/excel1`), a live run of a menu command or dialog can die on a
Toolbox trap that is not written yet. Each menu, dialog and file path should be exercised by a
scripted test, writing every trap it reaches.

- [ ] list the menu commands, dialogs and file paths of the program (File, Edit, Formula, Format,
  Data, Options, Macro, Window); a test script in `projects/excel1/tests` drives each, headless
- [ ] run each; every Toolbox trap that stops it is written (`projects/excel1/mac`), until all of
  the scripts finish without an unwritten trap
