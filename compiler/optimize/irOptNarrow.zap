# The optimizer's addressing, narrowing and proven checks (irOpt.zap).

# In each block, the address arithmetic of a load, store or update folded into its operand
# (x64's base + index * scale + displacement): an index i + c or i * 2^k (scale 1), a base p + c, or
# the sum p + q of two registers as base and index,
# made earlier in the block from operands not assigned since. True when one was.
fn irAddressing(mut f IrFn, facts IrFacts, visit bool[]):
	changed = false
	defs = f.irDefsFor()
	for bi, mut block in f.blocks:
		if not visit[bi]:
			defs.start += block.insts.len
			continue
		for k in 0..block.insts.len:
			op = block.insts[k].op
			if (op in [irLoad, irStore, irUpdate]) and not block.insts[k].frame and
				irAddress(block.insts, k, defs, facts.consts):
				changed = true
			defs.irNoteDef(block.insts[k].dst, k)
		defs.start += block.insts.len
	changed

# the address arithmetic folded into the address of load, store or update k (irAddressing)
fn irAddress(mut insts IrInst[], k i64, defs IrDefs, consts i64?[]):
	changed = false
	if insts[k].b >= 0 and consts[insts[k].b] is ci and
		fitsImm32(insts[k].imm + ci * insts[k].scale):
		insts[k].imm += ci * insts[k].scale   # a constant index: part of the displacement
		insts[k].b = -1
		insts[k].scale = 1
		return true
	if insts[k].b >= 0:
		d = defs.irDefIn(insts[k].b)
		if d >= 0 and defs.irFoldable(insts, d):
			x = insts[d].a
			c = (consts[insts[d].b] ?? -1) if insts[d].b >= 0 else -1
			if insts[d].size != 8:
				pass   # an operation on 32 bits wraps: no part of an address
			elif insts[d].op == irAdd and insts[d].b >= 0 and consts[insts[d].b] is add and
				fitsImm32(insts[k].imm + add * insts[k].scale):
				insts[k].b = x
				insts[k].imm += add * insts[k].scale
				changed = true
			elif insts[k].scale == 1 and
				(
					(insts[d].op == irMul and (c in [2, 4, 8])) or
						(insts[d].op == irShl and c >= 1 and c <= 3)
				):
				insts[k].b = x
				insts[k].scale = c if insts[d].op == irMul else 1 << c
				changed = true
	if insts[k].a >= 0:
		d = defs.irDefIn(insts[k].a)
		if d >= 0 and defs.irFoldable(insts, d) and insts[d].op == irAdd and insts[d].b >= 0 and
			insts[d].size == 8 and consts[insts[d].b] is add and fitsImm32(insts[k].imm + add):
			insts[k].a = insts[d].a
			insts[k].imm += add
			changed = true
	if changed: return true
	if insts[k].a >= 0 and insts[k].b < 0:
		d = defs.irDefIn(insts[k].a)
		if d >= 0 and defs.irFoldable(insts, d) and insts[d].op == irAdd and insts[d].b >= 0 and
			insts[d].size == 8 and consts[insts[d].b] == none and
			defs.at[insts[d].b] <= defs.start + d:
			# no index yet: the sum of two registers is the base and the index (the one a shift
			# or a multiply made, so the next round scales it)
			indexed = defs.irDefIn(insts[d].a)
			scaled = indexed >= 0 and (insts[indexed].op in [irShl, irMul])
			insts[k].a = insts[d].b if scaled else insts[d].a
			insts[k].b = insts[d].a if scaled else insts[d].b
			insts[k].scale = 1
			changed = true
	changed

# In each block, a wrap to a width the reader drops anyway is skipped: a store of n bytes of a
# value wrapped to n bytes or more, a wrap of a value wrapped to a width no narrower. True when
# one was.
fn irNarrowings(mut f IrFn, visit bool[]):
	changed = false
	defs = f.irDefsFor()
	for bi in 0..f.blocks.len:
		alias insts = f.blocks[bi].insts
		if not visit[bi]:
			defs.start += insts.len
			continue
		for k in 0..insts.len:
			isStore = insts[k].op == irStore and insts[k].size < 8
			if isStore or insts[k].op == irTrunc:
				d = defs.irDefIn(insts[k].c if isStore else insts[k].a)
				# a store keeps the low bytes; a wrap to fewer bits keeps fewer of what the first kept
				if d >= 0 and insts[d].op == irTrunc and defs.irFoldable(insts, d) and
					(
						(isStore and insts[d].imm >= 8 * insts[k].size) or
							(not isStore and insts[d].imm >= insts[k].imm)
					):
					if isStore:
						insts[k].c = insts[d].a
					else:
						insts[k].a = insts[d].a
					changed = true
			defs.irNoteDef(insts[k].dst, k)
		defs.start += insts.len
	changed

# An overflow check the operands' spans (irRanges.zap) prove never fails goes, and so does a
# check they prove never fails, or one that compares a value with itself for a difference, or two
# constants that pass. True when one went.
fn irProvenChecks(mut f IrFn, facts IrFacts, spans Span[]):
	changed = false
	for bi in 0..f.blocks.len:
		any = false
		for k in 0..f.blocks[bi].insts.len:
			alias inst = f.blocks[bi].insts[k]
			if inst.trap:
				if not inst.irOverflows(spans):
					inst.trap = false
					inst.size = 8   # (an i32's operands and result within 32 bits)
					changed = true
			elif inst.op == irFailIf and
				(
					inst.irCheckPasses(facts.consts) or
						inst.a >= 0 and inst.b >= 0 and
						irNeverHolds(inst.cond, inst.uns, spans[inst.a], spans[inst.b])
				):
				f.irTakeOut(bi, k)
				any = true
		if any:
			changed = true
			f.irDropTakenOut(bi)
	changed

# whether a check never fails: it compares a value with itself for a difference, or constants
# that pass
fn irCheckPasses(inst IrInst, consts i64?[]):
	if inst.a == inst.b: return inst.cond in [irNe, irLt, irGt]
	if consts[inst.a] is x and consts[inst.b] is y: return not irIntHolds(inst.cond, inst.uns, x, y)
	false

# a wrap of a value whose span already fits the width is the value itself. True when one was.
fn irWideEnough(mut f IrFn, spans Span[]):
	changed = false
	for bi in 0..f.blocks.len:
		for ii in 0..f.blocks[bi].insts.len:
			alias inst = f.blocks[bi].insts[ii]
			if inst.op == irTrunc and spans[inst.a].irSpanWithin(irWidthSpan(inst.imm, inst.uns)):
				dst = inst.dst
				a = inst.a
				line = inst.line
				col = inst.col
				f.blocks[bi].insts[ii] = IrInst(op = irCopy, dst, a, line, col)
				changed = true
	changed

# In each block, `t = a op b` then `x = t`, t read nowhere else and x neither read nor assigned
# in between: the operation writes x itself. True when one was.
fn irDirectResults(mut f IrFn, facts IrFacts):
	changed = false
	defs = f.irDefsFor()
	readAt = fill(f.classes.len, -1)   # each vreg's last read's position
	for bi in 0..f.blocks.len:
		alias insts = f.blocks[bi].insts
		any = false
		for k in 0..insts.len:
			wrap = insts[k].op == irTrunc and insts[k].imm == 32 and insts[k].uns
			if insts[k].op == irCopy or wrap:
				from = insts[k].a
				x = insts[k].dst
				j = defs.irDefIn(from)
				if from != x and facts.defs[from] == 1 and facts.reads[from] == 1 and
					f.classes[from] == f.classes[x] and j >= 0 and insts[j].op != irParam and
					not irCalls(insts[j].op) and insts[j].op != irCallOut and
					defs.at[x] <= defs.start + j and
					readAt[x] <= defs.start + j and
					(not wrap or insts[j].irNarrowable(facts.consts)):
					insts[j].dst = x
					if wrap:
						insts[j].size = 4
					f.irTakeOut(bi, k)
					defs.at[x] = defs.start + j
					any = true
					changed = true
					continue
			for v in insts[k].irReads():
				readAt[v] = defs.start + k
			defs.irNoteDef(insts[k].dst, k)
		# the positions noted are before the taken-out instructions go
		defs.start += insts.len
		if any:
			f.irDropTakenOut(bi)
	changed

# whether an operation gives the same low 32 bits as a 32-bit one, which zeroes the upper half
# (a wrap to u32 of its result is then that operation): a sum, a difference, a product, a
# negation, a not, a shift left by a constant below 32
fn irNarrowable(inst IrInst, consts i64?[]):
	if inst.trap or inst.size != 8: return false
	if inst.op == irShl:
		return inst.b >= 0 and (consts[inst.b] ?? 64) >= 0 and (consts[inst.b] ?? 64) < 32
	inst.op in [irAdd, irSub, irMul, irNeg, irNot]

# whether inst is an operation on 32 bits (irNarrowable, size 4): its result below 2^32 (an
# i32's that stops on overflow is none: its result sign-extended)
fn irIs32(inst IrInst):
	inst.size == 4 and not inst.trap and (inst.op in [irAdd, irSub, irMul, irNeg, irNot, irShl])
