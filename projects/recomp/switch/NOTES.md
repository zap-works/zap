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

    zap run projects/recomp/switch/main.zap <homebrew.nro> [--out <dir>] [--build]

`arm64/` decodes A64 (Arm v8.0, the Cortex-A57's) into `Instr`; `cpu/` holds a thread's
registers, the guest memory and what each instruction does (`execute`). `translate/` finds the
functions (the unwind tables' FDEs through MOD0, the entry, every bl's target) and writes each as
a loop over a match of its labels (its start, branch targets inside it, the places after calls
and supervisor calls), every instruction a call of `execute` with the decoded instruction written
as a literal. A function may be entered at any label and returns as soon as the guest leaves it,
so a thread that yields (a supervisor call, its slice spent) unwinds to `cpu/dispatch.zap`, which
goes on later from the thread's pc: the host's stack is only a short cut, the guest's holds the
return addresses, and the kernel runs the threads in turns on one host thread. Code the
translation did not see runs on the interpreter, block by block.

Oracles:
- Each instruction against the arm64 machine itself: `tools/armoracle.zap` sends gdb on the arm64
  host (arm64 in ZAP_SETUP) random words of each encoding class (`oracle/generate.zap`) with random
  registers, vector registers, FPCR and a scratch memory; gdb steps each once and prints the
  state, which `cpu/tests/vectors.zap` compares with ours (`vectors.txt`, 100 a class;
  `vectors=<file>` in ZAP_RUN runs another file). A word the machine refuses must decode as unknown.
- A whole homebrew against Eden: `tests/homebrew/hello.c` (written to compare, built with libnx
  in the devkitpro/devkita64 container by `tools/homebrew.zap`) is run by Eden's eden-cli on the
  arm64 host, headless (`tools/eden.zap` fetches and sets it up; it wrote `hello.txt`), and
  `tests/homebrew.zap` runs it interpreted and translated.

State: integer, branch, system, memory, vector structures, scalar FP (exact, FPCR's modes and
FPSR's flags) and Advanced SIMD's integer, permute and crypto groups match the machine on every
case. The homebrew (integers, doubles and floats through printf, two threads with a mutex and a
condition variable, the counter) prints what Eden prints, interpreted and translated, on Windows,
on the zap37 emulator (Android x86-64) and on Redroid (Android arm64). `tools/coverage.zap` on
BotW's main: 93% of its 5.8 million words decode; the rest is almost all vector FP.

The common instructions (loads and stores of one register or a pair, add, logic, moves, adr,
csel, the conditional branches' tests) are forms written once in `forms/`: the translation writes
them with known fields (`c.x[3] = c.x[1] + u64(16)`, 50 times faster than a call of `execute` and
30 times faster to compile), and the interpreter's functions for the same operations are written
from them into `cpu/forms.zap` (`tools/forms.zap`; `cpu/tests/forms.zap` checks it is current),
so the oracle checks the forms.

Scale: BotW's ExeFS is 141,297 functions, 19 million lines of Zap; the compiler holds about 6 KB a
line at its peak (TODO's bugs), so the whole cannot be built on 16 GB. Meanwhile `tools/run.zap
--profile f` records the blocks a run entered and `main.zap --profile f` translates only the
functions holding them; the interpreter runs the rest (about 8 million instructions a second).
`tools/coverage.zap`: 99.9% of main's words decode (15 of 5.8 million do not).

Left: the compiler's memory per line (or a translation smaller per instruction), forms for the
rest of the common operations (bitfield, FP), jump tables, direct tail calls.

## 3. Horizon HLE

`horizon/` is the kernel (kernel, svc, sync, threads, space, process, loader: the supervisor calls, the
threads run in turns on one host thread) and the services behind its IPC sessions (`ipc.zap`: CMIF,
TIPC and domains; `services.zap`: the Service objects and `dispatch` by interface name; `sm.zap`). Each
family is a file: applet.zap (appletOE and the controllers an application runs under), lm.zap,
set.zap (set, set:sys), accounts.zap (acc:u0, one user), clock.zap (time:u/a/s, UTC), files.zap
(fsp-srv: the RomFS as an image built from rom/<title>/romfs/ by package/romfsimage.zap, save data
and the SD card as dirs under out/), fonts.zap (pl:u: the firmware's fonts as BFTTF in a shared
memory), hid.zap (the shared memory, all zeros), apm.zap, addons.zap (aoc:u), parental.zap (pctl).
A command no file knows is noted in the log (`--calls` shows every request) and answered with
success and no outputs.

    zap run projects/recomp/switch/tools/run.zap <exefs dir> --steps 2000000000 --calls

State: Breath of the Wild 1.0.0 passes rtld and the SDK's start, asks sm:, lm, appletOE (and its
controllers), apm, aoc:u, pctl:a and fsp-srv (it reads the RomFS header and tables), then nvdrv and
vi:m/vi:s/vi:u, where it stops: vi:m #2 (GetDisplayService) is not written. tests/services.zap checks
the families by direct requests. The run needs 3.3 GB of heap, more than `zap test` allows a process.

Left: vi, nvdrv (NVN's ioctls) and audren; then the services the game asks after them (hid, set, acc,
time and pl:u are written but not yet reached by the game; nifm, friends, prepo, bcat, ssl, nfp when
asked).

## 4-6

Not started: GPU (Maxwell/NVN, shaders to Vulkan), audio and controls (touch overlay of
projects/recomp/touch, pads, hid touch), and the run from the Shrine of Resurrection to the Great
Plateau at 30 fps on Redroid.
