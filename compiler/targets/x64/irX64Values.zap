# The emission of copies, arithmetic, calls, branches, switches and memory accesses (irX64.zap).

# a copy, or a parameter read on entry (from its register, or its stack slot above the return
# address)
fn irEmitCopy(mut g Gen, em IrEmit, inst IrInst):
	float = em.f.classes[inst.dst] == irFloat
	if inst.op == irParam:
		if inst.regArgs: die("x64: a parameter in a register apart from the others (irParamsIn)")
		# above the return address (rbp saw it at 16 up)
		if em.slots[inst.dst] == 16 + 8 * inst.imm: return   # spilled where it arrived
		base = 4
		disp = g.irDisp(16 + 8 * inst.imm)
		if float:
			x = em.irFloatOut(inst.dst)
			if inst.size == 4:
				g.irVexRM(2, 0, 0x10, x, 0, base, -1, 1, disp)   # vmovss: the slot holds the f32 itself
				g.irVexRR(2, 0, 0x5A, x, x, x)
			else:
				g.irVexRM(3, 0, 0x10, x, 0, base, -1, 1, disp)
			g.irFloatDone(em, inst.dst, x)
		else:
			r = em.irIntOut(inst.dst)
			g.a.memOp(true, 0x8B, -1, r, base, -1, disp)
			g.irIntDone(em, inst.dst, r)
		return
	if em.irCopyInPlace(inst): return
	if float:
		x = em.irFloatOut(inst.dst)
		g.irFloatDone(em, inst.dst, g.irFloatIn(em, inst.a, x))
	else:
		r = em.irIntOut(inst.dst)
		g.irIntDone(em, inst.dst, g.irIntIn(em, inst.a, r))

# dst = a op b on integers: two operands, so a goes into dst's register first (through rax when
# that register holds b and op is not commutative)
fn irEmitAlu(mut g Gen, em IrEmit, inst IrInst):
	op = inst.op
	if op == irMul and g.irMulByImm(em, inst) or op == irAdd and g.irAddByLea(em, inst): return
	g.irEmitAluOp(em, inst)

# dst = a op b by the operation's own instruction (no lea), which sets the flags
fn irEmitAluOp(mut g Gen, em IrEmit, inst IrInst):
	op = inst.op
	commutes = op != irSub
	r = em.irIntOut(inst.dst)
	a = inst.a
	b = inst.b
	if not em.rs.spilled[b] and not em.rs.isConst[b] and em.rs.reg[b] == r and a != b:
		if commutes:
			a = inst.b
			b = inst.a
		else:
			r = 0
	g.irMov(r, g.irIntIn(em, a, r))
	wide = inst.size != 4   # an operation on 32 bits zeroes the upper half
	if op == irMul:
		c = em.rs.constVal[b] if em.rs.isConst[b] else 0
		if c in [3, 5, 9] and not inst.trap and wide:
			# r * 3, 5, 9: lea r, [r + r * 2, 4, 8]
			g.irModLea(r, r, r, c - 1)
		elif em.rs.spilled[b]:
			g.a.memOp(wide, 0x0F, 0xAF, r, 4, -1, g.irSlot(em, b))
		else:
			g.regOp(wide, 0x0F, 0xAF, r, g.irIntIn(em, b, 1))
	else:
		opRR, digit = (0x01, 0) if op == irAdd
			else (0x29, 5) if op == irSub
			else (0x21, 4) if op == irAnd
			else (0x09, 1) if op == irOr
			else (0x31, 6)
		g.irAluOperand(em, opRR, opRR + 2, digit, r, b, wide)
	g.irOverflowJump(inst)
	g.irSignExtended(inst, r)
	g.irIntDone(em, inst.dst, r)

# A sum's carry or a difference's borrow tested right after it: s = x + y then s < x (or s < y),
# d = x - y then x < y, is the add's or the sub's carry flag (setb, no compare); when the test's
# one reader adds it next, h + carry is one adc. The instructions taken, none for another shape.
fn irCarryOf(mut g Gen, em IrEmit, insts IrInst[], ii i64) i64?:
	if ii + 1 >= insts.len: return none
	op = insts[ii]
	test = insts[ii + 1]
	if not op.irCarryTest(test) or em.rs.isConst[op.dst] or em.rs.isConst[test.dst]: return none
	g.irEmitAluOp(em, op)
	if ii + 2 < insts.len and em.reads[test.dst] == 1:
		use = insts[ii + 2]
		if use.op == irAdd and not use.trap and use.size == 8 and use.dst >= 0 and
			(use.a == test.dst) != (use.b == test.dst):
			r = em.irIntOut(use.dst)
			g.irMov(r, g.irIntIn(em, use.b if use.a == test.dst else use.a, r))   # movs keep the flags
			g.regOp(true, 0x83, -1, 2, r)   # adc r, 0
			g.a.em1(0)
			g.irIntDone(em, use.dst, r)
			return 3
	g.a.em3(0x0F, 0x92, 0xC0)   # setb al
	r = em.irIntOut(test.dst)
	g.regOp(true, 0x0F, 0xB6, r, 0)   # movzx r, al
	g.irIntDone(em, test.dst, r)
	2

# A product's low word added to a word (or taken from one) and the carry (the borrow) added to
# its high word, both words read there alone, as a limb of a multiword product is: mul, then add
# (sub) and adc on rax and rdx, with no copy between. The instructions taken, none for another
# shape.
fn irMulCarry(mut g Gen, em IrEmit, insts IrInst[], ii i64, loadAt i64) i64?:
	if ii + 4 >= insts.len or not insts[ii].irMulPair(insts[ii + 1]): return none
	high = insts[ii] if insts[ii].op == irMulHigh else insts[ii + 1]
	low = insts[ii + 1].dst if insts[ii].op == irMulHigh else insts[ii].dst
	sum = insts[ii + 2]
	test = insts[ii + 3]
	use = insts[ii + 4]
	lowReads = [sum.a, sum.b, test.a, test.b].filter(it == low).len   # the test's are the flag's
	if not sum.irCarryTest(test) or em.reads[low] != lowReads or em.reads[high.dst] != 1 or
		em.reads[test.dst] != 1 or sum.b != low and (sum.op == irSub or sum.a != low) or
		use.op != irAdd or use.trap or use.size != 8 or use.dst < 0 or
		not (use.a == test.dst and use.b == high.dst or use.b == test.dst and use.a == high.dst) or
		em.rs.isConst[sum.dst]:
		return none
	if loadAt >= 0 and not em.irMulOfLoad(insts, loadAt, ii, high): return none
	other = sum.a if sum.b == low else sum.b
	if loadAt >= 0:
		# the factor read from memory into rax, the loads between it and the product, and the
		# other factor's mul
		g.irLoadInto(em, insts[loadAt], 0)
		for j in loadAt + 1..ii:
			g.irEmitMemory(em, insts[j])
		factor = high.b if insts[loadAt].dst == high.a else high.a
		g.regOp(true, 0xF7, -1, 4, g.irIntIn(em, factor, 1))   # mul
	else:
		g.irMov(0, g.irIntIn(em, high.a, 0))
		g.regOp(true, 0xF7, -1, 4, g.irIntIn(em, high.b, 1))   # mul
	r = 0
	if sum.op == irAdd:
		g.irAluOperand(em, 0x01, 0x03, 0, 0, other)   # add rax, other
	else:
		r = 1
		if em.irDiesInto(insts, ii, other):
			r = em.rs.reg[other]   # taken from where it is: nothing reads it after
		else:
			g.irMov(1, g.irIntIn(em, other, 1))
		g.regOp(true, 0x29, -1, 0, r)   # sub r, rax
	g.regOp(true, 0x83, -1, 2, 2)   # adc rdx, 0
	g.a.em1(0)
	s = sum.dst
	h = use.dst
	k = ii + 5
	while g.irCarryOnto(em, insts, k, s, h, r):
		s = insts[k].dst
		h = insts[k + 2].dst
		k += 3
	if k < insts.len and
		g.irStoreFrom(em, insts[k], s, r, [insts[k - 2].a, insts[k - 2].b].filter(it == s).len):
		k += 1
	else:
		g.irIntDone(em, s, r)
	g.irIntDone(em, h, 2)
	k - (loadAt if loadAt >= 0 else ii)

# whether the word v, held in a register, was computed a few instructions before the pattern of
# five at ii and is read by those and the ones between alone: nothing reads it after, so its
# register can take a result
fn irDiesInto(em IrEmit, insts IrInst[], ii i64, v i64):
	if not em.irInReg(v) or em.rs.reg[v] < 3: return false
	j = ii - 1
	while j >= (ii - 16).max(0) and insts[j].dst != v:
		j -= 1
	if j < (ii - 16).max(0): return false
	readers = 0
	for k in j + 1..(ii + 5).min(insts.len):
		if insts[k].irReadsVreg(v): readers += 1
	readers == em.reads[v]

# whether the load at insts[at] (of an 8-byte word read by the product's two halves at ii alone,
# the other factor another word) can be read into rax as the product's first factor: only loads
# of words that stay in registers, from addresses held in registers, come between
fn irMulOfLoad(em IrEmit, insts IrInst[], at i64, ii i64, high IrInst):
	load = insts[at]
	if not (load.op == irLoad and load.dst >= 0 and load.size == 8 and
			em.f.classes[load.dst] == irInt and em.reads[load.dst] == 2 and
			(load.dst == high.a) != (load.dst == high.b)):
		return false
	for j in at + 1..ii:
		between = insts[j]
		if between.op != irLoad or between.dst < 0 or em.f.classes[between.dst] != irInt or
			not em.irInReg(between.dst) or between.frame or between.a < 0 or
			not em.irInReg(between.a) or between.b >= 0 and not em.irInReg(between.b):
			return false
	true

# r = the 8-byte word load reads, in register r
fn irLoadInto(mut g Gen, em IrEmit, load IrInst, r i64):
	at, base, index = g.irMemoryAt(em, load)
	g.irMemOperand(true, 0x8B, -1, r, base, index, at.scale, at.imm)

# the store of the word s, held in register r and read nowhere else but by the carry test (read
# `tested` times), written from r when the instruction is that store to an address in registers
# (no scratch of its own)
fn irStoreFrom(mut g Gen, em IrEmit, store IrInst, s i64, r i64, tested i64):
	if store.op != irStore or store.c != s or store.size != 8 or em.reads[s] != tested + 1 or
		em.f.classes[s] != irInt or em.rs.isConst[s] or store.frame or store.a < 0 or
		not em.irInReg(store.a) or em.rs.isFrame[store.a] or em.rs.isData[store.a] or
		store.b >= 0 and not em.irInReg(store.b):
		return false
	at, base, index = g.irMemoryAt(em, store)
	g.irMemOperand(true, 0x89, -1, r, base, index, at.scale, at.imm)
	true

# whether insts from k go on from the word s in register r and the high word h in rdx: s plus a
# word (or less one), its carry tested and added to h, s and h read nowhere else; emitted if so
# (add or sub, then adc rdx, 0)
fn irCarryOnto(mut g Gen, em IrEmit, insts IrInst[], k i64, s i64, h i64, r i64):
	if k + 2 >= insts.len: return false
	next = insts[k]
	test = insts[k + 1]
	use = insts[k + 2]
	other = next.b if next.a == s else next.a
	last = insts[k - 2]   # the test of the link before, which reads s as the sum's carry test does
	sReads = [next.a, next.b, test.a, test.b, last.a, last.b].filter(it == s).len
	if not next.irCarryTest(test) or em.reads[s] != sReads or em.reads[h] != 1 or
		em.reads[test.dst] != 1 or next.a != s and (next.op == irSub or next.b != s) or
		other == s or use.op != irAdd or use.trap or use.size != 8 or use.dst < 0 or
		not (use.a == test.dst and use.b == h or use.b == test.dst and use.a == h) or
		em.rs.isConst[next.dst] or r == 1 and (em.rs.isFrame[other] or em.rs.isData[other]):
		return false
	add = next.op == irAdd
	g.irAluOperand(em, 0x01 if add else 0x29, 0x03 if add else 0x2B, 0 if add else 5, r, other)
	g.regOp(true, 0x83, -1, 2, 2)   # adc rdx, 0
	g.a.em1(0)
	true

# whether test is op's carry: an unsigned s < x after s = x + y (either operand, s not one), or
# x < y after d = x - y, 64 bits wrapping
fn irCarryTest(op IrInst, test IrInst):
	if op.trap or op.size != 8 or op.dst < 0 or op.dst == op.a or op.dst == op.b: return false
	if test.op != irSet or not test.uns or test.dst < 0 or test.dst == op.a or test.dst == op.b:
		return false
	s = op.dst
	if op.op == irAdd:
		return test.cond == irLt and test.a == s and (test.b == op.a or test.b == op.b) or
			test.cond == irGt and test.b == s and (test.a == op.a or test.a == op.b)
	op.op == irSub and
		(test.cond == irLt and test.a == op.a and test.b == op.b or
				test.cond == irGt and test.a == op.b and test.b == op.a)

# dst = a * a constant that fits 32 bits, in three operands (imul r, a, imm): false for another
# (a 3, 5 or 9 is a lea)
fn irMulByImm(mut g Gen, em IrEmit, inst IrInst):
	wide = inst.size != 4
	if not em.rs.isConst[inst.b]: return false
	c = em.rs.constVal[inst.b]
	if c in [3, 5, 9] and not inst.trap and wide or wide and not fitsImm32(c): return false
	r = em.irIntOut(inst.dst)
	g.regOp(wide, 0x69, -1, r, g.irIntIn(em, inst.a, r))
	g.a.emit32(c if wide else irLow32(c))
	g.irOverflowJump(inst)
	g.irSignExtended(inst, r)
	g.irIntDone(em, inst.dst, r)
	true

# dst = a + a constant that fits 32 bits, a in another register: one lea (no overflow check)
fn irAddByLea(mut g Gen, em IrEmit, inst IrInst):
	a = inst.a
	if inst.trap or not em.rs.isConst[inst.b] or not fitsImm32(em.rs.constVal[inst.b]) or
		em.rs.spilled[a] or em.rs.isConst[a] or em.rs.isFrame[a] or em.rs.isData[a] or
		em.rs.reg[a] < 0 or em.rs.reg[a] == em.irIntOut(inst.dst):
		return false
	r = em.irIntOut(inst.dst)
	g.a.memOp(inst.size != 4, 0x8D, -1, r, em.rs.reg[a], -1, em.rs.constVal[inst.b])
	g.irIntDone(em, inst.dst, r)
	true

# after an operation that stops the program when it overflows: jo to the stub
fn irOverflowJump(mut g Gen, inst IrInst):
	if inst.trap: g.failJump(0x80, g.failOverflow)

# an i32's operation that stops on overflow (32 bits, which zero the upper half): its result in
# r sign-extended, as an i32 is held
fn irSignExtended(mut g Gen, inst IrInst, r i64):
	if inst.trap and inst.size == 4:
		g.regOp(true, 0x63, -1, r, r)   # movsxd r, r32

# a shift by a constant, or (BMI2: shlx, shrx, sarx) by a register, three operands
fn irEmitShift(mut g Gen, em IrEmit, inst IrInst):
	r = em.irIntOut(inst.dst)
	if em.rs.isConst[inst.b]:
		g.irMov(r, g.irIntIn(em, inst.a, r))
		g.regOp(inst.size != 4, 0xC1, -1, 4 if inst.op == irShl else 5 if inst.uns else 7, r)
		g.a.em1(em.rs.constVal[inst.b] & 63)
	else:
		count = g.irIntIn(em, inst.b, 1)
		src = g.irIntIn(em, inst.a, 2)
		g.irVexMap(2, 1 if inst.op == irShl else 3 if inst.uns else 2, 1, r, count, -1, src)
		g.a.em2(0xF7, 0xC0 | (r & 7) << 3 | (src & 7))
	g.irIntDone(em, inst.dst, r)

# a division by a constant: a multiplication by its magic number (no check, no divide
# instruction); false when the constant is not one it takes (the remainder multiplies back by
# a 32-bit immediate)
fn irDivByConstant(mut g Gen, em IrEmit, inst IrInst, v i64):
	op = binDiv if inst.op == irDiv else binMod
	if v > 2_147_483_647 or v < -2_147_483_648: return false
	if (v < 2 if inst.uns else v == 0 or v == -1): return false
	if inst.uns and inst.imm <= 32 and (v & (v - 1)) != 0 and g.irDivByMagicU32(em, inst, v):
		return true
	g.irMov(0, g.irIntIn(em, inst.a, 0))
	if inst.uns:
		g.genUnsignedDivBy(op, v)
	else:
		g.genSignedDivBy(op, v, 32 if inst.imm == 32 else 64)
	g.irIntDone(em, inst.dst, 0)
	true

# an unsigned division of 32 bits or fewer by a constant, in the registers the operands have:
# x * M >> p (magicU32), a remainder x minus that times v (rcx between); false when M is not an
# immediate
fn irDivByMagicU32(mut g Gen, em IrEmit, inst IrInst, v i64):
	m, p = magicU32(v)
	if m == 0: return false
	x = g.irIntIn(em, inst.a, 0)
	r = em.irIntOut(inst.dst)
	q = r if inst.op == irDiv else 1
	g.regOp(true, 0x69, -1, q, x)   # imul q, x, M
	g.a.emit32(m)
	g.regOp(true, 0xC1, -1, 5, q)   # shr q, p
	g.a.em1(p)
	if inst.op == irRem:
		g.regOp(true, 0x69, -1, 1, 1)   # imul rcx, rcx, v
		g.a.emit32(v)
		g.irMov(r, x)
		g.regOp(true, 0x29, -1, 1, r)   # sub r, rcx
	g.irIntDone(em, inst.dst, r)
	true

# whether a and b divide the same operands, one for the quotient and one for the remainder (one
# division gives both), the first's result not one of them
fn irDivPair(a IrInst, b IrInst):
	((a.op == irDiv and b.op == irRem) or (a.op == irRem and b.op == irDiv)) and a.a == b.a and
		a.b == b.b and a.uns == b.uns and a.dst != a.a and a.dst != a.b

# whether a and b multiply the same operands, one for the high word and one for the low (one mul
# gives both), the first's result not an operand of the second
fn irMulPair(a IrInst, b IrInst):
	low = a if a.op == irMul else b
	(a.op == irMul and b.op == irMulHigh or a.op == irMulHigh and b.op == irMul) and
		not low.trap and low.size == 8 and
		(a.a == b.a and a.b == b.b or a.a == b.b and a.b == b.a) and a.dst != b.a and a.dst != b.b

# the product of insts[at] and insts[at + 1] (irMulPair) whose first factor is the load at insts[from]
# (irMulOfLoad): the load into rax, the loads between, then the mul
fn irEmitMulHighLoaded(mut g Gen, em IrEmit, insts IrInst[], from i64, at i64):
	high = insts[at] if insts[at].op == irMulHigh else insts[at + 1]
	low = insts[at + 1].dst if insts[at].op == irMulHigh else insts[at].dst
	g.irLoadInto(em, insts[from], 0)
	for j in from + 1..at:
		g.irEmitMemory(em, insts[j])
	factor = high.b if insts[from].dst == high.a else high.a
	g.regOp(true, 0xF7, -1, 4, g.irIntIn(em, factor, 1))   # mul
	g.irIntDone(em, low, 0)
	g.irIntDone(em, high.dst, 2)

# the high word of a * b (mul: rax a, the product in rdx:rax); low the vreg that takes the low word
# (-1: none)
fn irEmitMulHigh(mut g Gen, em IrEmit, inst IrInst, low i64):
	g.irMov(0, g.irIntIn(em, inst.a, 0))
	g.regOp(true, 0xF7, -1, 4, g.irIntIn(em, inst.b, 1))   # mul b
	if low >= 0:
		g.irIntDone(em, low, 0)
	g.irIntDone(em, inst.dst, 2)

# rax / rcx, the divisor checked for 0: by a 32-bit division when both are below 2^31, else a
# signed divisor of -1 negates (the quotient of the smallest number stops the program, the
# remainder is 0) instead of trapping. other: the vreg that takes the other result (-1: none).
fn irEmitDivide(mut g Gen, em IrEmit, inst IrInst, other i64):
	if em.rs.isConst[inst.b] and g.irDivByConstant(em, inst, em.rs.constVal[inst.b]): return
	g.irMov(1, g.irIntIn(em, inst.b, 1))
	g.irMov(0, g.irIntIn(em, inst.a, 0))
	g.regOp(true, 0x85, -1, 1, 1)   # test rcx, rcx
	g.failJump(0x84, g.failDivZero)
	done = g.a.asmNewLabel()
	if not inst.uns and inst.imm <= 32:
		g.irEmitDivide32(inst, done, other)
	else:
		g.irEmitDivideWide(inst, done)
	g.a.asmPlace(done)
	# rax the quotient, rdx the remainder
	quotient = inst.dst if inst.op == irDiv else other
	remainder = inst.dst if inst.op == irRem else other
	if remainder >= 0:
		g.irIntDone(em, remainder, 2)
	if quotient >= 0:
		g.irIntDone(em, quotient, 0)

# a division of signed numbers of 32 bits at most (sign-extended words): one idiv of 32 bits, as
# fast as an unsigned one and no test of the signs, the divisor -1 apart (the one it traps on),
# out of line after the function's blocks (irEmitMinusOnes)
fn irEmitDivide32(mut g Gen, inst IrInst, done i64, other i64):
	minus1 = g.a.asmNewLabel()
	g.a.em3(0x83, 0xF9, 0xFF)   # cmp ecx, -1
	g.a.jccLabel(0x84, minus1)
	g.a.em1(0x99)   # cdq
	g.a.em2(0xF7, 0xF9)   # idiv ecx
	if inst.op == irDiv or other >= 0:
		g.a.em3(0x48, 0x63, 0xC0)   # movsxd rax, eax
	if inst.op == irRem or other >= 0:
		g.a.em3(0x48, 0x63, 0xD2)   # movsxd rdx, edx
	g.f.minusOnes.push(minus1)
	g.f.minusOnes.push(done)

# each narrow division's divisor -1: the quotient negated (one past 32 bits is left to the
# narrowing after the division), the remainder 0, back after the division; nothing here fails
fn irEmitMinusOnes(mut g Gen):
	for k in 0..g.f.minusOnes.len / 2:
		g.a.asmPlace(g.f.minusOnes[2 * k])
		g.regOp(true, 0xF7, -1, 3, 0)   # neg rax
		g.a.em2(0x31, 0xD2)   # xor edx, edx
		g.a.jmpLabel(g.f.minusOnes[2 * k + 1])
	g.f.minusOnes.clear()

# a division of 64-bit words: of 32 bits when both are below 2^31, else of 64
fn irEmitDivideWide(mut g Gen, inst IrInst, done i64):
	wide = g.a.asmNewLabel()
	g.a.em3(0x48, 0x89, 0xC2)   # mov rdx, rax
	g.a.em3(0x48, 0x09, 0xCA)   # or rdx, rcx
	g.a.em4(0x48, 0xC1, 0xEA, 0x1F)   # shr rdx, 31
	g.a.jccLabel(0x85, wide)
	g.a.em2(0x31, 0xD2)   # xor edx, edx
	g.a.em2(0xF7, 0xF1)   # div ecx
	g.a.jmpLabel(done)
	g.a.asmPlace(wide)
	if inst.uns:
		g.a.em2(0x31, 0xD2)   # xor edx, edx
		g.regOp(true, 0xF7, -1, 6, 1)   # div rcx
	else:
		notMinus1 = g.a.asmNewLabel()
		g.a.em4(0x48, 0x83, 0xF9, 0xFF)   # cmp rcx, -1
		g.a.jccLabel(0x85, notMinus1)
		g.regOp(true, 0xF7, -1, 3, 0)   # neg rax
		if inst.op == irDiv: g.failJump(0x80, g.failOverflow)
		g.a.em2(0x31, 0xD2)   # xor edx, edx
		g.a.jmpLabel(done)
		g.a.asmPlace(notMinus1)
		g.a.em2(0x48, 0x99)   # cqo
		g.regOp(true, 0xF7, -1, 7, 1)   # idiv rcx

fn irEmitSet(mut g Gen, em IrEmit, inst IrInst):
	if em.f.classes[inst.a] == irFloat:
		g.irCompareFloat(em, inst.cond, inst.a, inst.b)
		g.a.em3(0x0F, irFloatJcc(inst.cond) + 0x10, 0xC0)   # setcc al
		if inst.cond == irEq or inst.cond == irNe:
			# equal also needs ordered (no NaN): sete and setnp; not equal: setne or setp
			g.a.em3(0x0F, 0x9B if inst.cond == irEq else 0x9A, 0xC1)
			g.a.em2(0x20 if inst.cond == irEq else 0x08, 0xC8)   # and/or al, cl
	else:
		cc = g.irCompareIntFor(em, inst.a, inst.b, inst.cond)
		g.a.em3(0x0F, irJcc(cc, inst.uns) + 0x10, 0xC0)
	r = em.irIntOut(inst.dst)
	g.regOp(true, 0x0F, 0xB6, r, 0)   # movzx r, al
	g.irIntDone(em, inst.dst, r)

# dst = a op b: vaddsd and its kind, a in a register, b anywhere; an operand that a load (read
# nowhere else) gives read from the load's memory (irFoldedUse)
fn irEmitFloatArith(mut g Gen, em IrEmit, inst IrInst, load IrInst?):
	op = inst.op
	vop = 0x58 if op == irFAdd else 0x5C if op == irFSub else 0x59 if op == irFMul else 0x5E
	x = em.irFloatOut(inst.dst)
	if load is from:
		at, base, index = g.irMemoryAt(em, from)
		other = g.irFloatIn(em, inst.b if inst.a == from.dst else inst.a, 0)
		g.irVexRM(3, 0, vop, x, other, base, index, at.scale, at.imm)
	else:
		g.irVexOperand(em, 3, vop, x, g.irFloatIn(em, inst.a, 0), inst.b)
	g.irFloatDone(em, inst.dst, x)

# A call: each word in the area at [rsp] as if pushed in order (a closure's environment first,
# then the arguments on the stack, then where the result goes: the last nearest the return
# address), then those of the register convention in theirs (irX64RegArgs.zap); the result in
# rax, or a small aggregate's leaves (the call's dst and outs', irCallOut) in rax, rdx and
# xmm0..xmm3.
fn irEmitCall(mut g Gen, em IrEmit, inst IrInst, outs IrInst[] = []):
	n = em.f.irArgWords(inst)
	k = 0
	if inst.op == irCallPtr:
		f = g.irIntIn(em, inst.a, 0)
		g.a.memOp(true, 0x8B, -1, 0, f, -1, 8)   # mov rax, [f+8]: the environment
		g.argWord(0, 0, n)
		k = 1
	for v in em.f.irCallArgs(inst, true):
		g.irArgWord(em, v, k, n)
		k += 1
	if inst.c >= 0:
		g.irArgWord(em, inst.c, k, n)
	if inst.regArgs:
		g.irRegArgsIn(em, em.f.irCallArgs(inst, false))

	if inst.op == irCallPtr:
		f = g.irIntIn(em, inst.a, 0)   # read again: the words written may have used rax
		g.a.memOp(false, 0xFF, -1, 2, f, -1, 0)   # call qword [f]: the code
	else:
		g.a.callLabel(fnLabel(g.fnLabels, g.a, inst.key))
	if not outs.isEmpty:
		g.irResultOut(em, inst, outs)
	elif inst.dst >= 0:
		if em.f.classes[inst.dst] == irFloat:
			x = em.irFloatOut(inst.dst)
			g.irMovqToXmm(x, 0)
			g.irFloatDone(em, inst.dst, x)
		else:
			g.irIntDone(em, inst.dst, 0)

# r = a cond b ? c : d: the comparison first, then only moves (they keep the flags): d into r,
# and c moved in when the condition holds (cmovcc); c through rdx when it shares r's register
fn irEmitSelect(mut g Gen, em IrEmit, inst IrInst):
	cc = g.irCompareIntFor(em, inst.a, inst.b, inst.cond)
	r = em.irIntOut(inst.dst)
	yes = g.irIntIn(em, inst.c, 2)
	if yes == r:
		g.irMov(2, yes)
		yes = 2
	g.irMov(r, g.irIntIn(em, inst.d, r))
	g.regOp(true, 0x0F, 0x40 | (irJcc(cc, inst.uns) & 15), r, yes)   # cmovcc r, yes
	g.irIntDone(em, inst.dst, r)

# a comparison and its jumps; the way to the next block falls through
fn irEmitBranch(mut g Gen, em IrEmit, inst IrInst, next i64):
	yes = em.labels[inst.target]
	no = em.labels[inst.other]
	if em.f.classes[inst.a] == irFloat:
		g.irCompareFloat(em, inst.cond, inst.a, inst.b)
		if inst.cond == irEq:
			g.a.jccLabel(0x8A, no)   # jp: unordered is not equal
			g.a.jccLabel(0x84, yes)
		elif inst.cond == irNe:
			g.a.jccLabel(0x8A, yes)
			g.a.jccLabel(0x85, yes)
		elif inst.target == next:
			g.a.jccLabel(irFloatJcc(inst.cond) ^ 1, no)   # jbe/jb: a NaN goes there too
			return
		else:
			g.a.jccLabel(irFloatJcc(inst.cond), yes)
		g.a.jmpLabel(no)
		return
	cc = irJcc(g.irCompareIntFor(em, inst.a, inst.b, inst.cond), inst.uns)
	if inst.target == next:
		g.a.jccLabel(cc ^ 1, no)
	else:
		g.a.jccLabel(cc, yes)
		g.a.jmpLabel(no)

# A switch: its cases in order (as uns orders them), searched as irSwitch.zap plans
fn irEmitSwitch(mut g Gen, em IrEmit, inst IrInst):
	values, labels = em.irSwitchCases(inst)
	x = g.irIntIn(em, inst.a, 0)
	g.irSwitchSearch(
		x,
		values,
		labels,
		0,
		values.len,
		em.labels[inst.other],
		inst.uns,
		inst.cond == 1
	)

# cases lo..hi of a switch on the register x, the default other (every: x is one of the cases, so
# no test is made for the default)
fn irSwitchSearch(
	mut g Gen,
	x i64,
	values i64[],
	labels i64[],
	lo i64,
	hi i64,
	other i64,
	uns bool,
	every bool
):
	plan = irSwitchPlan(values, lo, hi)
	if plan.kind == irSwitchCompare:
		for i in lo..hi:
			if every and i == hi - 1:
				g.a.jmpLabel(labels[i])
				return
			g.irCompareImm(x, values[i])
			g.a.jccLabel(0x84, labels[i])   # je
		g.a.jmpLabel(other)
	elif plan.kind == irSwitchTable:
		g.irJumpTable(x, values, labels, lo, hi, plan.shift, plan.span, other, every)
	else:
		upper = g.a.asmNewLabel()
		g.irCompareImm(x, values[plan.mid])
		g.a.jccLabel(0x83 if uns else 0x8D, upper)   # jae, jge
		g.irSwitchSearch(x, values, labels, lo, plan.mid, other, uns, every)
		g.a.asmPlace(upper)
		g.irSwitchSearch(x, values, labels, plan.mid, hi, other, uns, every)

# A jump table for cases lo..hi of a switch on x (their differences multiples of 2^shift, span
# entries): x less the first case, its low bits tested, shifted, its range tested, then the
# entry's distance from the table added to the table's address. The table goes after the
# function (FnState's switchTables).
fn irJumpTable(
	mut g Gen,
	x i64,
	values i64[],
	labels i64[],
	lo i64,
	hi i64,
	shift i64,
	span i64,
	other i64,
	every bool
):
	g.irMov(0, x)
	first = values[lo]
	if fitsImm32(first) and first != 0:
		g.regOp(true, 0x81, -1, 5, 0)   # sub rax, imm32
		g.a.emit32(first)
	elif first != 0:
		g.irMovImm(1, first)
		g.regOp(true, 0x29, -1, 1, 0)   # sub rax, rcx
	if shift > 0:
		if not every:
			g.a.em1(0xA9)   # test eax, imm32
			g.a.emit32((1 << shift) - 1)
			g.a.jccLabel(0x85, other)
		g.a.em4(0x48, 0xC1, 0xE8, shift)   # shr rax, shift
	if not every:
		g.regOp(true, 0x81, -1, 7, 0)   # cmp rax, imm32
		g.a.emit32(span - 1)
		g.a.jccLabel(0x87, other)   # ja: past the last case, or before the first
	table = g.a.asmNewLabel()
	g.a.em3(0x48, 0x8D, 0x0D)   # lea rcx, [rip + table]
	g.a.asmRel32Label(table)
	g.a.em4(0x48, 0x63, 0x04, 0x81)   # movsxd rax, dword [rcx + rax*4]
	g.a.em3(0x48, 0x01, 0xC8)   # add rax, rcx
	g.a.em2(0xFF, 0xE0)   # jmp rax
	g.f.switchTables.push(irTableEntries(table, values, labels, lo, hi, shift, span, other))

# rol (way 0) or ror (1) of the low w bits of r by count (-1: by cl), the bits above them zero
fn irTurn(mut g Gen, r i64, w i64, way i64, count i64):
	if w == 16:
		g.a.em1(0x66)
	rex = 0x40 | (8 if w == 64 else 0) | (1 if r >= 8 else 0)
	if rex != 0x40 or w == 8:
		g.a.em1(rex)   # w 8: the REX reaches sil, dil... as r's low byte
	op = (0xD2 if count < 0 else 0xC0) if w == 8 else 0xD3 if count < 0 else 0xC1
	g.a.em2(op, 0xC0 | way << 3 | (r & 7))
	if count >= 0:
		g.a.em1(count)
	if w == 8 or w == 16:
		# movzx r32, r8 / r16
		g.a.em1(0x40 | (5 if r >= 8 else 0))
		g.a.em3(0x0F, 0xB6 if w == 8 else 0xB7, 0xC0 | (r & 7) << 3 | (r & 7))

# cmp r, v: v an immediate when it fits 32 bits, else through rcx
fn irCompareImm(mut g Gen, r i64, v i64):
	if fitsImm32(v):
		g.regOp(true, 0x81, -1, 7, r)
		g.a.emit32(v)
	else:
		g.irMovImm(1, v)
		g.regOp(true, 0x39, -1, 1, r)   # cmp r, rcx

# word k of n of a call's arguments: vreg v's value (a float's bits) in the area at [rsp]
fn irArgWord(mut g Gen, em IrEmit, v i64, k i64, n i64):
	at = 8 * (n - 1 - k)
	if em.rs.isConst[v] and fitsImm32(em.rs.constVal[v]):
		g.a.memOp(true, 0xC7, -1, 0, 4, -1, at)   # mov qword [rsp+at], imm32
		g.a.emit32(em.rs.constVal[v])
	elif em.f.classes[v] == irFloat:
		g.irVexRM(3, 0, 0x11, g.irFloatIn(em, v, 0), 0, 4, -1, 1, at)   # vmovsd [rsp+at], x
	else:
		g.argWord(g.irIntIn(em, v, 0), k, n)

# a memory access whose base is an address in the frame, made one on rsp (its offset from there)
fn irOnFrame(g Gen, em IrEmit, inst IrInst):
	at = inst.copy()
	if not inst.frame and inst.a >= 0 and em.rs.isFrame[inst.a]:
		at.frame = true
		at.imm = inst.imm + em.rs.constVal[inst.a]
	if at.frame:
		at.imm = g.irDisp(at.imm)
	at

# a load's or a store's address: the instruction with its displacement as emitted, its base
# register (rsp, rip, or rax loaded) and its index (rcx loaded, -1 none)
fn irMemoryAt(mut g Gen, em IrEmit, inst0 IrInst):
	inst = g.irOnFrame(em, inst0)
	class = em.f.classes[inst.dst] if inst.op == irLoad else em.f.classes[inst.c]
	# data at a fixed place, no index: rip-relative (not a half, whose instruction ends in a byte)
	rip = not inst.frame and inst.a >= 0 and em.rs.isData[inst.a] and inst.b < 0 and
		not (class == irFloat and inst.size == 2)
	if rip:
		inst.imm += em.rs.constVal[inst.a]
	base = 4 if inst.frame else ripBase if rip else g.irIntIn(em, inst.a, 0)
	index = g.irIntIn(em, inst.b, 1) if inst.b >= 0 else -1
	(inst, base, index)

# r = the low size bytes of register src (or of memory, through irMemOperand), zero- or
# sign-extended
fn irExtendOp(size i64, uns bool):
	if size == 4: return (false, 0x8B, -1) if uns else (true, 0x63, -1)   # mov r32 / movsxd
	if size == 2: return (true, 0x0F, 0xB7 if uns else 0xBF)   # movzx / movsx
	(true, 0x0F, 0xB6 if uns else 0xBE)

fn irExtend(mut g Gen, r i64, src i64, size i64, uns bool):
	w, op1, op2 = irExtendOp(size, uns)
	g.regOp(w, op1, op2, r, src)

# a load or a store at a + b * scale + imm: the base in rax, the index in rcx and a stored
# integer in rdx when they are not in registers
fn irEmitMemory(mut g Gen, em IrEmit, inst0 IrInst):
	inst, base, index = g.irMemoryAt(em, inst0)
	class = em.f.classes[inst.dst] if inst.op == irLoad else em.f.classes[inst.c]
	rip = base == ripBase
	if class == irVec:
		g.irEmitVecMove(em, inst, base, index)
		return
	float = class == irFloat
	if inst.op == irLoad:
		if float:
			x = em.irFloatOut(inst.dst)
			if inst.size == 4:
				g.irVexRM(2, 0, 0x10, x, 0, base, index, inst.scale, inst.imm)   # vmovss x, [mem]
				g.irVexRR(2, 0, 0x5A, x, x, x)   # vcvtss2sd x, x
			else:
				g.irVexRM(3, 0, 0x10, x, 0, base, index, inst.scale, inst.imm)
			g.irFloatDone(em, inst.dst, x)
			return
		r = em.irIntOut(inst.dst)
		if inst.size == 8:
			g.irMemOperand(true, 0x8B, -1, r, base, index, inst.scale, inst.imm)
		else:
			w, op1, op2 = irExtendOp(inst.size, inst.uns)
			g.irMemOperand(w, op1, op2, r, base, index, inst.scale, inst.imm)
		g.irIntDone(em, inst.dst, r)
		return
	if float:
		v = g.irFloatIn(em, inst.c, 0)
		if inst.size == 4:
			g.irVexRR(3, 0, 0x5A, 1, v, v)   # vcvtsd2ss xmm1, v
			g.irVexRM(2, 0, 0x11, 1, 0, base, index, inst.scale, inst.imm)   # vmovss [mem], xmm1
			return
		g.irVexRM(3, 0, 0x11, v, 0, base, index, inst.scale, inst.imm)
		return
	if em.rs.isConst[inst.c] and fitsImm32(em.rs.constVal[inst.c]) and not rip:
		g.irStoreImm(em.rs.constVal[inst.c], inst.size, base, index, inst.scale, inst.imm)
		return
	value = g.irIntIn(em, inst.c, 2)
	if inst.size == 1:
		# a REX prefix always: with it the low byte of rsi, rdi is sil, dil (not dh, bh)
		em1(
			g.a,
			0x40 | (4 if value >= 8 else 0) | (
				2 if index >= 8 else 0
			) | (1 if base >= 8 else 0)
		)
		g.a.em1(0x88)
		g.irModRm(value, base, index, inst.scale if index >= 0 else 1, inst.imm)
		return
	if inst.size == 2:
		g.a.em1(0x66)
	g.irMemOperand(inst.size == 8, 0x89, -1, value, base, index, inst.scale, inst.imm)

# mov [mem], imm: the constant's low size bytes stored with no register (imm32 sign-extended for 8)
fn irStoreImm(mut g Gen, value i64, size i64, base i64, index i64, scale i64, disp i64):
	if size == 2:
		g.a.em1(0x66)
	g.irMemOperand(size == 8, 0xC6 if size == 1 else 0xC7, -1, 0, base, index, scale, disp)
	if size == 1:
		g.a.em1(value & 0xFF)
	elif size == 2:
		g.a.em2(value & 0xFF, (value >> 8) & 0xFF)
	else:
		g.a.emit32(value)

# lea r, [base + index * scale]
fn irModLea(mut g Gen, r i64, base i64, index i64, scale i64):
	g.a.emRexOpcode(true, 0x8D, -1, r, base, index)
	g.irModRm(r, base, index, scale, 0)

fn irMemOperand(
	mut g Gen,
	w bool,
	op1 i64,
	op2 i64,
	reg i64,
	base i64,
	index i64,
	scale i64,
	disp i64
):
	if index < 0:
		g.a.memOp(w, op1, op2, reg, base, -1, disp)
	else:
		g.a.memOpScaledDisp(w, op1, op2, reg, base, index, scaleBitsOf(scale), disp)
