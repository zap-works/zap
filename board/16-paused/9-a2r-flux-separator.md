---
size: L
blocked: set aside
priority: P3
---
# Excel: disk tracks are read from the `.a2r` flux captures

The Excel 1 port (`projects/excel1/disk`) reads the floppy tracks from the `.moof` bits with a noise
model. Where the turns of a track disagree, the `.a2r` flux captures should be the source,
read through a data separator the way MAME's floppy code reads flux.

- [ ] write the data separator in `projects/excel1/disk` that turns a flux capture's transition
  times into bits (as MAME's floppy code does), with a test on a known track
- [ ] use it as the track source where the `.moof` turns disagree, replacing the noise model; the
  disk boots with the same checks, and the tracks that disagreed read the same bits on every turn
