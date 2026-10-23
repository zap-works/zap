# A Maxwell (GM20B, SM 5.3) program as a game hands it to the GPU: a graphics stage's 0x50-byte
# shader program header (SPH, NVIDIA's open-gpu-doc "Shader Program Header"), then the code, in
# groups of a scheduling word and three 64-bit instructions. A compute program has no SPH.
# deko3d's DKSH container wraps one such program with what its driver needs.

import recomp.switch.arm64

pub type Stage:
	Vertex
	TessControl
	TessEval
	Geometry
	Pixel
	Compute

# The SPH's fields this translation reads. The maps are its bits as words: a VTG stage's inputs
# from bit 160 and outputs from bit 400, a bit an attribute (by its index: its byte address in the
# attribute space over 4, so position x is 28 and generic attribute g's component c 32 + 4g + c);
# a pixel stage's inputs the same up to the generic attributes, which take 2 bits a component
# (their interpolation) from word 6, and its outputs in words 18 and 19.
pub type Header:
	stage Stage
	killsPixels bool
	localMemory i64   # bytes of local memory a thread (the low and high sizes)
	crsSize i64   # bytes of the call/return stack
	words u32[]   # the 20 words, read by the accessors below

pub headerSize = 0x50

# attribute indices (yuzu's IR::Attribute, Ryujinx's AttributeConsts)
pub positionX = 28
pub generic0 = 32
pub instanceId = 190
pub vertexId = 191
pub frontFace = 255

fn headerBit(h Header, at i64):
	arm64.hasBit(h.words[at / 32], at % 32)

# The program's header from its 20 words at `at`.
pub fn readHeader(code u8[], at i64) Header:
	words = []
	for i in 0..20:
		words.push(code.u32le(at + i * 4))
	w0 = i64(words[0])
	stages = [
		Stage.Vertex,
		Stage.Vertex,
		Stage.TessControl,
		Stage.TessEval,
		Stage.Geometry,
		Stage.Pixel
	]
	kind = arm64.bits(w0, 10, 4)
	Header(
		stage = stages[kind] if kind < stages.len else .Vertex,
		killsPixels = arm64.hasBit(w0, 15),
		localMemory = arm64.bits(words[1], 0, 24) + arm64.bits(words[2], 0, 24),
		crsSize = arm64.bits(words[3], 0, 24),
		words
	)

# Whether the stage reads the attribute (index as above, below 240).
pub fn readsAttribute(h Header, index i64) bool:
	g = index - generic0
	if h.stage == .Pixel and g >= 0 and g < 128: return h.pixelMode(g) != 0
	h.headerBit(160 + index)

# Whether a VTG stage writes the attribute.
pub fn writesAttribute(h Header, index i64) bool:
	h.stage != .Pixel and h.headerBit(400 + index)

# A pixel stage's generic input component g (32 + g the attribute) interpolation: 0 unused, 1
# constant, 2 perspective, 3 linear.
pub fn pixelMode(h Header, g i64) i64:
	arm64.bits(h.words[6 + g / 16], g % 16 * 2, 2)

# A pixel stage's render target `t` component c written.
pub fn writesTarget(h Header, t i64, c i64) bool:
	arm64.hasBit(h.words[18], t * 4 + c)

pub fn writesDepth(h Header) bool:
	arm64.hasBit(h.words[19], 1)

pub fn writesSampleMask(h Header) bool:
	arm64.hasBit(h.words[19], 0)

# A program: its header (none for compute), its instructions (the scheduling words left out)
# and where they start in the code given.
pub type Program:
	stage Stage
	header Header?
	words i64[]
	start i64

# The NVIDIA compiler ends a program with an unconditional BRA to itself after its last EXIT.
fn isEndLoop(w i64, at i64):
	arm64.bits(w, 44, 20) == 0xE_2400 and arm64.bits(w, 0, 20) == 0x7_000F and
		relativeTarget(w, at) == at

# The instructions from `start` (a group's start) up to the branch to itself, or the end.
pub fn readCode(code u8[], start i64) i64[]:
	words = []
	while start + addressOf(words.len) + 8 <= code.len:
		w = i64(code.u64le(start + addressOf(words.len)))
		if isEndLoop(w, addressOf(words.len)): return words
		words.push(w)
	words

# The program whose SPH (none for compute) is at `entry` of code.
pub fn readProgram(code u8[], entry i64, stage Stage) Program:
	if stage == .Compute:
		return Program(stage, header = none, words = readCode(code, entry), start = entry)
	h = readHeader(code, entry)
	Program(
		stage = h.stage,
		header = h,
		words = readCode(code, entry + headerSize),
		start = entry + headerSize
	)

# What deko3d's DKSH holds of a program: the stage, the registers, the constants deko3d binds
# as constant buffer 1 (its bytes in the code), a compute program's group size, the program.
pub type Dksh:
	program Program
	registers i64
	constants u8[]
	group i64[]

# deko3d's program types in DKSH, in its order
dkshStages = [
	Stage.Vertex,
	Stage.Pixel,
	Stage.Geometry,
	Stage.TessControl,
	Stage.TessEval,
	Stage.Compute
]

# A DKSH file (deko3d's dksh.h): "DKSH", the header's size, the control part's size (the code
# follows it), the code's size, the program headers' offset and count. A program header: its
# type, entry (in the code), registers, constant buffer 1's offset and size in the code, then a
# compute program's group size at 0x18.
pub fn readDksh(file u8[]) Dksh ? str:
	if file.len < 0x18 or not file.startsWith("DKSH"): return "not a DKSH"
	control = i64(file.u32le(8))
	size = i64(file.u32le(12))
	programs = i64(file.u32le(16))
	if file.u32le(20) == 0: return "no program"
	kind = i64(file.u32le(programs))
	if kind >= dkshStages.len: return "program type {kind}"
	if control + size > file.len: return "code past the file's end"
	code = file[control..control + size].copy()
	entry = i64(file.u32le(programs + 4))
	cbAt = i64(file.u32le(programs + 12))
	cbSize = i64(file.u32le(programs + 16))
	group = []
	if dkshStages[kind] == .Compute:
		for k in 0..3:
			group.push(i64(file.u32le(programs + 0x18 + k * 4)))
	Dksh(
		program = readProgram(code, entry, dkshStages[kind]),
		registers = file.u32le(programs + 8),
		constants = code[cbAt..cbAt + cbSize].copy(),
		group
	)
