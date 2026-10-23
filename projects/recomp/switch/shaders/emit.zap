# The Zap GPU code of one program as the translation writes it: registers are u32 locals (`r5`,
# `rz` the zero), predicates bool locals (`p2`, PT `true`), a float a register's bits
# (`f32.fromBits(r5)`); constant buffer `bank`'s word w is `p.constants[bank * 16384 + w]`.
# A local the code never reads takes no binding, its writes going to `_`.

import recomp.switch.arm64

# words of a constant buffer bank: 64 KB
pub bankWords = 16_384

pub type Line:
	text str
	depth i64
	target i64 = -1   # the register (or with isPred the predicate) it assigns, -1 none
	isPred bool = false

# A texture the program reads: its handle (the texture constant buffer's word) and kind.
pub type TextureUse:
	handle i64
	kind TextureKind

pub type TextureKind:
	Plain   # Texture
	Layered   # TextureArray
	Shadow   # ShadowMap

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
	inputs i64[] = []   # the attributes (indices) read
	outputs i64[] = []   # the attributes written
	textures TextureUse[] = []
	targets i64[] = []   # the render targets a pixel stage writes
	constants bool = false
	localWords i64 = 0
	sharedWords i64 = 0
	missing str[] = []

	fn line(text str):
		lines.push(Line(text = text.copy(), depth))

	# rN = value, or `_ = value` for RZ (or a register nothing reads: see `body`)
	fn set(r i64, value str):
		if r == rz:
			line("_ = {value}")
			return
		lines.push(Line(text = "{regName(r)} = {value}", depth, target = r))

	fn setF(r i64, value str):
		set(r, "({value}).toBits()")

	fn setP(p i64, value str):
		if p == pt:
			line("_ = {value}")
			return
		lines.push(Line(text = "p{p} = {value}", depth, target = p, isPred = true))

	# what the translation cannot write yet (or Zap cannot): a note, the destinations zeroed
	fn lack(i Instr, why str, zeroed i64[]):
		missing.push("{i.op} at {i.at:x}: {why}")
		line("# not translated: {i.op} ({why})")
		for r in zeroed:
			set(r, "0")

	# register r's value (u32)
	fn x(r i64):
		regRead[r] = true
		regName(r)

	# register r's value as a float
	fn f(r i64):
		"0.0" if r == rz else "f32.fromBits({x(r)})"

	# predicate p's value, negated when `negated`
	fn pred(p i64, negated bool):
		if p == pt: return "false" if negated else "true"
		predRead[p] = true
		"not p{p}" if negated else "p{p}"

	fn constant(bank i64, word str):
		constants = true
		"p.constants[{bank * bankWords} + {word}]" if bank > 0 else "p.constants[{word}]"

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

	# an operand as a signed integer
	fn signed(o Operand):
		if o.kind == .Imm: return "{arm64.signedBits(o.imm, 0, 32)}"
		"i32({bits(o)})"

	# a block's first line (`if c:`, `else:`, `loop:`): closeBlock ends it
	fn openBlock(text str):
		line(text)
		depth += 1

	# the block ended, given a `pass` when it holds nothing
	fn closeBlock():
		if lines.last is l and l.depth < depth: line("pass")
		depth -= 1

	# opens the if of the instruction's guard predicate (closeGuard closes it)
	fn openGuard(i Instr):
		if i.isGuarded(): openBlock("if {pred(i.pred, i.predNot)}:")

	fn closeGuard(i Instr):
		if i.isGuarded(): closeBlock()

pub fn isGuarded(i Instr) bool:
	i.pred != pt or i.predNot

pub fn regName(r i64) str:
	"rz" if r == rz else "r{r}"

# The lines of the body: the bindings of what it reads, then its code.
pub fn body(e Emitter) str[]:
	out = []
	for r in 0..256:
		if e.regRead[r]: out.push("\t{regName(r)} u32 = 0")
	for p in 0..7:
		if e.predRead[p]: out.push("\tp{p} = false")
	for l in e.lines:
		text = l.text.copy()
		if l.target >= 0 and not (e.predRead[l.target] if l.isPred else e.regRead[l.target]):
			text = "_{l.text[l.text.indexOf(" = ") ?? 0..]}"
		out.push("{"\t".repeat(l.depth)}{text}")
	out
