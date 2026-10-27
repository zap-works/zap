---
needs: [switch-2]
size: XL
priority: P1
---
# The whole AArch64 translation runs on the phone

BotW's AArch64 code is translated into Zap, built in 131 loadable parts for Android arm64
(`main.zap --android <dir>`), and has to run on the phone. The parts are pushed to the app's files
with adb together with the ExeFS and loaded there. Four things are missing:

- [ ] run the whole translation on the phone: the parts pushed with adb and loaded by the app; the
  app reaches the same turn as the Windows run (`tools/run.zap` counts turns) with the same
  registers at a chosen address
- [ ] resolve the 258 jump tables still unresolved (`tools/coverage.zap` lists the unresolved
  ones); the list falls to zero or each remaining one is explained
- [ ] write forms for the rest of the common operations (bitfield, floating point) in
  `forms/forms.zap` and `cpu/forms.zap`; `tools/coverage.zap` shows fewer functions falling back
  to the interpreter
- [ ] make calls between parts go through a search; a call whose target is in another part runs
  on the phone
