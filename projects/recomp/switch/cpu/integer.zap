# What A64's integer instructions do (the Arm ARM's pseudocode, shared functions in J1), on a
# thread's registers: the interpreter calls these with a decoded instruction's fields, and the
# translation writes the same calls with them as constants.

import recomp.switch.arm64

mask32 u64 = 0xFFFF_FFFF

fn widthMask(sf bool) u64:
	u64(-1) if sf else mask32

fn signBit(v u64, sf bool) bool:
	(v >> (63 if sf else 31)) & 1 != 0

# x + y + carry and its flags (AddWithCarry)
pub fn addWithCarry(x u64, y u64, carry bool, sf bool) (u64, u64):
	m = widthMask(sf)
	a = x & m
	b = y & m
	cin = flagBit(carry)
	sum = (a + b + cin) & m
	carryOut = false
	if sf:
		carryOut = sum < a or (sum == a and (b != 0 or carry))
	else:
		carryOut = a + b + cin > m
	overflow = signBit(a, sf) == signBit(b, sf) and signBit(sum, sf) != signBit(a, sf)
	n = signBit(sum, sf)
	flags = flagBit(n) << 3 | flagBit(sum == 0) << 2 | flagBit(carryOut) << 1 | flagBit(overflow)
	(sum, flags)

# v shifted: lsl, lsr, asr, ror (ShiftReg)
pub fn shifted(v u64, kind i64, amount i64, sf bool) u64:
	m = widthMask(sf)
	x = v & m
	if amount == 0: return x
	match kind:
		0: (x << amount) & m
		1: x >> amount
		2:
			if sf: return u64(i64(x) >> amount)
			u64(i64(i32(u32(x))) >> amount) & m
		_: rotated(x, amount, sf)

# v extended (uxtb, uxth, uxtw, uxtx, sxtb, sxth, sxtw, sxtx) then shifted left (ExtendReg)
pub fn extended(v u64, kind i64, shift i64, sf bool) u64:
	width = 8 << (kind & 3)
	x = v
	if width < 64:
		x = v & ((u64(1) << width) - 1)
		if kind >= 4 and (x >> (width - 1)) & 1 != 0: x = x | ~((u64(1) << width) - 1)
	(x << shift) & widthMask(sf)

# v's width rotated right by r
fn rotated(v u64, r i64, sf bool) u64:
	if sf: return v.rotateRight(r)
	u64(u32(v & mask32).rotateRight(r))

pub fn addImm(mut c Cpu, i arm64.Instr):
	y = u64(i.imm)
	r, f = addWithCarry(c.get(i.rn, i.sf), ~y if i.subtract else y, i.subtract, i.sf)
	c.set(i.rd, r, i.sf)
	if i.setFlags: c.setNzcv(f)

pub fn addShifted(mut c Cpu, i arm64.Instr):
	y = shifted(c.get(i.rm, i.sf), i.shift, i.amount, i.sf)
	r, f = addWithCarry(c.get(i.rn, i.sf), ~y if i.subtract else y, i.subtract, i.sf)
	c.set(i.rd, r, i.sf)
	if i.setFlags: c.setNzcv(f)

pub fn addExtended(mut c Cpu, i arm64.Instr):
	y = extended(c.x[i.rm], i.shift, i.amount, i.sf)
	r, f = addWithCarry(c.get(i.rn, i.sf), ~y if i.subtract else y, i.subtract, i.sf)
	c.set(i.rd, r, i.sf)
	if i.setFlags: c.setNzcv(f)

pub fn addCarry(mut c Cpu, i arm64.Instr):
	y = c.get(i.rm, i.sf)
	r, f = addWithCarry(c.get(i.rn, i.sf), ~y if i.subtract else y, c.flagC, i.sf)
	c.set(i.rd, r, i.sf)
	if i.setFlags: c.setNzcv(f)

# and, orr, eor, ands of x and y; ands sets N and Z and clears C and V
fn logic(mut c Cpu, i arm64.Instr, x u64, y u64):
	m = widthMask(i.sf)
	r = match i.opc:
		0, 3: x & y
		1: x | y
		_: x ^ y
	r &= m
	c.set(i.rd, r, i.sf)
	if i.opc == 3: c.setNzcv(flagBit(signBit(r, i.sf)) << 3 | flagBit(r == 0) << 2)

pub fn logicImm(mut c Cpu, i arm64.Instr):
	c.logic(i, c.get(i.rn, i.sf), u64(i.imm))

pub fn logicShifted(mut c Cpu, i arm64.Instr):
	y = shifted(c.get(i.rm, i.sf), i.shift, i.amount, i.sf)
	c.logic(i, c.get(i.rn, i.sf), ~y if i.subtract else y)

pub fn moveWide(mut c Cpu, i arm64.Instr):
	v = u64(i.imm) << i.shift
	match i.opc:
		0: c.set(i.rd, ~v, i.sf)
		2: c.set(i.rd, v, i.sf)
		_: c.set(i.rd, (c.x[i.rd] & ~(u64(0xFFFF) << i.shift)) | v, i.sf)

# sbfm, bfm, ubfm (immr r, imms s): the bits rotated right by r, kept where the masks say
pub fn bitfield(mut c Cpu, i arm64.Instr):
	m = widthMask(i.sf)
	r = i.imm
	s = i.imm2
	src = c.get(i.rn, i.sf)
	turned = rotated(src, r, i.sf)
	# wmask: the bits to replace; tmask: the bits from the source's top bit downwards
	w, t = arm64.bitMasks(i.sf, r, s, i.sf, false) ?? (0, 0)
	wmask = u64(w) & m
	tmask = u64(t) & m
	dst = c.get(i.rd, i.sf) if i.opc == 1 else u64(0)
	bot = (dst & ~wmask) | (turned & wmask)
	top = dst
	if i.opc == 0: top = m if (src >> s) & 1 != 0 else u64(0)
	c.set(i.rd, ((top & ~tmask) | (bot & tmask)) & m, i.sf)

pub fn extract(mut c Cpu, i arm64.Instr):
	lo = c.get(i.rm, i.sf)
	hi = c.get(i.rn, i.sf)
	if i.imm == 0: return c.set(i.rd, lo, i.sf)
	left = (64 if i.sf else 32) - i.imm
	c.set(i.rd, ((lo >> i.imm) | (hi << left)) & widthMask(i.sf), i.sf)

pub fn condCompare(mut c Cpu, i arm64.Instr):
	if not c.holds(i.cond): return c.setNzcv(u64(i.imm))
	y = u64(i.rm) if i.pair else c.get(i.rm, i.sf)
	_, f = addWithCarry(c.get(i.rn, i.sf), ~y if i.subtract else y, i.subtract, i.sf)
	c.setNzcv(f)

pub fn condSelect(mut c Cpu, i arm64.Instr):
	if c.holds(i.cond): return c.set(i.rd, c.get(i.rn, i.sf), i.sf)
	y = c.get(i.rm, i.sf)
	r = match i.opc:
		0: y
		1: y + 1
		2: ~y
		_: 0 - y
	c.set(i.rd, r & widthMask(i.sf), i.sf)

fn reverseBits(v u64, width i64) u64:
	r = u64(0)
	for b in 0..width:
		if (v >> b) & 1 != 0: r = r | (u64(1) << (width - 1 - b))
	r

# the bytes of each `chunk`-byte container of v reversed
fn reverseBytes(v u64, chunk i64, width i64) u64:
	r = u64(0)
	for at in (0..width / 8 / chunk).map(it * chunk * 8):
		for k in 0..chunk:
			byte = (v >> (at + k * 8)) & 0xFF
			r |= byte << (at + (chunk - 1 - k) * 8)
	r

pub fn oneSource(mut c Cpu, i arm64.Instr):
	width = 64 if i.sf else 32
	v = c.get(i.rn, i.sf)
	r = match i.opc:
		0: reverseBits(v, width)
		1: reverseBytes(v, 2, width)
		2: reverseBytes(v, 4, width) if i.sf else reverseBytes(v, 4, 32)
		3: reverseBytes(v, 8, 64)
		4: u64(v.leadingZeros() - (64 - width))
		_:
			flipped = (v ^ (v >> 1)) & (widthMask(i.sf) >> 1)
			u64(flipped.leadingZeros() - (64 - width) - 1)
	if i.opc == 2 and not i.sf: r = reverseBytes(v, 4, 32)
	c.set(i.rd, r, i.sf)

pub fn twoSource(mut c Cpu, i arm64.Instr):
	a = c.get(i.rn, i.sf)
	b = c.get(i.rm, i.sf)
	count = i64(b & (63 if i.sf else 31))
	r = match i.opc:
		2: u64(0) if b == 0 else a / b
		3: signedDivide(a, b, i.sf)
		8: shifted(a, 0, count, i.sf)
		9: shifted(a, 1, count, i.sf)
		10: shifted(a, 2, count, i.sf)
		11: shifted(a, 3, count, i.sf)
		_: crc(c, i, a, b)
	c.set(i.rd, r, i.sf)

fn signedDivide(a u64, b u64, sf bool) u64:
	if b == 0: return 0
	if sf:
		if a == u64(1) << 63 and b == u64(-1): return a
		return u64(i64(a) / i64(b))
	x = i64(i32(u32(a)))
	y = i64(i32(u32(b)))
	u64(x / y) & mask32

# crc32b/h/w/x (opc 16-19) and crc32cb/h/w/x (20-23): the accumulator in rn's 32 bits, the
# value's low bytes in rm, bit-reflected as the instruction defines
fn crc(c Cpu, i arm64.Instr, acc u64, value u64) u64:
	poly = u64(0x82F6_3B78) if i.opc >= 20 else u64(0xEDB8_8320)
	n = 1 << (i.opc & 3)
	r = acc & mask32
	v = c.x[i.rm]
	for k in 0..n * 8:
		bitIn = (v >> k) & 1
		low = (r ^ bitIn) & 1
		r >>= 1
		if low != 0: r = r ^ poly
	r

# the high 64 bits of a's and b's 128-bit product, unsigned
pub fn mulHigh(a u64, b u64) u64:
	aLo = a & mask32
	aHi = a >> 32
	bLo = b & mask32
	bHi = b >> 32
	ll = aLo * bLo
	lh = aLo * bHi
	hl = aHi * bLo
	hh = aHi * bHi
	mid = (ll >> 32) + (lh & mask32) + (hl & mask32)
	hh + (lh >> 32) + (hl >> 32) + (mid >> 32)

pub fn threeSource(mut c Cpu, i arm64.Instr):
	a = c.x[i.ra]
	n = c.x[i.rn]
	m = c.x[i.rm]
	match i.opc:
		0: c.set(i.rd, a + n * m, i.sf)
		1: c.set(i.rd, a - n * m, i.sf)
		2: c.set(i.rd, a + u64(i64(i32(u32(n & mask32))) * i64(i32(u32(m & mask32)))), true)
		3: c.set(i.rd, a - u64(i64(i32(u32(n & mask32))) * i64(i32(u32(m & mask32)))), true)
		4:
			hi = mulHigh(n, m)
			if i64(n) < 0: hi = hi - m
			if i64(m) < 0: hi = hi - n
			c.set(i.rd, hi, true)
		10: c.set(i.rd, a + (n & mask32) * (m & mask32), true)
		11: c.set(i.rd, a - (n & mask32) * (m & mask32), true)
		12: c.set(i.rd, mulHigh(n, m), true)
		_: c.halted = "three-source opc {i.opc}"
