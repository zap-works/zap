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
	Class("exclusive", 0x3F00_0000, 0x0800_0000, access = true, store = true)
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

fn field(w i64, at i64, width i64):
	(w >> at) & ((1 << width) - 1)

# the word made runnable for its class (no vector registers here), or none to draw again
fn fixed(c Class, word i64) i64?:
	w = word & ~(1 << 26)   # the general registers only
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
	if c.name == "exclusive" and field(w, 22, 1) == 0 and field(w, 23, 1) == 0 and
		(rm in [rt, rn, rt2]):
		return none
	w

# A case's word and its registers before (x0-x30, sp, nzcv), the base at `base`.
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
	if c.access:
		rn = field(word, 5, 5)
		if rn != 31: regs[rn] = u64(base)
		if c.name == "load/store reg": regs[field(word, 16, 5)] = u64(rng.nextInt(0, 128))
	(word, regs)
