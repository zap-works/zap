# Advanced SIMD shift by immediate: immh:immb give the lane size (the highest set bit of immh)
# and the shift count, which is `amount` for the right shifts and the left ones alike.

fn shiftImmediate(w i64, scalar bool):
	immh = bits(w, 19, 4)
	opcode = bits(w, 11, 5)
	u = hasBit(w, 29)
	q = hasBit(w, 30) and not scalar
	size = 3 if immh & 8 != 0 else (2 if immh & 4 != 0 else (1 if immh & 2 != 0 else 0))
	immhb = immh << 3 | bits(w, 16, 3)
	left = immhb - (8 << size)
	right = 2 * (8 << size) - immhb
	if opcode == 0x1C or opcode == 0x1F: return floatFixed(w, scalar, size, right)
	allocated = false
	if scalar:
		allocated = match opcode:
			0, 2, 4, 6, 10: size == 3
			8: size == 3 and u
			12: u
			14: true
			0x10, 0x11: u and size != 3
			0x12, 0x13: size != 3
			_: false
	else:
		allocated = match opcode:
			0, 2, 4, 6, 10, 14: size != 3 or q
			8, 12: u and (size != 3 or q)
			0x10, 0x11, 0x12, 0x13, 0x14: size != 3
			_: false
	if not allocated: return Instr()
	leftShift = opcode in [10, 12, 14, 0x14]
	Instr(
		op = .Vector,
		vop = .ShiftImmediate,
		rd = bits(w, 0, 5),
		rn = bits(w, 5, 5),
		size,
		q,
		opc = opcode,
		unsigned = u,
		amount = left if leftShift else right,
		scalar
	)
