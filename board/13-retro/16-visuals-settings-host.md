---
size: M
---
# Prince of Persia: the host acts on the visuals and controller settings

The pause menu's visuals settings (fullscreen, scaling, fade, lighting, hardware acceleration) and
the controller's are stored and saved (`game/settings.zap`, `SDLPoP.cfg`), but the host
(`projects/pop/main.zap`) acts on none of them except flash and music.

- [ ] make `main.zap` act on each setting: fullscreen and scaling set the window, fade and lighting
  change the drawing as SDLPoP's do, and the controller settings change the pad's mapping; changing
  a setting in the menu changes the running window
- [ ] a setting that cannot apply on this host is listed in `projects/pop/README.md` as ignored,
  with the reason (hardware acceleration has no meaning in the engine, for instance)
