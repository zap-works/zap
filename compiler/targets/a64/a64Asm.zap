# Machine code for AArch64 (the arm64 of Linux and Android): each instruction one 32-bit word,
# written into the assembler's code as x64.zap's bytes are, its labels and data references fixups
# the ELF writer resolves (elf.zap). Registers are numbers 0..30; 31 is sp or xzr, as the
# instruction reads it.

a64Zr = 31
a64Sp = 31
a64Fp = 29
a64Lr = 30

# the scratch registers of an instruction's code (no vreg lives in them): an operand or an
# address, an index or a large offset, a stored value or a second operand
a64T0 = 16
a64T1 = 17
a64T2 = 15

a64DmbIsh = 0xD503_3BBF   # dmb ish: every load and store before it seen before any after
a64LdaddAl = 0xF8E0_0000   # ldaddal xs, xt, [xn]: xt the word before, xs added; a full barrier
a64CasAl = 0xC8E0_FC00   # casal xs, xt, [xn]: xt stored when the word is xs, xs the word before

# the conditions of b.cond, csel and cset
a64Eq = 0
a64Ne = 1
a64Hs = 2
a64Lo = 3
a64Mi = 4
a64Vs = 6
a64Hi = 8
a64Ls = 9
a64Ge = 10
a64Lt = 11
a64Gt = 12
a64Le = 13

# the fixups of AArch64 code: a b or bl (imm26), a b.cond or cbz (imm19), and an adrp and the add
# after it reaching the data at an offset, or a label's code
fxA64Jump = 10
fxA64Cond = 11
fxA64Page = 12
fxA64Low = 13
fxA64PageCode = 14
fxA64LowCode = 15
fxA64LowLoad = 16   # an ldr of a double by the data's page offset, as fxA64Low is an add's

# the register operations, 64 bits (a64Narrow: their 32-bit forms)
a64Add = 0x8B00_0000
a64Sub = 0xCB00_0000
a64Adds = 0xAB00_0000
a64Subs = 0xEB00_0000
a64And = 0x8A00_0000
a64Orr = 0xAA00_0000
a64Eor = 0xCA00_0000
a64Ands = 0xEA00_0000
a64Lslv = 0x9AC0_2000
a64Lsrv = 0x9AC0_2400
a64Asrv = 0x9AC0_2800
a64Rorv = 0x9AC0_2C00
a64Sdiv = 0x9AC0_0C00
a64Udiv = 0x9AC0_0800
a64Mul = 0x9B00_7C00
a64Smulh = 0x9B40_7C00
a64Umulh = 0x9BC0_7C00
a64Smull = 0x9B20_7C00
a64Clz = 0xDAC0_1000
a64Rbit = 0xDAC0_0000
a64Rev = 0xDAC0_0C00

# the float operations on d registers
a64Fadd = 0x1E60_2800
a64Fsub = 0x1E60_3800
a64Fmul = 0x1E60_0800
a64Fdiv = 0x1E60_1800
a64Fneg = 0x1E61_4000
a64Fsqrt = 0x1E61_C000
a64Fmov = 0x1E60_4000
a64FcvtDS = 0x1E62_4000   # a single from a double
a64FcvtSD = 0x1E22_C000   # a double from a single
a64FmovDX = 0x9E67_0000   # d = the bits of x
a64FmovXD = 0x9E66_0000   # x = the bits of d
a64FmovSW = 0x1E27_0000
a64FmovWS = 0x1E26_0000
a64Scvtf = 0x9E62_0000
a64Fcvtzs = 0x9E78_0000

fn a64(mut a Asm, word i64):
	bytesPut32(a.code, word)

# an instruction whose field the fixup of kind fills with where target is
fn a64Fixed(mut a Asm, kind i64, target i64, word i64):
	a.fixKind.push(u8(kind))
	a.fixAt.push(i32(a.code.len))
	a.fixTarget.push(u32(target))
	a.fixJump.push(0)
	a.a64(word)

# the 32-bit form of a register operation
fn a64Narrow(op i64):
	op & 0x7FFF_FFFF

# op d, n, m
fn a64Op3(mut a Asm, op i64, d i64, n i64, m i64):
	a.a64(op | m << 16 | n << 5 | d)

# op d, n (one source: clz, rbit, rev, the float moves and conversions)
fn a64Op2(mut a Asm, op i64, d i64, n i64):
	a.a64(op | n << 5 | d)

# op d, n, m shifted by s (kind 0 lsl, 1 lsr, 2 asr): add, sub, and, orr or eor's shifted form
fn a64Op3Shifted(mut a Asm, op i64, d i64, n i64, m i64, kind i64, s i64):
	a.a64(op | kind << 22 | m << 16 | s << 10 | n << 5 | d)

fn a64Mov(mut a Asm, d i64, s i64):
	if d != s:
		a.a64(0xAA00_03E0 | s << 16 | d)   # orr d, xzr, s

# v's four 16-bit halves
fn a64Halves(v i64):
	(0..4).map((v >> (16 * it)) & 0xFFFF)

# whether a64MovImm writes v with a movz or a movn and its movks rather than a logical immediate
fn a64ImmInverted(halves i64[]):
	halves.count(0xFFFF) > halves.count(0)

# the movz or movn and movks that write v
fn a64ImmMoves(v i64):
	halves = a64Halves(v)
	fill = 0xFFFF if a64ImmInverted(halves) else 0
	halves.count(it != fill).max(1)

# v with its half k as half k + 1 (a logical immediate that lacks only half k, perhaps)
fn a64ImmAsNeighbour(v i64, k i64):
	halves = a64Halves(v)
	v ^ (halves[k] ^ halves[(k + 1) % 4]) << (16 * k)

# the half of v a logical immediate lacks (a64ImmAsNeighbour), -1 when none does
fn a64ImmLacking(v i64):
	(0..4).find(a64BitMask(a64ImmAsNeighbour(v, it)) >= 0) ?? -1

# the instructions a64MovImm writes v in
fn a64MovImmLength(v i64):
	moves = a64ImmMoves(v)
	if moves > 1 and a64BitMask(v) >= 0: return 1
	if moves > 2 and a64ImmLacking(v) >= 0: return 2
	moves

# d = v: a movz or a movn, then a movk for each other half that differs; a logical immediate
# instead when it takes fewer (an orr from xzr, and a movk of the one half it lacks)
fn a64MovImm(mut a Asm, d i64, v i64):
	halves = a64Halves(v)
	inverted = a64ImmInverted(halves)
	fill = 0xFFFF if inverted else 0
	moves = a64ImmMoves(v)
	if moves > 1 and a.a64LogicalImm(a64Orr, d, a64Zr, v, true): return
	lack = a64ImmLacking(v) if moves > 2 else -1
	if lack >= 0:
		a.a64LogicalImm(a64Orr, d, a64Zr, a64ImmAsNeighbour(v, lack), true)
		a.a64(0xF280_0000 | lack << 21 | halves[lack] << 5 | d)   # movk
		return
	first = halves.findIndex(it != fill) ?? 0
	if inverted:
		a.a64(0x9280_0000 | first << 21 | (halves[first] ^ 0xFFFF) << 5 | d)   # movn
	else:
		a.a64(0xD280_0000 | first << 21 | halves[first] << 5 | d)   # movz
	for k in (first + 1)..4:
		if halves[k] != fill:
			a.a64(0xF280_0000 | k << 21 | halves[k] << 5 | d)   # movk

# The N:immr:imms field of the logical immediate v (bits 22..10 of and, orr and eor), -1 when v
# is none: an element of 2, 4, 8, 16, 32 or 64 bits repeated, its ones one run, rotated
fn a64BitMask(v i64):
	if v == 0 or v == -1: return -1
	size = 64
	while size > 2:
		half = size / 2
		mask = (1 << half) - 1
		if v & mask != (v >> half) & mask: break
		size = half
	all = u64(-1) if size == 64 else u64((1 << size) - 1)
	e = u64(v) & all
	ones = e.bitCount()
	run = (u64(1) << ones) - 1
	for r in 0..size:
		rotated = e if r == 0 else (e >> r | e << (size - r)) & all
		if rotated == run:
			return (1 if size == 64 else 0) << 12 | (size - r) % size << 6 |
				(-size << 1) & 0x3F | ones - 1
	-1

# d = n op v for and, orr, eor or ands (a64And, a64Orr, a64Eor, a64Ands; 32 bits when not wide)
# by its logical immediate; false when v has none
fn a64LogicalImm(mut a Asm, op i64, d i64, n i64, v i64, wide bool):
	low = v & 0xFFFF_FFFF
	field = a64BitMask(v if wide else low | low << 32)
	if field < 0: return false
	imm = op & 0xE000_0000 | 0x1200_0000 | field << 10 | n << 5 | d
	a.a64(imm if wide else a64Narrow(imm))
	true

# d = the double of these bits: fmov's 8-bit immediate (sign, 3 bits of exponent, 4 of
# fraction), xzr's bits for 0.0, one mov and an fmov for bits with one half set, else loaded from
# the data area (adrp and ldr)
fn a64FloatConst(mut g Gen, d i64, bits i64):
	if a64FmovImm(bits):
		b = (bits >> 61) & 1
		g.a.a64(0x1E60_1000 | ((bits >> 56) & 0x80 | b << 6 | (bits >> 48) & 0x3F) << 13 | d)
		return
	if bits == 0:
		g.a.a64Op2(a64FmovDX, d, a64Zr)
		return
	if (0..4).count((bits >> (16 * it)) & 0xFFFF != 0) > 1:
		off = g.floatConst(bits)
		g.a.a64Fixed(fxA64Page, off, 0x9000_0000 | a64T0)   # adrp x16, page
		g.a.a64Fixed(fxA64LowLoad, off, 0xFD40_0000 | a64T0 << 5 | d)   # ldr d, [x16, lo12]
		return
	g.a.a64MovImm(a64T0, bits)
	g.a.a64Op2(a64FmovDX, d, a64T0)

# whether the double of these bits is fmov's 8-bit immediate
fn a64FmovImm(bits i64):
	b = (bits >> 61) & 1
	bits & 0xFFFF_FFFF_FFFF == 0 and (bits >> 54) & 0xFF == 0xFF * b and (bits >> 62) & 1 != b

# whether a64FloatConst writes the double of these bits in more than one instruction
fn a64FloatLong(bits i64):
	bits != 0 and not a64FmovImm(bits)

# d = n + imm, either of them may be sp; an immediate past 24 bits through x17
fn a64AddImm(mut a Asm, d i64, n i64, imm i64):
	if imm == 0 and d == n: return
	if imm.abs() >= 1 << 24:
		a.a64MovImm(a64T1, imm)
		a.a64Op3(0x8B20_6000, d, n, a64T1)   # add d, n, x17, uxtx
		return
	op = 0x9100_0000 if imm >= 0 else 0xD100_0000   # add / sub, immediate
	m = imm.abs()
	if m >= 4096:
		a.a64(op | 1 << 22 | (m >> 12) << 10 | n << 5 | d)   # the high part, lsl 12
		if m & 0xFFF != 0:
			a.a64(op | (m & 0xFFF) << 10 | d << 5 | d)
		return
	a.a64(op | m << 10 | n << 5 | d)

# what a64Access moves: an integer register loaded or stored, or a float or vector register
accessLoad = 0
accessStore = 1
accessFloat = 2

# a load or a store of rt at base + off (base may be sp) by op, the form of an offset scaled by
# size (its bit 24 clear: of an unscaled one): the scaled form when off is a multiple of size in
# reach, the unscaled one within 256 bytes, else the address made in a register: an integer
# load's own, else the first scratch that holds neither rt nor base (an operand already in x17
# survives the load of the next)
fn a64Access(mut a Asm, op i64, size i64, rt i64, from i64, at i64, kind i64):
	base, off = a64FrameBase(from, at)
	if off >= 0 and off % size == 0 and off / size < 4096:
		a.a64(op | (off / size) << 10 | base << 5 | rt)
	elif off >= -256 and off < 256:
		a.a64(op ^ 0x0100_0000 | (off & 0x1FF) << 12 | base << 5 | rt)
	else:
		r = rt if kind == accessLoad and rt != base and rt != a64Zr
			else [a64T1, a64T2, 8].find(it != base and (kind == accessFloat or it != rt)) ?? a64T1
		a.a64MovImm(r, off)
		a.a64Op3(0x8B20_6000, r, base, r)   # add r, base, r, uxtx
		a.a64(op | r << 5 | rt)

# the bytes of the function's frame below x29, -1 outside a function's frame (a64EmitWhole's)
mut a64FrameBytes = -1

# whether the function being emitted may pass 1 MB of code (a64EmitWhole): its conditional
# branches then go through a b (a64BCond)
mut a64Far = false
# the instructions of the form past which a function is emitted far (about 1 MB at 6 words each)
a64FarInsts = 40_000

# the base and offset of base + off: a frame slot more than 256 bytes below x29 from sp, which a
# scaled offset reaches further from
fn a64FrameBase(base i64, off i64):
	if base == a64Fp and off < -256 and a64FrameBytes >= 0: return (a64Sp, off + a64FrameBytes)
	(base, off)

# the same at base + index (times size when shifted): the register offset form
fn a64AccessIndexed(mut a Asm, op i64, rt i64, base i64, index i64, shifted bool):
	a.a64(
		op ^ 0x0100_0000 | 0x0020_6800 | index << 16 | (1 << 12 if shifted else 0) | base << 5 | rt
	)

# the opcode of a load of size bytes into an integer register, zero- or sign-extended (a float
# register's: with a64FloatAccess)
fn a64LoadOp(size i64, uns bool):
	size.trailingZeros() << 30 | (0x3940_0000 if uns or size == 8 else 0x3980_0000)

fn a64StoreOp(size i64):
	size.trailingZeros() << 30 | 0x3900_0000

a64FloatAccess = 0x0400_0000

# rt = the size bytes at base + off, zero- or sign-extended
fn a64Load(mut a Asm, rt i64, base i64, off i64, size i64, uns bool):
	a.a64Access(a64LoadOp(size, uns), size, rt, base, off, accessLoad)

# the low size bytes of rt stored at base + off
fn a64Store(mut a Asm, rt i64, base i64, off i64, size i64):
	a.a64Access(a64StoreOp(size), size, rt, base, off, accessStore)

fn a64Ldr(mut a Asm, rt i64, base i64, off i64):
	a.a64Load(rt, base, off, 8, true)

fn a64Str(mut a Asm, rt i64, base i64, off i64):
	a.a64Store(rt, base, off, 8)

# a float register loaded from or stored to base + off: a double (size 8) or a single (4)
fn a64LoadF(mut a Asm, ft i64, base i64, off i64, size i64):
	a.a64Access(a64LoadOp(size, true) | a64FloatAccess, size, ft, base, off, accessFloat)

fn a64StoreF(mut a Asm, ft i64, base i64, off i64, size i64):
	a.a64Access(a64StoreOp(size) | a64FloatAccess, size, ft, base, off, accessFloat)

# stp or ldp of two words at base + off (a multiple of 8 within 512 bytes), of d registers when
# float; mode 0 the offset alone, 1 base moved by off first (pre-index), 2 moved after
# (post-index)
fn a64Pair(mut a Asm, load bool, r1 i64, r2 i64, base i64, off i64, mode i64, float bool = false):
	op = (0xA900_0000 if mode == 0 else 0xA980_0000 if mode == 1 else 0xA880_0000) |
		(1 << 22 if load else 0)
	if float: op = op ^ 0xC400_0000   # opc 01 and V: d registers
	a.a64(op | ((off / 8) & 0x7F) << 15 | r2 << 10 | base << 5 | r1)

# d = n shifted by the constant s: kind 0 lsl, 1 lsr, 2 asr (ubfm, sbfm)
fn a64ShiftImm(mut a Asm, kind i64, d i64, n i64, s i64, wide bool):
	bits = 64 if wide else 32
	k = s & (bits - 1)
	unsigned = 0xD340_0000 if wide else 0x5300_0000   # ubfm
	signed = 0x9340_0000 if wide else 0x1300_0000   # sbfm
	base = unsigned if kind < 2 else signed
	immr, imms = ((bits - k) & (bits - 1), bits - 1 - k) if kind == 0 else (k, bits - 1)
	a.a64(base | immr << 16 | imms << 10 | n << 5 | d)

# d = the low size bytes of n, zero- or sign-extended to 64 bits
fn a64Extend(mut a Asm, d i64, n i64, size i64, uns bool):
	if size >= 8:
		a.a64Mov(d, n)
	elif uns and size == 4:
		a.a64(0x2A00_03E0 | n << 16 | d)   # mov wd, wn
	elif uns:
		a.a64(0x5300_0000 | (8 * size - 1) << 10 | n << 5 | d)   # uxtb, uxth
	else:
		a.a64(0x9340_0000 | (8 * size - 1) << 10 | n << 5 | d)   # sxtb, sxth, sxtw

# cmp n, m
fn a64Cmp(mut a Asm, n i64, m i64):
	a.a64Op3(a64Subs, a64Zr, n, m)

# cmp n, v as one instruction (cmp or cmn of an immediate); false when v does not fit one
fn a64CmpImm(mut a Asm, n i64, v i64):
	if v >= 0 and v < 4096:
		a.a64(0xF100_001F | v << 10 | n << 5)
	elif v < 0 and v > -4096:
		a.a64(0xB100_001F | (-v) << 10 | n << 5)
	else:
		return false
	true

# cmp n, v: an immediate when v fits one, else through scratch
fn a64CmpValue(mut a Asm, n i64, v i64, scratch i64):
	if a.a64CmpImm(n, v): return
	a.a64MovImm(scratch, v)
	a.a64Cmp(n, scratch)

# d = cond ? n : m
fn a64Csel(mut a Asm, d i64, n i64, m i64, cond i64):
	a.a64(0x9A80_0000 | m << 16 | cond << 12 | n << 5 | d)

# d = 1 when cond holds, else 0
fn a64Cset(mut a Asm, d i64, cond i64):
	a.a64(0x9A9F_07E0 | (cond ^ 1) << 12 | d)   # csinc d, xzr, xzr, !cond

fn a64B(mut a Asm, label i64):
	a.a64Fixed(fxA64Jump, label, 0x1400_0000)

fn a64Bl(mut a Asm, label i64):
	a.a64Fixed(fxA64Jump, label, 0x9400_0000)

# a conditional branch reaches 1 MB either way; in a function that may be larger (a64Far) it is
# the opposite condition over a b, which reaches 128 MB
fn a64BCond(mut a Asm, cond i64, label i64):
	if not a64Far: return a.a64Fixed(fxA64Cond, label, 0x5400_0000 | cond)
	a.a64(0x5400_0040 | (cond ^ 1))   # b.!cond past the b
	a.a64B(label)

# cbz r (cbnz when nonzero)
fn a64Cbz(mut a Asm, r i64, label i64, nonzero bool):
	if not a64Far:
		return a.a64Fixed(fxA64Cond, label, (0xB500_0000 if nonzero else 0xB400_0000) | r)
	a.a64((0xB400_0000 if nonzero else 0xB500_0000) | 2 << 5 | r)   # the opposite, past the b
	a.a64B(label)

fn a64Blr(mut a Asm, r i64):
	a.a64(0xD63F_0000 | r << 5)

fn a64Ret(mut a Asm):
	a.a64(0xD65F_03C0)

fn a64Brk(mut a Asm, imm i64):
	a.a64(0xD420_0000 | imm << 5)

fn a64Svc(mut a Asm):
	a.a64(0xD400_0001)

# d = the address of the data at offset off (the zero storage from bssBase)
fn a64AdrData(mut a Asm, d i64, off i64):
	a.a64Fixed(fxA64Page, off, 0x9000_0000 | d)
	a.a64Fixed(fxA64Low, off, 0x9100_0000 | d << 5 | d)

# d = the address of a label's code
fn a64AdrLabel(mut a Asm, d i64, label i64):
	a.a64Fixed(fxA64PageCode, label, 0x9000_0000 | d)
	a.a64Fixed(fxA64LowCode, label, 0x9100_0000 | d << 5 | d)

# fcmp n, m (doubles)
fn a64Fcmp(mut a Asm, n i64, m i64):
	a.a64(0x1E60_2000 | m << 16 | n << 5)

# the AArch64 condition of an integer comparison
fn a64CondOf(cond i64, uns bool):
	if cond == irEq: return a64Eq
	if cond == irNe: return a64Ne
	if cond == irLt: return a64Lo if uns else a64Lt
	if cond == irLe: return a64Ls if uns else a64Le
	if cond == irGt: return a64Hi if uns else a64Gt
	a64Hs if uns else a64Ge

# the condition after fcmp that a NaN never meets (but irNe, which it meets)
fn a64FloatCond(cond i64):
	if cond == irLt: return a64Mi
	if cond == irLe: return a64Ls
	a64CondOf(cond, false)

# the field of the instruction at code offset at filled with where its target is: a label's code,
# or the data (the zero storage at bssAt past the data's start)
fn a64Resolve(mut a Asm, kind i64, at i64, target i64, dataRva i64, bssAt i64):
	pc = imageBase + sectRva + at
	dest = 0
	if kind == fxTable:   # a jump table's entry: its label's distance from the table
		patch32(a.code, at, a.labelPos[a.entryLabel(target)] - a.labelPos[a.entryTable(target)])
		return
	if kind in [fxA64Page, fxA64Low, fxA64LowLoad]:
		dest = imageBase + dataRva + (bssAt + target - bssBase if target >= bssBase else target)
	else:
		if a.labelPos[target] < 0:
			exit(1, "a64: unplaced label {target}")
		dest = imageBase + sectRva + a.labelPos[target]
	word = (0..4).sum(i64(a.code[at + it]) << (8 * it))
	steps = (dest - pc) >> 2
	if kind == fxA64Jump:
		if steps.abs() >= 1 << 25: exit(1, "a64: a call out of reach")
		word |= steps & 0x3FF_FFFF
	elif kind == fxA64Cond:
		if steps.abs() >= 1 << 18: exit(1, "a64: a branch out of reach")
		word |= (steps & 0x7_FFFF) << 5
	elif kind == fxA64Page or kind == fxA64PageCode:
		pages = (dest >> 12) - (pc >> 12)
		word |= (pages & 3) << 29 | ((pages >> 2) & 0x7_FFFF) << 5
	elif kind == fxA64LowLoad:
		word |= (dest & 0xFFF) >> 3 << 10
	else:
		word |= (dest & 0xFFF) << 10
	patch32(a.code, at, word)
