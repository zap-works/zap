# TODO: Prince of Persia

1. A headless SDLPoP oracle built with its menu (no SDL2 here), to check the menu's pixels against
   SDLPoP's; the other items below were checked only by reading SDLPoP's C.
2. The visuals settings (fullscreen, scaling, fade, lighting, hardware acceleration) and the
   controller's are stored and saved, but the host acts on none of them but flash and music.
3. The feather-fall timer (needs fix_quicksave_during_feather).
4. The key dialog is drawn on the layer without SDLPoP's offscreen restore.
5. The oracle's replay playback hangs at the title after a replay ends (it has to be killed).
