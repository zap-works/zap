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

`arm64/` decodes A64 (Arm v8.0, the Cortex-A57's) into `Instr`; `cpu/` holds a thread's
registers, the guest memory and what each instruction does (`execute`), the same functions the
translation will call with constant fields.

The oracle is the arm64 machine itself: `tools/armoracle.zap` sends gdb on the arm64 host
(ZAP_BENCH_HOST) random words of each encoding class (`oracle/generate.zap`) with random
registers, vector registers and a scratch memory; gdb steps each once and prints the state, which
`cpu/tests/vectors.zap` compares with ours (`vectors.txt`, 100 a class; ZAP_ARM_VECTORS names
another file). A word the machine refuses must decode as unknown.

State: the integer, branch, system and memory groups and the vector structures (ld1-ld4,
st1-st4, ld1r-ld4r) match the machine on every case (17,000 run). `tools/coverage.zap` on BotW's
main: 90.9% of its 5.8 million words decode before the FP and Advanced SIMD groups; those two
are being written.

Left: scalar FP and Advanced SIMD; the loader (NSO, NRO), the interpreter's loop and the
kernel's first SVCs for a homebrew; then the translation (functions from the entry, `bl` targets,
`.eh_frame`'s FDEs, adrp+add pairs and relocations, as SavageWindRecomp finds them; jump tables
resolved by running the instructions before the `br`; other indirect branches through a table
from address to function, and the interpreter for code never seen); for a homebrew, an
emulator's trace as the oracle.

## 3-6

Not started: Horizon HLE (SVCs, IPC, the services BotW asks for), GPU (Maxwell/NVN, shaders to
Vulkan), audio and controls (touch overlay of projects/recomp/touch, pads, hid touch), and the run
from the Shrine of Resurrection to the Great Plateau at 30 fps on Redroid.
