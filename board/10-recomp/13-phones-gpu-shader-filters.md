---
size: L
---
# SNES: phone apps draw the picture on the GPU with shader filters

On phones the SNES picture is filtered by the CPU in `projects/recomp/touch/look.zap`, which keeps
the zoom at 3 because zoom 4 cost 16.5 ms a frame on the S26. The look's filters (xBR, CRT) should
be shaders on Vulkan.

- [ ] draw the finished picture with the GPU (Vulkan) on Android, replacing `look.zap`'s CPU work;
  the app shows the same picture (shot equal at zoom 3 without a filter)
- [ ] write the filters (xBR, CRT) as shaders; at zoom 4 the S26's frame time is under 8.3 ms, read
  from the frame-time log
