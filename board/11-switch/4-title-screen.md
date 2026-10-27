---
needs: [switch-2]
size: L
priority: P1
---
# BotW shows its title screen and answers the pad

After the boot (switch-2), the game's title screen should draw: the logo and "Press any button".
It then answers the pad, so a button press starts the game.

- [ ] the title screen's frames draw the logo and "Press any button"; a headless shot
  (`projects/recomp/switch/tests/boot.zap` style) equals Eden's frame of the same moment
- [ ] a press on the pad (`controls/pad.zap`) in a scripted run moves the game past the title
  screen; the next frame differs from the title
