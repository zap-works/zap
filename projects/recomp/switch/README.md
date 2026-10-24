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

## 2. AArch64 translation

    zap run projects/recomp/switch/main.zap <homebrew.nro | exefs dir> [--out <dir>] [--build]

`arm64/` decodes A64 (Arm v8.0, the Cortex-A57's) into `Instr`; `cpu/` holds a thread's
registers, the guest memory and what each instruction does (`execute`). `translate/` finds the
functions as SavageWindRecomp does (program.zap): starts from the unwind tables' FDEs (each FDE's
pointer encoding read from its CIE), the code the dynamic section's relocations store
(R_AARCH64_RELATIVE, RELR: vtables, callbacks) and its function symbols, every bl's target, and an
adr or adrp+add that makes a code address outside its own FDE; extents from the FDEs' ranges; labels
at every branch's target (one into another function is a tail call to its middle), an adr into the
own FDE, the targets of a bounds-checked jump table (tables.zap: the window from the cmp to the br
run once per index on a scratch thread, as gen.py's jump_table does with Unicorn) and the places
after calls and supervisor calls. Each function is a loop over a match of its labels, a `br` a jump
to the label its register names when it stays inside, every instruction a form or a call of
`execute` with the decoded instruction written as a literal. A function may be entered at any label and returns as soon as the guest leaves it,
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

Scale: BotW's ExeFS (main, sdk, subsdk0-3, rtld) is 141,434 functions, 7.7 million instructions,
18.9 million lines of Zap: one build would take some 190 GB at the compiler's 10 KB a line. It is
written as 131 parts of at most 60,000 instructions (`--part`), each a module and an entry file
built with `zap build --loadable` (spec 13.1), which the program loads as it starts (`loadBuild`):
every part imports the program's modules, so its code shares the program's state, and registers
its functions with the dispatcher. A call into another part goes through cpu's `enter` (a search
of the functions by address). A translation that fits one part is one build, as before (Android
builds only that: loadable builds are Windows x64's so far).

Guest memory (`cpu/memory.zap`) is a window of the host's address space reserved at a fixed
address (std's `vmem`, as SavageWindRecomp and ScarletNX reserve theirs): 64 GiB at 64 GiB holds
the 36-bit guest's whole space, a guest address is its offset there, and a load or store is one
host access at the window's base or'd with the address (masked to the window, so no address
reaches outside it). Pages are committed as the kernel maps regions (`Space.map`): a game's
heap costs only what it maps, and an access to a page never mapped crashes the host with its
trace; `guestfaults` in ZAP_RUN checks every access against the process's span instead. The
window could not sit at the guest's own addresses: BotW is a 36-bit process (main.npdm), rtld
scans for modules from 128 MiB and the game maps stacks below 2 GiB, where Windows keeps its own
allocations and its executable (5 GiB). On Linux and Android the window is mapped PROT_NONE with
MAP_NORESERVE | MAP_FIXED_NOREPLACE and committed by mprotect, in 64 KiB steps (16 KiB pages fit);
64-128 GiB lies below the libraries of a 39-bit device too, but a 39-bit game would need a
512 GiB window at 512 GiB, past a 39-bit device's whole space. Measured once on Windows, the
machine shared: BotW's 300 million instructions interpreted (`tools/run.zap --steps 300000000`)
took 71.8 s before (4.2 million a second), 65.9 s after (4.6 million); the translated hello ran in
0.70 s before, 0.56 s after. The interpreter's cost is now its decoding and dispatch, not memory.


Measured once on the whole ExeFS (this machine, two builds at once): translation 75 s; build 26
minutes, each part about 15 s and 1.6 GB at its peak; 1.27 GB of parts and a 3 MB program, loaded in
1.1 s. A part imports its own module alone (its code reaches cpu/ and arm64/, never horizon/ or
the renderer; the loader finds the program's variables by name), so a part's cold build is 23 s
to 15 s, and `zap build --loadable` keeps a part whose sources are unchanged (0.03 s): a change to
horizon/, maxwell/, render/ or frontend/ builds the program alone. 300 turns (`--frames 300`, headless) take 73 s, against 124 s for the 4,900 functions of the
profiled build (startup included: 1.8 s and 0.7 s). Jump tables: 1,819 of the 8,996 `br` resolved
(258 more look like tables and are not: their targets are entered through the interpreter).

Per instruction: 190 bytes of x64 a translated instruction, until an access's fault was kept as
numbers (Memory.faultAt) instead of a message formatted inline in every access, and the
registers became a fixed array (`u64[33]`, no bounds check): 90 bytes, a part's build 22 s to 15 s
and 2.0 to 1.6 GB.

`tools/run.zap --profile f` still records the blocks a run entered, and `main.zap --profile f`
translates only the functions holding them. `tools/coverage.zap`: 99.9% of main's words decode
(15 of 5.8 million do not).

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

The renderer (`render/`, `frontend/rendered.zap`): with a program table the GPU keeps each frame's
clears and draws in order (each draw with its program names and a copy of its stages' constants;
the 3D engine's constant data writes land in memory), and at each present the frame is replayed
on the engine: render targets are textures of target sets (engine.newTargetSet) by address and
format, a draw takes its recorded set's translation (`programs/programs.zap`, which the translated
program passes as a `render.ShaderTable`), its textures from the TIC pool (a target drawn earlier
where one lies at the address, else decoded once), its vertices as Vec4s in its Attributes' order,
as triangles; the target at the presented buffer's GPU address is read back as the picture.
`--trace-render` prints each command, its textures, constants and first vertex, and the read.

State: BotW's first 700 turns draw every one of their 3,511 draws (none skipped): a black quad
over a cleared 10-bit target, copied to the 1920x1080 framebuffer, so the picture is black (its
texture is an 8x8 BC4 of zeros: the game's own black screen before loading). Left: depth,
stencil, blending, culling, instancing, layered and shadow textures, other primitives, BGRA and
float targets read back, and the speed (a 1920x1080 read back each turn).

The test homebrews of this step are switchbrew's deko3d examples (tools/homebrew.zap builds them:
a triangle, and nine examples behind a menu).

### Maxwell shaders

    zap run projects/recomp/switch/tools/shaders.zap <files | dirs> [--out <dir>]

`shaders/` reads a Maxwell (GM20B, SM 5.3) program as a game hands it to the GPU (the 0x50-byte
SPH, then groups of a scheduling word and three instructions) or deko3d's DKSH around one,
decodes its instructions (yuzu's maxwell.inc patterns, the most specific winning), rebuilds its
control flow (SSY/SYNC and PBK/BRK regions, backward jumps as loops, forward ones as if and
if-else) and writes it as Zap GPU code: registers are u32 locals, constant buffers one storage
buffer of u32 (bank b's word w at b * 16384 + w; DKSH's constants are bank 1), textures
`p.textures[base + k]` (`layers` for 2D arrays, `shadows` for shadow maps, `shadowLayers` for
shadow map arrays; k the program's own slot per kind, base 0 for a vertex stage and 32 for a pixel
one; a texture read two ways, sampled and compared, takes a slot of each kind and the renderer
binds the one image to both, the compared one with a comparison sampler), vertex inputs `Attributes<name>` (a Vec4 a
generic attribute), what a vertex stage passes on the module's `Varyings`: the generic attributes
of all the programs built together, so any vertex stage meets any pixel stage. `maxwell/` holds
the GPU functions the translations call (BFE, LOP3, F2I, FMZ products...). The tool writes the
module `translated/` and `programs.zap`, which names the entries and builds when each compiles.
Every program takes the one `Params` of `translated/types.gpu.zap` (the constants buffer and an
unsized array of each texture kind some program reads), so a vertex and a pixel entry pair in
`shader(...)`. When a dir holds `pairs.txt` (a run's recorded program sets, a line each), the
tool also writes `programs/programs.zap`: `programCode(key)` is the `shader(vertex, pixel)` text
of a set (the line is the key; only sets of a vertex and a pixel stage that both translated) and
`programTextures(name)` a program's `TextureUse`s (handle, kind, index in the kind's array, and
for a bindless handle the bank its word was loaded from: the code's MOV or LDC of a constant
buffer word before the read, in the same block) for a renderer to fill the arrays; `programs.zap` then names those sets only.

State: `tools/homebrew.zap` builds deko3d's examples and copies their shaders to
rom/homebrew/shaders/; all 454 instructions of the 14 programs decode, and the vertex, pixel and
compute ones translate and build (`shaders/tests/`); the two tessellation stages are left out.
BotW's first 800 turns record 52 programs in 10 sets; 49 translate into a module that builds,
38 of them with no instruction left out (31 before gathers, level-of-detail queries, shadow
arrays, a pixel stage's depth and sparse targets); the sets whose two stages translated build.

### Draws and descriptors

At a draw's end (END, or the one-word draws that begin and end, with inline indices) `maxwell/draw.zap`
decodes the 3D registers into a `DrawCall` (`maxwell/drawstate.zap`; offsets from Ryujinx's
ThreedClassState): topology, first/count or the index buffer, instances (a BEGIN with bit 26 adds one),
vertex attributes and streams, the enabled programs with their GPU addresses, the constant buffers bound
per stage, the TIC and TSC pools, targets, zeta, viewports, scissors, blend, depth and cull. `Gpu.draws`
keeps the frame's (512 at most, cleared at endFrame). `textures/descriptors.zap` reads a TIC and a TSC
entry. `run.zap --record-shaders <dir>` (also the translated program) writes each program a draw uses
once, named by its hash, SPH included; `tools/shaders.zap <dir>` translates them.

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
