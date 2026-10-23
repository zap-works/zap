# A64's loads and stores of vector structures (Arm ARM C4.1.4): ld1-ld4 and st1-st4 of multiple
# structures or of one lane, and ld1r-ld4r, with their post-index forms. Decoded as
# Op.VectorStructure: opc 0 a store, 1 a load, 2 a load replicated to every lane; size the
# element's bytes as their log2; amount the registers of a structure (selem); imm2 how many
# times a run of registers repeats (rpt); index the lane of a one-lane access, -1 for all; rm
# the post-index register, zr for the size of what moved, and mode PostIndex.

# a multiple-structure opcode's (rpt, selem), none for a reserved one
fn multiple(opcode i64) (i64, i64)?:
	match opcode:
		0b0000: (1, 4)
		0b0010: (4, 1)
		0b0100: (1, 3)
		0b0110: (3, 1)
		0b0111: (1, 1)
		0b1000: (1, 2)
		0b1010: (2, 1)
		_: none

# The structure access w (its rt and rn read), Op.Unknown when it is none the decoder knows.
fn vectorStructure(w i64, rt i64, rn i64):
	if bit(w, 31) or bits(w, 25, 2) != 0b10: return Instr()
	load = bit(w, 22)
	post = bit(w, 23)
	if not post and bits(w, 16, 5) != 0: return Instr()
	mode = Mode.PostIndex if post else Mode.Offset
	q = bit(w, 30)
	size = bits(w, 10, 2)
	opcode = bits(w, 12, 4)
	if not bit(w, 24):
		if bit(w, 21): return Instr()
		rpt, selem = multiple(opcode) ?? return Instr()
		if size == 3 and not q and selem > 1: return Instr()
		return Instr(
			op = .VectorStructure,
			rd = rt,
			rn,
			rm = bits(w, 16, 5),
			opc = 1 if load else 0,
			size,
			amount = selem,
			imm2 = rpt,
			index = -1,
			q,
			mode
		)
	selem = (bits(w, 13, 1) << 1 | bits(w, 21, 1)) + 1
	s = bits(w, 12, 1)
	kind = bits(w, 14, 2)
	if kind == 3:
		if not load or s == 1: return Instr()
		return Instr(
			op = .VectorStructure,
			rd = rt,
			rn,
			rm = bits(w, 16, 5),
			opc = 2,
			size,
			amount = selem,
			imm2 = 1,
			index = -1,
			q,
			mode
		)
	qs = bits(w, 30, 1) << 1 | s
	esize = kind
	index = 0
	match kind:
		0: index = qs << 2 | size
		1:
			if size & 1 != 0: return Instr()
			index = qs << 1 | size >> 1
		_:
			if size == 0: index = qs
			elif size == 1 and s == 0:
				esize = 3
				index = qs >> 1
			else: return Instr()
	Instr(
		op = .VectorStructure,
		rd = rt,
		rn,
		rm = bits(w, 16, 5),
		opc = 1 if load else 0,
		size = esize,
		amount = selem,
		imm2 = 1,
		index,
		q,
		mode
	)
