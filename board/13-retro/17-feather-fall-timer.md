---
size: S
blocked: ask the user what the feather-fall timer should do (SDLPoP only saves it in a quicksave with fix_quicksave_during_feather on, and the port keeps the fixes off)
---
# Prince of Persia: the feather-fall timer follows SDLPoP

The original card read "the feather-fall timer (needs `fix_quicksave_during_feather`)". The port
(`projects/pop`) keeps SDLPoP's fixes off, and the fix flag `fix_quicksave_during_feather` is the
one that lets a quicksave work in feather mode (`game/menuTable.zap`). It is unclear whether the
aim is to carry the feather-fall timer through a quicksave (needing the fix on), or to reproduce
the original's behavior with the fix off.

- [ ] once the user says which, port SDLPoP's handling of the feather-fall timer in
  `game/saveState.zap` and `game/frame.zap`; a quicksave and quickload in feather mode (a test in
  `tests.zap`) gives SDLPoP's result
