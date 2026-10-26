# What AArch64 needs to know of a vector's bytes to run x64's byte instructions in fewer of its
# own (a64Vec.zap), stated on the instruction as uns: a vpshufb whose indices have bits 4..6 clear
# (tbl as it is, no `and` with 0x8f first), a vpblendvb whose mask's bytes are each 0 or 0xFF
# (bsl by it, no cmlt to spread its top bits). A loop's shuffle by indices the loop does not
# assign takes them cleared once before the loop (irHeldConstants).

# each shuffle and blend whose operand's bytes are known so marked
fn irKnownVecMasks(mut f IrFn):
	consts = f.irFacts().consts
	defs = f.irDefCounts()
	clear = fill(f.classes.len, false)   # a vector whose bytes have bits 4..6 clear
	full = fill(f.classes.len, false)   # a vector whose bytes are each 0 or 0xFF
	for turn in 0..2:   # the broadcasts first, then what ands them
		for blk in f.blocks:
			for inst in blk.insts:
				if inst.dst < 0 or defs[inst.dst] != 1: continue
				if turn == 0 and inst.op == irVecSplat:
					clear[inst.dst] = inst.irLaneBytesClear(consts)
				elif turn == 1 and inst.op == irVecOp and inst.cond == 0:
					full[inst.dst] = irVecCompares(inst.imm)
					if irVecCodeIs(inst.imm, 1, 0xDB) and inst.b >= 0:
						clear[inst.dst] = clear[inst.a] or clear[inst.b]
	for mut block in f.blocks:
		for k in 0..block.insts.len:
			if block.insts[k].irKnownBytes(clear, full):
				block.insts[k].uns = true

# whether inst is a shuffle by indices whose bytes are clear, or a blend by a mask whose bytes are full
fn irKnownBytes(inst IrInst, clear bool[], full bool[]):
	inst.op == irVecOp and (irVecCodeIs(inst.imm, 2, 0x00) and inst.b >= 0 and clear[inst.b] or
			inst.cond == 2 and irVecCodeIs(inst.imm, 3, 0x4C) and inst.c >= 0 and full[inst.c])

# whether a broadcast's lane is an integer constant whose bytes have bits 4..6 clear
fn irLaneBytesClear(splat IrInst, consts i64?[]):
	if splat.a < 0 or splat.a >= consts.len: return false
	width = 1 if splat.imm == irLaneU8 else 4 if splat.imm == irLaneI32
		else 8 if splat.imm == irLaneI64
		else 0
	c = consts[splat.a] ?? return false
	width > 0 and (0..width).all((c >> (8 * it)) & 0x70 == 0)

# whether code (irVecCode) is the 66-prefixed instruction of map (1 0F, 2 0F38, 3 0F3A) and opcode
fn irVecCodeIs(code i64, map i64, opcode i64):
	code & 15 == (map | 1 << 2) and (code >> 8) & 255 == opcode

# whether code is a comparison, whose lanes are all ones or all zeros
fn irVecCompares(code i64):
	op = (code >> 8) & 255
	code & 15 == 5 and op in [0x64, 0x65, 0x66, 0x74, 0x75, 0x76] or
		code & 15 == 6 and op in [0x29, 0x37] or
		code & 3 == 1 and (code >> 2) & 3 <= 1 and op == 0xC2

# whether inst is a shuffle by indices not known cleared that the loop (its assigned vregs) does not
# assign
fn irUnclearedShuffle(inst IrInst, assigned bool[]):
	inst.op == irVecOp and irVecCodeIs(inst.imm, 2, 0x00) and not inst.uns and inst.b >= 0 and
		inst.b < assigned.len and not assigned[inst.b]

# indices anded with 0x8f (bits 4..6 dropped: AArch64's tbl then reads them as vpshufb does), a
# vector of 16 << l bytes made in made: the cleared indices' vreg
fn irClearedIndices(mut f IrFn, indices i64, l i64, mut made IrInst[]):
	byte = f.irVreg(irInt)
	splat = f.irVreg(irVec)
	cleared = f.irVreg(irVec)
	made.push(IrInst(op = irConst, dst = byte, imm = 0x8F))
	made.push(IrInst(op = irVecSplat, dst = splat, a = byte, imm = irLaneU8, size = 16 << l))
	made.push(
		IrInst(
			op = irVecOp,
			dst = cleared,
			a = indices,
			b = splat,
			imm = irVecCode(1, 1, 0, l, 0xDB, -1)
		)
	)
	cleared
