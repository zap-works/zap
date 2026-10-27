---
size: M
---
# Skate 3: the skater spawns at the career start

The skater starts at fixed coordinates in the code. The game starts the career at the place named
"gamestart" in its attribute database (`db.big`).

- [ ] read the "gamestart" record of the attribute database in `projects/skate3` (a reader beside
  `projects/skate3/ea` and `rw4`) and print its position and heading
- [ ] spawn the skater there instead of at the fixed coordinates in `projects/skate3/main.zap`; a
  headless shot at start shows him at the career start
