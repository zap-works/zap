---
size: S
---
# Prince of Persia: the key dialog restores the screen under it

The key redefinition dialog of the pause menu is drawn on the layer without SDLPoP's offscreen
restore, so what was under the dialog is not put back when it closes as SDLPoP puts it back.

- [ ] find the dialog's drawing in `projects/pop/game/menuDraw.zap` and add SDLPoP's offscreen
  restore (`restorePeel` and `copy_screen_rect` in `game/draw.zap`); closing the dialog leaves the
  menu's pixels exactly as before it opened (a test in `tests.zap` compares the two displays)
