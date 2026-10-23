# recomp.switch: a Switch game recompiled into native Zap

The goal: Zelda: Breath of the Wild played on Android arm64, by touch or a pad, its AArch64 code
translated ahead of time into Zap, Horizon's services written in Zap (HLE), the GPU's commands and
Maxwell shaders drawn through rhi/ on Vulkan. Windows only builds the APK. Nothing of the game,
the firmware or the keys is in the repository (`.gitignore`: `rom/`, `out/`).

Community work read as reference and oracle, never as a dependency: SavageWindRecomp (BotW 1.8.2
recompiled to C, MIT), ScarletNX (a generic ARM64 recompiler with an APK, GPL-3), Eden and
Citron (Android emulators, their touch layout), switchbrew.org, Ryujinx's Maxwell shaders, the
zeldaret/botw decompilation.

## 1. Extraction

    zap run projects/recomp/switch/tools/extract.zap <dir>

`<dir>` holds `prod.keys` (and `title.keys`), the game's NSP and the firmware (a zip, or its NCAs
in a dir); without prod.keys the tool stops saying how to dump them. It writes into `rom/`:

- `<title id>/exefs/`: main, rtld, sdk, subsdk0-3 as NSOs stored whole (LZ4 undone), main.npdm.
- `<title id>/romfs/`: the RomFS's files.
- `<title id>/control.nacp`, `info.txt`: name, version, main's build id and what
  `package/games.zap` knows it as.
- `firmware/version.txt`, `firmware/fonts/*.ttf` (the shared fonts, BFTTF undone).

A file already there with its size is not written again, so a second run takes seconds.

`package/` reads the formats: keys files and tickets, PFS0, NCA3 (header in XTS, sections in
CTR by the key area or the title key), RomFS, NSO, BFTTF. AES-128 is std's `cipher`.

State: the user's NSP (v0) is BotW 1.0.0, main's build id 2094f152836683a3632c6153fd84ab80
(ZeldaMods' table agrees), 64-bit (main.npdm's flags 0x03). 39,678 RomFS files (14 GB). The
firmware is 22.5.0, 7 shared fonts. SavageWindRecomp targets 1.8.2 (main de0b6ac4efc1dda7): its
findings carry over to 1.0.0 by meaning, not by address.

Left: the APK packs what the game reads from rom/ (step 5's work); BotW's updates (1.8.2) need
the update NSP, which the user does not have.

## 2. AArch64 translation

Not started. Plan: functions found from the entry, `bl` targets, `.eh_frame`'s FDEs, adrp+add
pairs and relocations (SavageWindRecomp's sources); jump tables resolved by running the few
instructions before the `br`; every other indirect branch through a table from address to
function, and code never seen run by an interpreter written from the same semantics. The oracle
for each instruction is the arm64 machine itself (ssh lucas: gdb sets the registers, steps one
instruction, reads them back); for a homebrew, an emulator's trace.

## 3-6

Not started: Horizon HLE (SVCs, IPC, the services BotW asks for), GPU (Maxwell/NVN, shaders to
Vulkan), audio and controls (touch overlay of projects/recomp/touch, pads, hid touch), and the run
from the Shrine of Resurrection to the Great Plateau at 30 fps on Redroid.
