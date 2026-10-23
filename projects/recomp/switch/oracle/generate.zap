# Random instructions of each encoding class (the fixed bits of the class, the others random),
# with registers that make them run: an access's base points into the scratch, its index is
# small, and the forms the Arm ARM leaves unpredictable (a write-back onto its own data
# register, a pair loaded into one register) are drawn again.

pub type Class:
	name str
	mask i64
	value i64
	access bool = false   # its rn is a base into the scratch
	store bool = false   # it may write the scratch
	vector bool = false   # it may use the vector registers (bit 26 of an access kept)

# long: a table
pub classes = [
	Class("adr", 0x1F00_0000, 0x1000_0000),
	Class("add/sub imm", 0x1F80_0000, 0x1100_0000),
	Class("logic imm", 0x1F80_0000, 0x1200_0000),
	Class("move wide", 0x1F80_0000, 0x1280_0000),
	Class("bitfield", 0x1F80_0000, 0x1300_0000),
	Class("extract", 0x1F80_0000, 0x1380_0000),
	Class("logic shifted", 0x1F00_0000, 0x0A00_0000),
	Class("add/sub shifted", 0x1F20_0000, 0x0B00_0000),
	Class("add/sub extended", 0x1F20_0000, 0x0B20_0000),
	Class("add/sub carry", 0x1FE0_FC00, 0x1A00_0000),
	Class("cond compare", 0x1FE0_0410, 0x1A40_0000),
	Class("cond select", 0x1FE0_0800, 0x1A80_0000),
	Class("two source", 0x5FE0_0000, 0x1AC0_0000),
	Class("one source", 0x5FE0_0000, 0x5AC0_0000),
	Class("three source", 0x1F00_0000, 0x1B00_0000),
	Class("branch", 0x7C00_0000, 0x1400_0000),
	Class("branch cond", 0xFF00_0010, 0x5400_0000),
	Class("compare branch", 0x7E00_0000, 0x3400_0000),
	Class("test branch", 0x7E00_0000, 0x3600_0000),
	Class("branch reg", 0xFF9F_FC1F, 0xD61F_0000),
	Class("load/store imm12", 0x3B00_0000, 0x3900_0000, access = true, store = true),
	Class("load/store imm9", 0x3B20_0000, 0x3800_0000, access = true, store = true),
	Class("load/store reg", 0x3B20_0C00, 0x3820_0800, access = true, store = true),
	Class("load/store pair", 0x3A00_0000, 0x2800_0000, access = true, store = true),
	Class("exclusive", 0x3F00_0000, 0x0800_0000, access = true, store = true),
	Class("structure", 0xBFBF_0000, 0x0C00_0000, access = true, store = true, vector = true),
	Class("structure post", 0xBF80_0000, 0x0C80_0000, access = true, store = true, vector = true),
	Class("structure lane", 0xBF9F_0000, 0x0D00_0000, access = true, store = true, vector = true),
	Class(
		"structure lane post",
		0xBF80_0000,
		0x0D80_0000,
		access = true,
		store = true,
		vector = true
	),
	Class("fp move abs neg sqrt", 0xFFBE_7C00, 0x1E20_4000, vector = true),
	Class("fp convert", 0xFF3E_7C00, 0x1E22_4000, vector = true),
	Class("fp round", 0xFFBC_7C00, 0x1E24_4000, vector = true),
	Class("fp compare", 0xFFA0_FC07, 0x1E20_2000, vector = true),
	Class("fp cond compare", 0xFFA0_0C00, 0x1E20_0400, vector = true),
	Class("fp two source", 0xFFA0_0C00, 0x1E20_0800, vector = true),
	Class("fp cond select", 0xFFA0_0C00, 0x1E20_0C00, vector = true),
	Class("fp immediate", 0xFFA0_1FE0, 0x1E20_1000, vector = true),
	Class("fp three source", 0xFF80_0000, 0x1F00_0000, vector = true),
	Class("fp int conversion", 0x7F20_FC00, 0x1E20_0000, vector = true),
	Class("fp fixed conversion", 0x7F20_0000, 0x1E00_0000, vector = true)
]

# a register's value drawn from the edges and from random bits
fn value(mut rng Random) u64:
	match rng.nextInt(0, 10):
		0: 0
		1: u64(-1)
		2: 0x7FFF_FFFF
		3: 0x8000_0000
		4: 0xFFFF_FFFF
		5: u64(1) << 63
		6: u64(rng.nextInt(0, 64))
		7: rng.nextBits() & 0xFFFF_FFFF
		_: rng.nextBits()

# a float of the format's bits with an exponent near 1 (so sums cancel and products stay in
# range), or at the edges: denormal, largest, infinity, NaN
fn floatBits(mut rng Random, expBits i64, fracBits i64):
	frac = rng.nextBits() & ((u64(1) << fracBits) - 1)
	bias = (1 << (expBits - 1)) - 1
	sign = rng.nextBits() & 1
	exponent = match rng.nextInt(0, 10):
		0: 0
		1: (1 << expBits) - 1
		2: (1 << expBits) - 2
		3: 1
		_: bias + rng.nextInt(-12, 13)
	if rng.nextInt(0, 6) == 0: frac = 0
	sign << (expBits + fracBits) | u64(exponent) << fracBits | frac

# a vector register's word: random bits, a double, or two floats, mostly of exponents near 1
fn vectorValue(mut rng Random) u64:
	match rng.nextInt(0, 8):
		0: 0
		1: rng.nextBits()
		2, 3, 4: rng.floatBits(11, 52)
		_: rng.floatBits(8, 23) | rng.floatBits(8, 23) << 32

fn field(w i64, at i64, width i64):
	(w >> at) & ((1 << width) - 1)

# whether the scalar floating-point word is in Armv8.0 (the machine may run later ones: half
# precision, frint32/64, bfcvt, fjcvtzs)
fn isArmV80Float(w i64):
	ftype = field(w, 22, 2)
	opcode = field(w, 15, 6)
	registerForm = field(w, 21, 1) == 1 and field(w, 24, 1) == 0
	if registerForm and field(w, 10, 5) == 0b1_0000:
		if opcode >> 2 == 1: return opcode & 3 != 2
		return ftype != 3 and opcode >> 2 != 4
	if registerForm and field(w, 10, 6) == 0:
		fjcvtzs = field(w, 31, 1) == 0 and ftype == 1 and field(w, 16, 5) == 0b1_1110
		return ftype != 3 and not fjcvtzs
	ftype != 3

# the word made runnable for its class (no vector registers here), or none to draw again
fn fixed(c Class, word i64) i64?:
	if c.name.startsWith("fp ") and not isArmV80Float(word): return none
	w = word if c.vector else word & ~(1 << 26)   # the general registers only, unless vector
	if c.name == "load/store imm12": w = w & ~(0x3F << 16)   # an offset within the scratch
	if c.name == "load/store reg":
		if field(w, 13, 3) & 2 == 0: w = w | (2 << 13)
	if c.name == "exclusive":
		if field(w, 23, 1) == 1: w = (w | (1 << 15)) & ~(1 << 21)
		if field(w, 22, 1) == 1 or field(w, 23, 1) == 1: w = w | (31 << 16)
		if field(w, 21, 1) == 0: w = w | (31 << 10)
	rt = field(w, 0, 5)
	rn = field(w, 5, 5)
	rm = field(w, 16, 5)
	rt2 = field(w, 10, 5)
	if not c.access: return w
	writeBack = c.name == "load/store imm9" and field(w, 10, 1) == 1 or
		c.name == "load/store pair" and field(w, 23, 2) != 2
	if writeBack and rn != 31 and (rt == rn or c.name == "load/store pair" and rt2 == rn):
		return none
	if c.name == "load/store pair" and field(w, 22, 1) == 1 and rt == rt2: return none
	if c.name == "load/store reg" and (rm == rn or rm == 31): return none
	if c.name.endsWith("post") and rm == rn: return none
	if c.name == "exclusive" and field(w, 22, 1) == 0 and field(w, 23, 1) == 0 and
		(rm in [rt, rn, rt2]):
		return none
	w

# FPCR for a case: round to nearest and nothing flushed, unless the class uses the vector
# registers, which draw the rounding mode (bits 23:22), flush to zero (24) and default NaN (25)
fn fpcrDrawn(mut rng Random, c Class) u64:
	if not c.vector: return 0
	if rng.nextInt(0, 3) == 0: return 0
	rng.nextBits() & 0x0380_0000

# A case's word and its state before (case.zap's places), the base at `base`.
pub fn draw(mut rng Random, c Class, base i64) (i64, u64[]):
	word = 0
	while true:
		bitsDrawn = i64(rng.nextBits() & 0xFFFF_FFFF)
		word = c.fixed((bitsDrawn & ~c.mask) | c.value) ?? continue
		break
	regs = []
	loop 31:
		regs.push(rng.value())
	regs.push(u64(base))   # sp, 16-aligned
	regs.push(u64(rng.nextInt(0, 16)))
	regs.push(0)   # pc: the code's address, set by gdb
	loop 64:
		regs.push(rng.vectorValue())
	regs.push(rng.fpcrDrawn(c))
	regs.push(0)
	if c.access:
		rn = field(word, 5, 5)
		if rn != 31: regs[rn] = u64(base)
		if c.name == "load/store reg" or c.name.endsWith("post") and field(word, 16, 5) != 31:
			regs[field(word, 16, 5)] = u64(rng.nextInt(0, 128))
	(word, regs)
