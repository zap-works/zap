# The cryptographic extension's three-register SHA group (the two-register ones share
# vectortwo.zap's encoding space).

fn shaThree(w i64):
	opcode = bits(w, 12, 3)
	if opcode == 7: return Instr()
	Instr(
		op = .Vector,
		vop = .ShaThree,
		rd = bits(w, 0, 5),
		rn = bits(w, 5, 5),
		rm = bits(w, 16, 5),
		opc = opcode
	)
