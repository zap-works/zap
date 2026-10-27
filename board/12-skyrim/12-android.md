---
needs: [skyrim-10]
size: XL
---
# Skyrim runs on Android (milestone 15)

After the frame rate (skyrim-10), the project (`projects/skyrim`) runs on Android. This stands on
engine-4 (the engine's GPU in a phone's window) and engine-5 and engine-7 (compressed assets,
passes kept in the tile).

- [ ] build `projects/skyrim/main.zap` for `android-x64` and run it on the zap37 emulator: the inn
  draws and the player walks in it (a headless shot equals the PC's within the emulator's
  tolerances)
- [ ] run it on the arm64 target (Redroid, then the user's S26 on a hidden display): measure the
  frame time and record it in `projects/skyrim/README.md`
