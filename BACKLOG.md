# Backlog

Set aside on 2026-10-17 to focus on Excel and performance. Each item is left working at an
intermediate state; it comes back to TODO.md when picked up again.

## FireRed (`projects/firered`)

Recompiled to native Zap: from the user's ROM it reaches the title screen headless (frame 2400)
and, with scripted keys, the player's room; EWRAM, VRAM, palette and OAM match mGBA's up to
VBlank 1000. About 270 fps uncapped, 25 MB running, 100 s and 2.3 GB to compile its generated
code. Left:
- Cycle counting exact (IWRAM's sound buffer and frame counters still differ from mGBA's).
- The assets split into graphics, maps, text, music and tables: needs the decomp's symbol map,
  which comes only from building pokefirered with agbcc.
- A frame-for-frame check against mGBA: needs a headless mGBA (the Windows build has its GDB
  stub only in the windowed app).
- Compile time and memory of the generated code (100 s, 2.3 GB).

### 91. A function written once runs on the CPU and the GPU

Found by FireRed (step 41): its layers are drawn on the CPU because a shader's function cannot
take a storage buffer as an argument and CPU code cannot call a `.gpu.zap` function, so one
renderer cannot serve both. A plain function over buffers (`u32[]`, a `Grid`) is callable from
CPU code and from a kernel alike, its buffers passed as storage on the GPU; then FireRed's PPU
draws its layers on the GPU with the same code its CPU path runs (frame hashes the same).

### 92. One table decoder for the recompilers

Excel's 68000 (`excel1/m68k`) and FireRed's ARM and Thumb (`firered`) are each a text table of
bits and templates read by a decoder of their own: one decoder, in the engine or the std, reads
all three tables, and both recompilers share its common form.

## AI models on the GPU (`std/tensor`, `std/gpu`, `grad`; the models in `projects/ai`)

Working on main: tensors on the CPU and the GPU, kernels in Zap, `grad(f)` by the compiler, SGD,
Adam and AdamW, GGUF; MNIST and a char transformer match PyTorch's loss, TinyLlama 1.1B writes
llama.cpp's tokens (26.5 against 34.5 tokens/s on a GTX 1650; measured before the barriers
only on a hazard and grad keeping the activations, merged 2026-10-19, and the batched causal
prompt, merged unfinished). The data is in `projects/ai/data/`, outside git.

### 81. What remains of AI models on the GPU: shapes in the type, and speed

Tensors, `grad`, the optimisers, MNIST, a transformer and TinyLlama 1.1B run (projects/ai: their loss
curves PyTorch's, TinyLlama's tokens llama.cpp's). What is left:
- A tensor's shape in its type where it is known (`Tensor<[784, 128]>`, a product's shapes met
  when compiling), the runtime's shape kept for the others; today every shape is checked when
  the program runs.
- Speed (GTX 1650, 2026-10-17, a machine shared with other builds): MNIST's epoch 1.35x
  PyTorch's time, the transformer's 200 steps 1.8x, TinyLlama's decoding 0.77x llama.cpp's
  tokens per second (26.5 against 34.5). Every dispatch waits on a full barrier after the one
  before; a prompt is read a token at a time (no batched causal attention); the transformer's
  steps compute each block's forward pass twice (a checkpoint per step, then its pull).
Judged by the same tests' measures.

## Excel 1.00 (`projects/excel1`)

Set aside on 2026-10-18 for performance. Working on main: `zap run excel1/prepare.zap` once, then
`zap run excel1/main.zap` opens Excel in a live window (mouse, keys, real clock); it still dies on
a Toolbox trap not written yet; a crash writes its log to `excel1/crash.txt`. Left: every menu, dialog and file path
exercised by a scripted test with each trap it reaches written, then the rest of step 65.

### 65. What remains of Microsoft Excel 1.00 for the Mac recompiled into native Zap (`projects/excel1`)

Done: the disks are read from the user's `.moof` captures; the 68000 is one decoder, one lowered
form, an interpreter and a recompiler; the Mac is written in Zap. The floppy drive reads each
track's captured bits as the drive's head would, its weak cells as the amplifier's noise, and the
`.Sony` driver runs Excel's own `JRdData` against the IWM, so Excel's copy-protection check
passes with its code unmodified. Excel runs to its worksheet window and, driven by `--input`, opens
its About box, which matches the screenshot kept with the disks but for 17 pixels (`zap run
excel1/main.zap --idle 90 --input "down 10 20; move 30 30; up 30 30" --expect ...`). The
recompiled segments are the driver's fast path (`excel1/recomp/excel.zap`, written by
`recomp.zap` from the code a run reached, `main.zap --reached`) and end in the interpreter's
machine state (`--state`). `zap run excel1/main.zap` (after `excel1/prepare.zap`) runs Excel live:
the Mac's screen in a window scaled by whole pixels, the real mouse and keys (Ctrl as Command)
and clock fed to the Mac; the headless options (`--headless`, `--input`, `--shot`, ...) keep the
checks windowless.

What remains:
- The p-code dispatcher and the code Excel copies into RAM before running it stay interpreted
  (56% of the instructions of the About run): recompile code copied at run time by the bytes it
  was copied from, then measure the recompiled run against the interpreted one.
- Read the `.a2r` flux captures through a data separator (as MAME's floppy code reads flux) as the
  tracks' source where their turns disagree, in place of the `.moof` bits and the noise model.
- About shows 98% free memory where the screenshot shows 99%: the Toolbox's own heap use set
  against the ROM's.
- Open the sample documents (File > Open: the Standard File package) and match the other
  screenshots in `excel1/disks/extras/`.

## Constants computed when compiling

A top-level constant whose value calls only pure functions (no I/O, no `args`, no module variable)
computed by the compiler and stored in the executable's data; the others still made before `main`.
No new syntax, no macros. Set aside on 2026-10-21: the tables that qualify cost well under a
millisecond at start (mario's `sineTable`, 5,120 sines, and `arctanTable`, 1,025; std/digest's
`crcTable`; excel1's opcode `matchers`; ragnarok's JPEG `idctTable`, made per image today but
writable at the top as it is), and stored in the executable they make it larger (mario by about
28 KB), against the spec's smallest executable. Comes back when a table costs time worth
measuring at start.

## Open questions of the language

Decided later, with real code:

- Borrows the origin rules miss: each case found gets a `from` clause or, if common, a new
  inference rule.
- `decimal` and `char`: an exact `decimal` for money (annotated once, `price decimal = 19.99`,
  its literals following; mixing it with `f64` an error) and a `char` type.
