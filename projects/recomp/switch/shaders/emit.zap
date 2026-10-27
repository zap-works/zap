# The Zap GPU code of one program as the translation writes it: registers are u32 locals (`r5`,
# `rz` the zero), predicates bool locals (`p2`, PT `true`), the condition codes bool locals (`zf`,
# `sf`, `cf`, `of`: zero, sign, carry, overflow), a float a register's bits
# (`f32.fromBits(r5)`); constant buffer `bank`'s word w is `p.constants[bank * 16384 + w]`.
# A local the code never reads takes no binding, its writes going to `_`.

import engine
import recomp.switch.arm64

# words of a constant buffer bank: 64 KB
pub bankWords = 16_384

# what a line assigns: a register, a predicate or a condition code (its index in flagNames)
pub type Space:
	Register
	Predicate
	Flag

pub flagNames = ["zf", "sf", "cf", "of"]

pub type Line:
	text str
	depth i64
	target i64 = -1   # the register, predicate or flag it assigns, -1 none
	space Space = .Register

# A texture the program reads: its handle (the texture constant buffer's word), kind and slot
# (its order among the program's textures of that kind).
pub type TextureUse:
	handle i64
	kind TextureKind
	slot i64
	bank i64 = -1   # the constant buffer of a bindless handle's word, -1 the texture buffer

pub type TextureKind:
	Plain   # Texture
	Layered   # TextureArray
	Shadow   # ShadowMap
	LayeredShadow   # ShadowMapArray
	Integers   # UintTexture: a texture the TIC says holds unsigned integers
	SignedIntegers   # IntTexture
	Volume   # Texture3D
	Cube   # TextureCube
	LayeredCube   # TextureCubeArray
	Image   # UintImage: a surface (SULD, SUST, SUATOM), a field of Params a slot (imageField)

pub textureKinds = [
	TextureKind.Plain,
	TextureKind.Layered,
	TextureKind.Shadow,
	TextureKind.LayeredShadow,
	TextureKind.Integers,
	TextureKind.SignedIntegers,
	TextureKind.Volume,
	TextureKind.Cube,
	TextureKind.LayeredCube,
	TextureKind.Image
]

# The shared Params' array of a kind and the index a stage's slot takes in it: a pixel stage's
# slots start at pixelTextureBase, so one array holds a vertex and a pixel stage's textures.
pub fn arrayName(k TextureKind) str:
	match k:
		Plain: "textures"
		Layered: "layers"
		Shadow: "shadows"
		LayeredShadow: "shadowLayers"
		Integers: "integers"
		SignedIntegers: "signedIntegers"
		Volume: "volumes"
		Cube: "cubes"
		LayeredCube: "cubeLayers"
		Image: "images"

# The textures a renderer fills for a draw, an array a kind (TextureKind's arrayName), each at the
# slot its TextureUse gives.
pub type TextureSet:
	textures engine.Texture[] = []
	layers engine.TextureArray[] = []
	shadows engine.ShadowMap[] = []
	shadowLayers engine.ShadowMapArray[] = []
	integers engine.UintTexture[] = []
	signedIntegers engine.IntTexture[] = []
	volumes engine.Texture3D[] = []
	cubes engine.TextureCube[] = []
	cubeLayers engine.TextureCubeArray[] = []
	images engine.UintImage[] = []   # at the slots of Image's TextureUses (Params' imageN fields)

pub pixelTextureBase = 32

# the Params field of the image at a slot (base included): images are fields, as a texture array
# of storage images is not Zap's
pub fn imageField(slot i64) str:
	"image{slot}"

pub fn textureBase(stage Stage) i64:
	pixelTextureBase if stage == .Pixel else 0

pub fn textureType(k TextureKind) str:
	match k:
		Plain: "Texture"
		Layered: "TextureArray"
		Shadow: "ShadowMap"
		LayeredShadow: "ShadowMapArray"
		Integers: "UintTexture"
		SignedIntegers: "IntTexture"
		Volume: "Texture3D"
		Cube: "TextureCube"
		LayeredCube: "TextureCubeArray"
		Image: "UintImage"

# What a register holds where the code is, when the code shows it: an immediate (bank -1), or
# the word of a constant buffer it was loaded from (a bindless handle's, read from the texture
# buffer). Known only within the block that set it.
pub type Known:
	value i64 = 0
	bank i64 = -1
	word i64 = 0

pub type Emitter:
	name str   # the program's, which its declarations end with
	stage Stage
	header Header?
	interface i64[]   # the generic attributes a vertex stage passes on
	code Instr[]
	lines Line[] = []
	depth i64 = 1
	regRead bool[] = fill(256, false)
	predRead bool[] = fill(8, false)
	flagRead bool[] = fill(4, false)
	usesMachine bool = false   # whether the code is written as a machine of blocks (machine.zap)
	calls bool = false   # whether the machine calls (its locals returns, called)
	usesSum bool = false   # whether a sum with codes uses the locals ca, cb, cr (sums.zap)
	inputs i64[] = []   # the attributes (indices) read
	outputs i64[] = []   # the attributes written
	textures TextureUse[] = []
	targets i64[] = []   # the render targets a pixel stage writes
	depthRegister i64 = -1   # the register of a pixel stage's depth, -1 when it writes none
	localWords i64 = 0
	sharedWords i64 = 0
	missing str[] = []
	known {i64: Known} = {}
	integers {i64: bool} = {}   # the handles of textures of integers (true: signed), as the TIC says

	fn line(text str):
		lines.push(Line(text = text.copy(), depth))

	# rN = value, or `_ = value` for RZ (or a register nothing reads: see `body`)
	fn set(r i64, value str):
		if r == rz:
			line("_ = {value}")
			return
		known.remove(r)
		lines.push(Line(text = "{regName(r)} = {value}", depth, target = r))

	fn setF(r i64, value str):
		set(r, "({value}).toBits()")

	# the double value's words into r and the register after it (the low one first)
	fn setD(r i64, value str):
		if r == rz:
			line("_ = {value}")
			return
		line("wide = {value}")
		set(r, "wide.lowWord()")
		set(r + 1, "wide.highWord()")

	# a float value into r: an f32's bits, or when wide an f64's words into r and the one after
	fn setFloat(r i64, value str, wide bool):
		if wide:
			setD(r, value)
		else:
			setF(r, value)

	fn setP(p i64, value str):
		if p == pt:
			line("_ = {value}")
			return
		lines.push(Line(text = "p{p} = {value}", depth, target = p, space = .Predicate))

	# condition code k (0 zero, 1 sign, 2 carry, 3 overflow) = value
	fn setFlag(k i64, value str):
		lines.push(Line(text = "{flagNames[k]} = {value}", depth, target = k, space = .Flag))

	# the zero and sign codes of a result; `extended` (an X operation, a word above the one before)
	# keeps zero only when the words before were zero too
	fn setZeroSign(result str, extended bool):
		setFlag(0, "{result} == 0 and {cc(0)}" if extended else "{result} == 0")
		setFlag(1, "{result} >> 31 != 0")

	# rN = value, its zero and sign codes set when cc (through cr: the destination may be RZ)
	fn setCoded(r i64, value str, cc bool, extended bool):
		if not cc:
			set(r, value)
			return
		usesSum = true
		line("cr = {value}")
		setZeroSign("cr", extended)
		set(r, "cr")

	# condition code k's value
	fn cc(k i64):
		flagRead[k] = true
		flagNames[k].copy()

	# what the translation cannot write yet (or Zap cannot): a note, the destinations zeroed
	# An instruction not translated: noted, its results zeroed, and the registers its A and B
	# fields start read (four each, as a texture's coordinates run), so what was computed for it
	# stays a value something reads.
	fn lack(i Instr, why str, zeroed i64[]):
		missing.push("{i.op} at {i.at:x}: {why}")
		line("# not translated: {i.op} ({why})")
		for first in [i.ra, (i.word >> 20) & 0xFF]:
			for r in (first..(first + 4).min(rz)):
				line("_ = {x(r)}")
		for r in zeroed:
			set(r, "0")

	# register r's value (u32)
	fn x(r i64):
		regRead[r] = true
		regName(r)

	# register r's value as a float
	fn f(r i64):
		"0.0" if r == rz else "f32.fromBits({x(r)})"

	# the double of register r and the one after it (the low word first)
	fn d(r i64):
		"0.0" if r == rz else "f64.fromWords({x(r)}, {x(r + 1)})"

	# predicate p's value, negated when `negated`
	fn pred(p i64, negated bool):
		if p == pt: return "false" if negated else "true"
		predRead[p] = true
		"not p{p}" if negated else "p{p}"

	# a constant buffer's word, from the buffers of the program's own stage (each stage binds its own)
	fn constant(bank i64, word str):
		at = "{bank * bankWords} + {word}" if bank > 0 else word
		"p.{stage.constantsName()}[{at}]"

	# an operand as u32 bits
	fn bits(o Operand) str:
		match o.kind:
			Reg: x(o.reg)
			Cbuf: constant(o.bank, "{o.offset / 4}")
			Imm: "{o.imm & 0xFFFF_FFFF}"
			None: "0"

	# an operand as a float: an immediate's 20 bits are the float's top ones
	fn float(o Operand) str:
		match o.kind:
			Reg: f(o.reg)
			Cbuf: "f32.fromBits({bits(o)})"
			Imm: "f32.fromBits({(o.imm & 0xFFFFF) << 12})"
			None: "0.0"

	# an operand as a double: a register pair, two words of a constant buffer, an immediate's 20
	# bits the top of its high word
	fn double(o Operand) str:
		match o.kind:
			Reg: d(o.reg)
			Cbuf: "f64.fromWords({bits(o)}, {constant(o.bank, "{o.offset / 4 + 1}")})"
			Imm: "f64.fromWords(0, {(o.imm & 0xFFFFF) << 12})"
			None: "0.0"

	# an operand as a signed integer
	fn signed(o Operand):
		if o.kind == .Imm: return "{arm64.signedBits(o.imm, 0, 32)}"
		"i32({bits(o)})"

	# a block's first line (`if c:`, `else:`, `loop:`): closeBlock ends it
	fn openBlock(text str):
		line(text)
		depth += 1
		known.clear()

	# the block ended, given a `pass` when it holds nothing
	fn closeBlock():
		if lines.last is l and l.depth < depth: line("pass")
		depth -= 1
		known.clear()

	# opens the if of the instruction's guard predicate (closeGuard closes it)
	fn openGuard(i Instr):
		if i.isGuarded(): openBlock("if {guard(i, false)}:")

	fn closeGuard(i Instr):
		if i.isGuarded(): closeBlock()

pub fn isGuarded(i Instr) bool:
	i.pred != pt or i.predNot or i.flowTest() != alwaysTest

fn isRead(e Emitter, l Line):
	match l.space:
		Register: e.regRead[l.target]
		Predicate: e.predRead[l.target]
		Flag: e.flagRead[l.target]

pub fn regName(r i64) str:
	"rz" if r == rz else "r{r}"

# The lines of the body: the bindings of what it reads, then its code.
pub fn body(e Emitter) str[]:
	out = []
	for r in 0..256:
		if e.regRead[r]: out.push("\t{regName(r)} u32 = 0")
	for p in 0..7:
		if e.predRead[p]: out.push("\tp{p} = false")
	for k, name in flagNames:
		if e.flagRead[k]: out.push("\t{name} = false")
	if e.usesSum:
		for name in ["ca", "cb", "cr"]:
			out.push("\t{name} u32 = 0")
	for l in e.lines:
		text = l.text.copy()
		if l.target >= 0 and not e.isRead(l):
			text = "_{l.text[l.text.indexOf(" = ") ?? 0..]}"
		out.push("{"\t".repeat(l.depth)}{text}")
	out
