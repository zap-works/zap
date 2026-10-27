---
size: M
---
# SNES: phone apps are smooth, in sound and at 120 fps

The SNES apps built for Android (`--android`, touch controls in `projects/recomp/touch`) have not
been seen on the user's S26 since three changes: the performance hints, the sound feed's lead and
the pacing to the clock. The player saw tearing and rough sound before them. Phone checks run on a
hidden display, never in front of the user.

- [ ] run the apps on the S26 and read smoothness, sound and tearing from a recording or the
  frame-time log; write the result here
- [ ] pace the pictures by the display (`AChoreographer`) instead of the clock, between the
  cartridge's 60.1 Hz and the screen's 60 or 120 Hz; the frame times show no drops or doubled frames
- [ ] at 120 Hz, show interpolated frames (`console/interpolate.zap`) and measure the frame time
  on the S26 to be under 8.3 ms
