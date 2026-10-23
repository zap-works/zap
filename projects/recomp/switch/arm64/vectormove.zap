# Advanced SIMD copy (dup, ins, smov, umov), modified immediate, extract, table lookup and
# permute: the groups that move lanes and constants rather than compute.

# opc of an element insert, which has no imm4 of its own
elementInsert = 16

# the lane size (log2 of its bytes) imm5 selects by its lowest set bit, -1 when none
fn copySize(imm5 i64):
	if imm5 & 15 == 0: return -1
	u64(imm5).trailingZeros()

fn elementCopy(w i64, scalar bool):
	imm5 = bits(w, 16, 5)
	imm4 = bits(w, 11, 4)
	size = copySize(imm5)
	q = bit(w, 30) and not scalar
	insert = bit(w, 29)
	if size < 0 or (scalar and (insert or imm4 != 0)): return Instr()
	allocated = false
	if insert:
		allocated = q
	else:
		allocated = match imm4:
			0: size < 3 or q or scalar
			1: size < 3 or q
			3: q
			5: size < 2 or (size == 2 and q)
			7: size == 3 if q else size < 3
			_: false
	if not allocated: return Instr()
	Instr(
		op = .Vector,
		vop = .Copy,
		rd = bits(w, 0, 5),
		rn = bits(w, 5, 5),
		size,
		q,
		opc = elementInsert if insert else imm4,
		index = imm5 >> (size + 1),
		imm = imm4 >> size,
		scalar
	)

# the 64 bits a modified immediate expands to, its operation not applied
fn expandedImmediate(cmode i64, op bool, imm8 i64):
	b = u64(imm8)
	match cmode >> 1:
		0, 1, 2, 3: (b << (8 * (cmode >> 1))) * 0x1_0000_0001
		4, 5: (b << (8 * ((cmode >> 1) & 1))) * 0x0001_0001_0001_0001
		6: ((b << 8 | 0xFF) if cmode & 1 == 0 else (b << 16 | 0xFFFF)) * 0x1_0000_0001
		_:
			if cmode == 15: return b   # fmov's: cpu/vectormove.zap expands it (amount 1)
			if not op: return b * 0x0101_0101_0101_0101
			bytes = u64(0)
			for k in 0..8:
				if (b >> k) & 1 != 0: bytes |= u64(0xFF) << (8 * k)
			bytes

fn modifiedImmediate(w i64):
	cmode = bits(w, 12, 4)
	op = bit(w, 29)
	if bit(w, 11) or (cmode == 15 and op and not bit(w, 30)): return Instr()
	imm = expandedImmediate(cmode, op, bits(w, 16, 3) << 5 | bits(w, 5, 5))
	# orr and bic only exist for the shifted forms, odd cmode below 12
	logic = cmode < 12 and cmode & 1 == 1
	opc = 0
	if logic: opc = 3 if op else 2
	Instr(
		op = .Vector,
		vop = .ModifiedImmediate,
		rd = bits(w, 0, 5),
		imm = i64(~imm if op and cmode < 14 else imm),
		amount = 1 if cmode == 15 else 0,
		sf = op or cmode != 15,
		q = bit(w, 30),
		opc
	)

fn extract(w i64):
	if not bit(w, 30) and bit(w, 14): return Instr()
	Instr(
		op = .Vector,
		vop = .Extract,
		rd = bits(w, 0, 5),
		rn = bits(w, 5, 5),
		rm = bits(w, 16, 5),
		q = bit(w, 30),
		imm = bits(w, 11, 4)
	)

fn table(w i64):
	Instr(
		op = .Vector,
		vop = .Table,
		rd = bits(w, 0, 5),
		rn = bits(w, 5, 5),
		rm = bits(w, 16, 5),
		q = bit(w, 30),
		imm = bits(w, 13, 2) + 1,
		opc = bits(w, 12, 1)
	)

fn permute(w i64):
	opcode = bits(w, 12, 3)
	size = bits(w, 22, 2)
	q = bit(w, 30)
	if opcode & 3 == 0 or (size == 3 and not q): return Instr()
	Instr(
		op = .Vector,
		vop = .Permute,
		rd = bits(w, 0, 5),
		rn = bits(w, 5, 5),
		rm = bits(w, 16, 5),
		size,
		q,
		opc = opcode
	)
