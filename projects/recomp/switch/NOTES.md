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
and the SD card as dirs beside the title's, save/ and sd/), fonts.zap (pl:u: the firmware's fonts as
BFTTF in a shared memory), hid.zap and hidinput.zap (the shared memory: a Pro Controller as player 1
and the touch screen, sampled 60 times a second from Kernel.pad and Kernel.touches), apm.zap, addons.zap (aoc:u), parental.zap (pctl).
A command no file knows is noted in the log (`--calls` shows every request) and answered with
success and no outputs.

    zap run projects/recomp/switch/tools/run.zap <exefs dir> --steps 2000000000 --calls

The display and the GPU's interface: vi.zap (vi:m/s/u, layers, the native window), binder.zap
(IHOSBinderDriver over IGraphicBufferProducer: Connect, SetPreallocatedBuffer, DequeueBuffer,
QueueBuffer, Query; a queued buffer waits in `Display.queue` with its nvmap handle, offset, layout
and guest address), parcel.zap, nvdrv.zap with nvmap, nvctrl (syncpoints, events), nvctrlgpu
(a Tegra X1's characteristics), nvas (GPU address spaces) and nvchannel (GPFIFO submission).
`maxwell/` is the GPU behind them: address spaces, GPFIFO entries and pushbuffer methods, classes
bound to subchannels with their registers as arrays, semaphores, syncpoints, inline-to-memory
and DMA copies done for real, draws (3D END) counted per frame. Work completes at submission.
Macro programs (the MME, `maxwell/macro.zap`) run as the driver calls them. Block linear copies
move bytes in order.

`tools/run.zap` ends with the GPU's counts and notes. State: deko_basic.nro (deko3d's triangle)
runs its frame loop, a frame per QueueBuffer, with no unwritten service command
(tests/deko.zap). Breath of the Wild 1.0.0 passes rtld and the SDK's start, sm:, lm, appletOE,
apm, aoc:u, pctl:a, fsp-srv, vi, nvdrv (it opens a channel, makes its pools and maps them),
audren:u, hid (its shared memory, six-axis and vibration), nfp:user (a reader that never finds a
figure), its own save data (there from the launch, as the system makes it) and the threads that map
their stacks and shared memory at random addresses (the heap starts at 2 GiB for them, and what lies
past the guest memory's span is reported inaccessible, so they pick again). Translated from a
profile of its first 1.5 billion instructions (4,900 functions, built in a minute), 800 turns
present 2,343 frames of 1920x1080 with 11,798 draws and 4,685 clears, with no GPU note left; the
pictures are still blank, since draws are not drawn yet (step 4). When every thread waits,
`runFor` says what each waits for.

Left: whatever the game asks next; the 3D renderer.

## 4. GPU

The level is the hardware's, as yuzu and Ryujinx emulate it: the game's own NVN driver (inside its
sdk module) runs as translated code, and nvdrv, the GPU's address space and channel, and the
Maxwell classes' methods are what is written here. `textures/blocklinear.zap` is the Tegra's
block-linear layout; `textures/decode.zap` decodes a TIC's first level (plain formats, BC1-5 and
BC7 by std's dds, ASTC by std's astc, the swizzle applied); `render/` turns a DrawCall's vertices
(`vertexNumbers`, `attributeValue`) and constant buffers (`constantWords`) into what a translated
stage reads. Shaders are
translated ahead of time: a run records each Maxwell program by a hash, `shaders/` turns them into
Zap GPU code built with the program (spec 11), and the renderer picks each by its hash.

A pushbuffer's headers of the older increasing and non-increasing kinds (0 and 2) carry bursts
as 1 and 3 do, and a GPU address reads through the newest mapping that holds it; without either
the stream was read as garbage. VertexB always runs, whatever its enable bit says.

Being written: the renderer (targets, textures and draws through the engine). The test homebrews of this step are switchbrew's deko3d examples
(tools/homebrew.zap builds them: a triangle, and nine examples behind a menu).

### Maxwell shaders

    zap run projects/recomp/switch/tools/shaders.zap <files | dirs> [--out <dir>]

`shaders/` reads a Maxwell (GM20B, SM 5.3) program as a game hands it to the GPU (the 0x50-byte
SPH, then groups of a scheduling word and three instructions) or deko3d's DKSH around one,
decodes its instructions (yuzu's maxwell.inc patterns, the most specific winning), rebuilds its
control flow (SSY/SYNC and PBK/BRK regions, backward jumps as loops, forward ones as if and
if-else) and writes it as Zap GPU code: registers are u32 locals, constant buffers one storage
buffer of u32 (bank b's word w at b * 16384 + w; DKSH's constants are bank 1), textures
`p.textures[base + k]` (`layers` for 2D arrays, `shadows` for shadow maps; k the program's own
slot per kind, base 0 for a vertex stage and 32 for a pixel one), vertex inputs `Attributes<name>` (a Vec4 a
generic attribute), what a vertex stage passes on the module's `Varyings`: the generic attributes
of all the programs built together, so any vertex stage meets any pixel stage. `maxwell/` holds
the GPU functions the translations call (BFE, LOP3, F2I, FMZ products...). The tool writes the
module `translated/` and `programs.zap`, which names the entries and builds when each compiles.
Every program takes the one `Params` of `translated/types.gpu.zap` (the constants buffer and an
unsized array of each texture kind some program reads), so a vertex and a pixel entry pair in
`shader(...)`. When a dir holds `pairs.txt` (a run's recorded program sets, a line each), the
tool also writes `programs/programs.zap`: `programCode(key)` is the `shader(vertex, pixel)` text
of a set (the line is the key; only sets of a vertex and a pixel stage that both translated) and
`programTextures(name)` a program's `TextureSlot`s (handle, kind, index in the kind's array) for
a renderer to fill the arrays; `programs.zap` then names those sets only.

State: `tools/homebrew.zap` builds deko3d's examples and copies their shaders to
rom/homebrew/shaders/; all 454 instructions of the 14 programs decode, and the vertex, pixel and
compute ones translate and build (`shaders/tests/`); the two tessellation stages are left out.
BotW's first 800 turns record 52 programs in 10 sets; 49 translate into a module that builds,
24 of them with no instruction left out; the sets whose two stages translated build.

What Zap's GPU code lacks, each with the instructions that need it (the translation notes the
instruction and writes zeros, or does as said):
- Texel fetch (TLD, TLDS: integer coordinates and a level, no sampler): written as `sampleLevel`
  at the texel's centre after a `size` query; exact inside the texture with nearest or linear
  filtering, but outside it the sampler's wrap answers where a fetch gives 0.
- Gather (TLD4, TLD4S, with offsets and a depth compare).
- Integer textures (a TEX or TLD of an R32UI texture reads integers; Zap samples Vec4 floats, and
  has no IVec4/UVec4).
- Images (SULD, SUST, SURED, SUATOM: storage images by integer coordinates, and their atomics).
- Bindless handles (TEX.B, TLD.B, TLD4.B, TXQ.B, TMML.B: the handle in a register, a texture's
  index and a sampler's index << 20); `Texture[]` indexes textures with their own samplers, so it
  also needs separate sampler arrays.
- Sampling options: a level bias, lod clamp and offsets (TEX.LB, .LBA, .LC, .AOFFI), gradients
  (TXD), the level of detail (TMML), the level count (TXQ's fourth component), a shadow compare at
  an explicit level or on an array (TEXS 2D.LL.DC, TEX.DC of arrays), 1D, 3D, cube and
  multisampled textures (TEXS/TEX/TLDS encodings), f16 results (TEXS, TLDS).
- f64 (DADD, DMUL, DFMA, DMNMX, DSET, DSETP, F2F/F2I/I2F of f64, MUFU.RCP64H/RSQ64H).
- Global memory (LDG, STG, LD, ST, ATOM, RED: a 64-bit address; Zap has bound storage buffers):
  deko3d's sinewave compute program writes through one.
- Tessellation and geometry stages (ISBERD, OUT, AL2P, ALD/AST of patches).
- A vertex stage's number beside its attributes (ALD of attribute 191 when generic ones are read:
  Zap's vertex stage takes one or the other), and outputs other than the position and generic
  attributes (AST of point size, clip distances, layer, viewport).
- A pixel stage's front face (IPA of attribute 255), flat and linear float inputs (SPH modes
  constant and linear: translated as perspective), IPA's centroid, sample and offset modes, and
  outputs other than colors (the SPH's depth and sample mask); targets are numbered by their order,
  so one written without those before it lands on the wrong one.

Left in the translation: condition codes (CC, .X: IADD.CC/IADD.X pairs, BRA by a condition),
indirect and call flow (BRX, JMX, CAL, RET), a jump to an outer if's end or an outer loop (no
labelled break: the program is left out), rounding modes other than nearest-even, IADD.SAT,
IADD3.RS, I2I.SAT, IMNMX's extended modes, XMAD.CSFU, P2R/R2P of condition codes or by a register,
IMAD, IMUL, LEA, PRMT, half floats (HADD2, HMUL2, HFMA2, HSET2, HSETP2), SHFL and VOTE (Zap has
`laneAt`, `laneAll`), special registers but the lane and the thread and group ids. The renderer
(not written) must give the depth range the game set (the compiler maps z from -1..1 to 0..1,
spec 11), the y direction, the vertex formats as Vec4 floats, constant buffer banks and texture
handles as above.

### Draws and descriptors

At a draw's end (END, or the one-word draws that begin and end, with inline indices) `maxwell/draw.zap`
decodes the 3D registers into a `DrawCall` (`maxwell/drawstate.zap`; offsets from Ryujinx's
ThreedClassState): topology, first/count or the index buffer, instances (a BEGIN with bit 26 adds one),
vertex attributes and streams, the enabled programs with their GPU addresses, the constant buffers bound
per stage, the TIC and TSC pools, targets, zeta, viewports, scissors, blend, depth and cull. `Gpu.draws`
keeps the frame's (512 at most, cleared at endFrame). `textures/descriptors.zap` reads a TIC and a TSC
entry. `run.zap --record-shaders <dir>` (also the translated program) writes each program a draw uses
once, named by its hash, SPH included; `tools/shaders.zap <dir>` translates them.

Left: nothing reads the pools or the program bytes through the DrawCall yet (a renderer fetches TIC/TSC
entries by handle from the texture constant buffer); geometry's viewport index, stencil, logic ops, color
masks, transform feedback, indirect and instanced-by-macro draws are not decoded; a tessellation or
geometry program is recorded but not translated.

## 5. Audio and controls

`controls/pad.zap` makes the Pro Controller from a game pad (engine.isPadDown, and engine.padAxis
for the sticks and triggers, read from Android's joystick motion; ZL, ZR and the sticks pressed are
engine.PadButtons now). `frontend/screen.zap` plays the program a sixtieth of a second of guest time
at a turn, shows Kernel.frame (the last picture vi was given) and feeds the pad to hid; scripted
runs (engine.isHeadless) open no window.

The touch controls run on projects/recomp/touch, whose layout is a parameter (the SNES pad's is
unchanged). `controls/pad.zap` has the Pro Controller layout (two sticks, ABXY, the cross, L, R, ZL,
ZR and +/-, semi-transparent) and turns the overlay into a horizon.PadState (`fromOverlay`) and
the Switch's touch points (`touchPoints`, 1280 by 720). The left stick moves; the right one, or a
drag on the right half outside every control, turns the camera; a finger on no control is a touch
point; a game pad's first press hides the controls and `frontend/screen.zap` then reads the pad.
The scale, opacity and moved places are kept in `--touch-layout` (touch-layout.txt); MENU offers
bigger, smaller, move controls (a drag moves a control) and resume. Tested without a window: hit
testing, stick range and lean bits, the camera drag, the passthrough, hiding, the settings file.

Left: the window run itself is not tried on a phone (the overlay is drawn on the CPU image, not on
the GPU picture), the touch points carry no multi-finger identity across frames (a finger's index
in the list), and the opacity and per-control sizes have no menu.

audren:u (horizon/aud*.zap): the work buffer size (yuzu's formula, by revision), the renderer and its
event (a frame every sample count at the rate, on the guest's clock), RequestUpdate read as the
game's revision lays it out, and a frame of voices (PCM8, PCM16, DSP ADPCM with loops, linear
resampling) mixed through the mixes and the device sink, downmixed to stereo and pushed to
Kernel.audio.sound (engine.audio's FrameSound: heard unless --mute, --wav writes it). With nothing
listening the voices still advance, reading no memory. Left out: biquad filters, volume ramps, the
effects (reverb, delay, aux, limiter, compressor), PCM float and 24/32-bit, circular buffer sinks,
mixes sent into a splitter, the performance history, and checking that buffers lie in an attached
memory pool.

## 6. The Great Plateau on Redroid

Not started. The arm64 host's Redroid shares the machine with services in production (8 GB free of
23), and BotW's heap alone is 3.3 GB.
