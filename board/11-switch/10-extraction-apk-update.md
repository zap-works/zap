---
size: M
blocked: ask the user which files of rom/ the APK must pack (the ones the game reads at run time?); BotW's 1.8.2 update also needs its update NSP, which the user does not have
priority: P3
---
# Extraction: the APK holds what the game reads from `rom/`

The Switch recompiler (`projects/recomp/switch`) opens the player's own game into `rom/`
(`tools/extract.zap`, never committed) and `main.zap --android <dir>` builds the app's APK. The
card's first aim is that the APK packs the files the game reads from `rom/`, so the app does not
need them pushed by hand. The second is BotW's 1.8.2 update, which needs the update NSP the user
does not have.

- [ ] list the files of `rom/<title id>` that the game opens during the first slice (the boot to
  leaving the Shrine of Resurrection), from the horizon file service (`horizon/files.zap`)
- [ ] pack those files into the APK (or the app's files) in the Android build; the app on the
  emulator opens them with no adb push, and the title screen draws
- [ ] when the update NSP is available, `tools/extract.zap` applies it and `rom/` holds version
  1.8.2
