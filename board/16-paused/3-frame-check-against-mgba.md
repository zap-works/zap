---
size: L
blocked: set aside: needs a headless mGBA (the Windows build has its GDB stub only in the windowed app)
priority: P3
---
# FireRed: frames are checked against mGBA, frame for frame

The FireRed port (`projects/firered`) should be compared with mGBA frame by frame. That needs a
headless mGBA; the Windows build offers its GDB stub only in the windowed app, and tests may not
open windows.

- [ ] get an mGBA that runs headless with a debugging interface (build the `mgba-headless` frontend
  from source, or another route) and write here how it is run
- [ ] run the same input route in both and compare state and frame hashes at each frame
  (`projects/firered/tests`); the first differing frame is printed, and a full route has none
