# Advanced SIMD three different (narrow sources, wide results, or the reverse) and the vector by
# element forms, which are folded onto three same and three different.

fn threeDifferent(w i64, scalar bool):
	opcode = bits(w, 12, 4)
	size = bits(w, 22, 2)
	u = hasBit(w, 29)
	doubling = opcode in [9, 11, 13]
	allocated = match opcode:
		9, 11, 13: not u and (size == 1 or size == 2)
		14: not u and not scalar and (size == 0 or size == 3)
		15: false
		_: size != 3 and not scalar
	if scalar and not doubling: return Instr()
	if not allocated: return Instr()
	Instr(
		op = .Vector,
		vop = .ThreeDifferent,
		rd = bits(w, 0, 5),
		rn = bits(w, 5, 5),
		rm = bits(w, 16, 5),
		size,
		q = hasBit(w, 30) and not scalar,
		opc = opcode,
		unsigned = u,
		scalar
	)

# the by element opcode's three same (mla, mls, mul, sqdmulh, sqrdmulh) or three different
# opcode, its U bit in three same's meaning (mls and sqrdmulh set it), or -1 when not allocated
fn indexedOpcode(opcode i64, u bool, scalar bool):
	match opcode:
		0: (18, false) if u and not scalar else (-1, false)
		4: (18, true) if u and not scalar else (-1, false)
		8: (19, false) if not u and not scalar else (-1, false)
		2: (8, u) if not scalar else (-1, false)
		6: (10, u) if not scalar else (-1, false)
		10: (12, u) if not scalar else (-1, false)
		3: (9, false) if not u else (-1, false)
		7: (11, false) if not u else (-1, false)
		11: (13, false) if not u else (-1, false)
		12: (22, false) if not u else (-1, false)
		13: (22, true) if not u else (-1, false)
		_: (-1, false)

fn sameIndexed(w i64, scalar bool):
	if bits(w, 12, 4) in [1, 5, 9]: return floatIndexed(w, scalar)
	size = bits(w, 22, 2)
	h = bits(w, 11, 1)
	l = bits(w, 21, 1)
	m = bits(w, 20, 1)
	if size == 0 or size == 3: return Instr()
	index = h << 2 | l << 1 | m if size == 1 else h << 1 | l
	rm = bits(w, 16, 4) if size == 1 else m << 4 | bits(w, 16, 4)
	opc, u = indexedOpcode(bits(w, 12, 4), hasBit(w, 29), scalar)
	if opc < 0: return Instr()
	Instr(
		op = .Vector,
		vop = .Indexed,
		rd = bits(w, 0, 5),
		rn = bits(w, 5, 5),
		rm,
		size,
		q = hasBit(w, 30) and not scalar,
		opc,
		unsigned = u,
		index,
		scalar
	)
