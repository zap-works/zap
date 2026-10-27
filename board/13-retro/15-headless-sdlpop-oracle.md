---
size: L
---
# Prince of Persia: the pause menu is checked against a headless SDLPoP

The Prince of Persia port (`projects/pop`) is checked frame by frame against a headless SDLPoP
built from its source, but that oracle has no menu, so the pause menu (`game/menu.zap`,
`menuDraw.zap`, `menuSettings.zap`) was checked only by reading SDLPoP's C. SDL2 is not installed
here.

- [ ] build SDLPoP headless with its menu code and a stub for SDL2's drawing and input (scratchpad,
  never committed), so it can open the pause menu and save the display
- [ ] drive the same key route in both (`check.zap` and the oracle), open each of the menu's pages
  and dialogs, and compare the pixels; any difference is fixed in `game/menu*.zap` until all
  pages match
