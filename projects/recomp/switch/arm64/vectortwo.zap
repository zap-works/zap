# Advanced SIMD two-register miscellaneous, across lanes, and the crypto two-register groups
# (aes, sha1h, sha1su1, sha256su0), which share their encoding space.

# whether the two-register miscellaneous opcode is allocated (the FP ones are not here)
fn miscAllocated(opcode i64, size i64, u bool, q bool, scalar bool):
	if scalar:
		return match opcode:
			3, 7: true
			8, 9, 11: size == 3
			10: size == 3 and not u
			0x12: u and size != 3
			0x14: size != 3
			_: false
	wide = size != 3 or q
	match opcode:
		0: size <= 1 or (size == 2 and not u)
		1: not u and size == 0
		2, 6, 4, 0x14, 0x12: size != 3
		0x13: u and size != 3
		3, 7, 8, 9, 11: wide
		0xF: size == 2 or (size == 3 and q)
		10: wide and not u
		5: size == 0 or (u and size == 1)
		_: false

fn twoMisc(w i64, scalar bool):
	opcode = bits(w, 12, 5)
	if opcode >= 0x16 or opcode in [0xC, 0xD, 0xE]: return floatUnary(w, scalar)
	size = bits(w, 22, 2)
	u = bit(w, 29)
	q = bit(w, 30) and not scalar
	if not miscAllocated(opcode, size, u, q, scalar): return Instr()
	Instr(
		op = .Vector,
		vop = .TwoMisc,
		rd = bits(w, 0, 5),
		rn = bits(w, 5, 5),
		size,
		q,
		opc = opcode,
		unsigned = u,
		scalar
	)

# across lanes (saddlv, smaxv, sminv, addv) or scalar pairwise (addp): addp of two 64-bit lanes
# is addv's opcode with the size addv lacks
fn acrossLanes(w i64, scalar bool):
	opcode = bits(w, 12, 5)
	if opcode in [0xC, 0xD, 0xF]: return floatAcross(w, scalar)
	size = bits(w, 22, 2)
	u = bit(w, 29)
	q = bit(w, 30) and not scalar
	ok = false
	if scalar:
		ok = opcode == 0x1B and size == 3 and not u
		q = true
	else:
		ok = (opcode in [3, 0xA, 0x1A] or (opcode == 0x1B and not u)) and size != 3 and
			(size != 2 or q)
	if not ok: return Instr()
	Instr(
		op = .Vector,
		vop = .AcrossLanes,
		rd = bits(w, 0, 5),
		rn = bits(w, 5, 5),
		size,
		q,
		opc = opcode,
		unsigned = u,
		scalar
	)

fn cryptoTwo(w i64, scalar bool):
	opcode = bits(w, 12, 5)
	if bits(w, 22, 2) != 0 or bit(w, 29): return Instr()
	if scalar:
		if opcode > 2: return Instr()
		return Instr(
			op = .Vector,
			vop = .ShaTwo,
			rd = bits(w, 0, 5),
			rn = bits(w, 5, 5),
			opc = opcode
		)
	if opcode < 4 or opcode > 7 or not bit(w, 30): return Instr()
	Instr(op = .Vector, vop = .Aes, rd = bits(w, 0, 5), rn = bits(w, 5, 5), opc = opcode)

fn twoRegister(w i64, scalar bool):
	match bits(w, 17, 5):
		0b1_0000: twoMisc(w, scalar)
		0b1_1000: acrossLanes(w, scalar)
		0b1_0100: cryptoTwo(w, scalar)
		_: Instr()
