# Microsoft Excel 1.00 for the Mac recompiled into native Zap

Excel 1.00 run on a Mac written in Zap, from the user's own `.moof` captures of its disks (never
committed). `zap run projects/excel1/prepare.zap` once, then `zap run projects/excel1/main.zap`
opens Excel in a live window: the Mac's screen scaled by whole pixels, the real mouse and keys
(Ctrl as Command) and clock fed to the Mac; the headless options (`--headless`, `--input`,
`--shot`, `--idle`, `--expect`, ...) keep the checks windowless (`driver/driver.zap` lists them);
a crash writes its log to `excel1/crash.txt`. Excel's About box, from the Apple menu, against the
screenshot kept with the disks:

    zap run projects/excel1/main.zap --idle 90 --input "down 10 20; move 30 30; up 30 30" --expect ...

## Layout

`disk/` and `disks/` read the captures; `m68k/` is the 68000, one decoder, one lowered form, an
interpreter and a recompiler (`recomp.zap` writes `recomp/excel.zap` from the code a run reached,
`main.zap --reached`; `list.zap` lists a code resource's instructions); `mac/` the Mac (the
Toolbox, the `.Sony` driver, the IWM); `cpu/`, `driver/`, `tests/`.

## State

The floppy drive reads each track's captured bits as the drive's head would, its weak cells as the
amplifier's noise, and the `.Sony` driver runs Excel's own `JRdData` against the IWM, so Excel's
copy-protection check passes with its code unmodified. Excel runs to its worksheet window and,
driven by `--input`, opens its About box, which matches the screenshot but for 17 pixels. The
recompiled segments are the driver's fast path and end in the interpreter's machine state
(`--state`). Live, it still dies on a Toolbox trap not written yet. Set aside at this state.
