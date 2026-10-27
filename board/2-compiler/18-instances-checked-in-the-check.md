---
size: M
priority: P2
---
# Scripts: generic instances are checked later, in the code phase

The check phase checks every instance of a generic function a script uses, which is 5% of a small
build. When a kept form is taken for that instance, the check was wasted.

- [ ] put the checking of instances off to the code phase, where a taken form skips it; the
  instances are then recorded in another order, so the executable's functions are laid out
  differently, and a test that compares layouts must expect it. A small script's check phase
  falls by most of the 5% in the build timing
- [ ] the instances that the program's code inlines are checked again at that point
  (`irInstanceCall`'s `askChecked`): check them once, so the saving is not given back; the bench
  (`zap test --only bench tests/scripts`) shows the ratio
