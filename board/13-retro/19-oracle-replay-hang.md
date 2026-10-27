---
size: S
---
# Prince of Persia: the oracle exits after a replay ends at the title

The headless SDLPoP oracle (built in the scratchpad from SDLPoP's source, never committed) hangs at
the title screen after a replay ends, and has to be killed. That blocks scripted runs that play a
replay and then continue.

- [ ] find where the oracle waits after the replay's last frame (the title's loop in its `seg000`
  main loop, which waits on a key or a timer) and make it exit, or return, when the replay ends;
  running `oracle.exe` with `--replay` on a short replay ends by itself with its exit code 0
