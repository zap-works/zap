# Advanced SIMD three same: the integer operations on each lane of two registers, and the
# vector by element forms, which this decoder folds onto them.

# whether the three-same opcode (size and U as given) is allocated in the integer group
fn sameAllocated(opcode i64, size i64, q bool, scalar bool):
	if opcode >= 24: return false
	if scalar:
		return match opcode:
			1, 5, 9, 11: true
			6, 7, 8, 10, 16, 17: size == 3
			22: size == 1 or size == 2
			_: false
	if opcode == 3: return true
	if size == 3: return q and opcode in [1, 5, 6, 7, 8, 9, 10, 11, 16, 17, 23]
	match opcode:
		22: size == 1 or size == 2
		_: true

fn threeSame(w i64, scalar bool):
	opcode = bits(w, 11, 5)
	size = bits(w, 22, 2)
	q = bit(w, 30) and not scalar
	u = bit(w, 29)
	if not sameAllocated(opcode, size, q, scalar): return Instr()
	if opcode == 19 and u and size != 0: return Instr()
	if opcode == 23 and u: return Instr()
	pair = opcode in [20, 21, 23]
	opc = opcode
	if opcode == 20: opc = 12
	if opcode == 21: opc = 13
	if opcode == 23: opc = 16
	Instr(
		op = .Vector,
		vop = .ThreeSame,
		rd = bits(w, 0, 5),
		rn = bits(w, 5, 5),
		rm = bits(w, 16, 5),
		size,
		q,
		opc,
		unsigned = u,
		pair,
		scalar
	)
