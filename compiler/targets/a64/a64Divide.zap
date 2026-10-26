# The AArch64 code of a division and its remainder (a64Ops.zap's dispatch): by a constant a
# multiplication by its magic number (divConst.zap), else sdiv or udiv.

# a / b or a % b, the divisor checked for 0; a signed divisor of -1 negates (the quotient of the
# smallest number stops the program, the remainder is 0), which sdiv would not tell. other: the
# vreg that takes the other result (-1: none), the remainder a minus the quotient times b (msub)
fn a64EmitDivide(mut g Gen, em IrEmit, inst IrInst, other i64):
	quotient = inst.dst if inst.op == irDiv else other
	remainder = inst.dst if inst.op == irRem else other
	if em.rs.isConst[inst.b] and
		g.a64DivByConstant(em, inst, em.rs.constVal[inst.b], quotient, remainder):
		return
	known = em.rs.constVal[inst.b] if em.rs.isConst[inst.b] else 0
	b = g.a64IntIn(em, inst.b, a64T1)
	a = g.a64IntIn(em, inst.a, a64T0)
	if known == 0:
		g.a.a64Cbz(b, g.a64Site(g.failDivZero), false)
	done = g.a.asmNewLabel()
	if not inst.uns and (known == 0 or known == -1):
		divide = g.a.asmNewLabel()
		g.a.a64CmpImm(b, -1)
		g.a.a64BCond(a64Ne, divide)
		if quotient >= 0:
			g.a.a64Op3(a64Subs, 6, a64Zr, a)   # negs x6, a
			g.a64FailIf(a64Vs, g.failOverflow)
		g.a.a64Mov(7, a64Zr)
		g.a.a64B(done)
		g.a.asmPlace(divide)
	g.a.a64Op3(a64Udiv if inst.uns else a64Sdiv, 6, a, b)
	if remainder >= 0:
		g.a.a64(0x9B00_8000 | b << 16 | a << 10 | 6 << 5 | 7)   # msub x7, x6, b, a
	g.a.asmPlace(done)
	if remainder >= 0: g.a64IntDone(em, remainder, 7)
	if quotient >= 0: g.a64IntDone(em, quotient, 6)

# a division by a constant without a divide instruction (no check: v is neither 0 nor, signed,
# -1), its quotient and its remainder (a minus the quotient times v) put in their vregs (-1:
# none); false when v is one sdiv needs
fn a64DivByConstant(mut g Gen, em IrEmit, inst IrInst, v i64, quotient i64, remainder i64):
	if (v < 2 if inst.uns else v == 0 or v == -1): return false
	a = g.a64IntIn(em, inst.a, a64T0)
	q = 6 if remainder >= 0 else em.a64IntOut(quotient)
	rr = em.a64IntOut(remainder) if remainder >= 0 else -1
	if v > 0 and v & (v - 1) == 0:
		k = v.trailingZeros()
		if inst.uns:
			if quotient >= 0: g.a.a64ShiftImm(1, q, a, k, true)
			if remainder >= 0: g.a.a64(0xD340_0000 | (k - 1) << 10 | a << 5 | rr)   # ubfx rr, a, 0, k
		elif k == 0:
			if quotient >= 0: g.a.a64Mov(q, a)
			if remainder >= 0: g.a.a64Mov(rr, a64Zr)
		else:
			# a negative dividend rounded toward zero: v - 1 added first
			g.a.a64ShiftImm(2, 7, a, 63, true)
			g.a.a64Op3Shifted(a64Add, 7, a, 7, 1, 64 - k)
			if quotient >= 0: g.a.a64ShiftImm(2, q, 7, k, true)
			if remainder >= 0:
				g.a.a64(0x9240_0000 | (64 - k) << 16 | (63 - k) << 10 | 7 << 5 | 7)   # and x7, x7, -v
				g.a.a64Op3(a64Sub, rr, a, 7)
	else:
		if inst.uns:
			g.a64DivByMagicU(em, inst, a, q, v)
		else:
			m, sh = magicS64(v)
			g.a.a64MovImm(a64T1, m)
			g.a.a64Op3(a64Smulh, 6, a, a64T1)
			if v > 0 and m < 0:
				g.a.a64Op3(a64Add, 6, 6, a)
			elif v < 0 and m > 0:
				g.a.a64Op3(a64Sub, 6, 6, a)
			if sh > 0:
				g.a.a64ShiftImm(2, 6, 6, sh, true)
			g.a.a64Op3Shifted(a64Add, q, 6, 6, 1, 63)   # its sign bit added: toward zero
		if remainder >= 0:
			g.a.a64MovImm(a64T1, v)
			g.a.a64(0x9B00_8000 | a64T1 << 16 | a << 10 | 6 << 5 | rr)   # msub rr, x6, x17, a
	if remainder >= 0: g.a64IntDone(em, remainder, rr)
	if quotient >= 0: g.a64IntDone(em, quotient, q)
	true

# q = a / v unsigned, v not a power of two: below 2^32 a product and a shift (magicU32), else the
# high word of a * M (magicU64)
fn a64DivByMagicU(mut g Gen, em IrEmit, inst IrInst, a i64, q i64, v i64):
	m32, p = magicU32(v)
	if inst.imm <= 32 and m32 != 0:
		g.a.a64MovImm(a64T1, m32)
		g.a.a64Op3(a64Mul, 6, a, a64T1)
		g.a.a64ShiftImm(1, q, 6, p, true)
		return
	m, sh, add = magicU64(v)
	g.a.a64MovImm(a64T1, m)
	g.a.a64Op3(a64Umulh, 6, a, a64T1)
	if add:
		g.a.a64Op3(a64Sub, 7, a, 6)
		g.a.a64Op3Shifted(a64Add, 6, 6, 7, 1, 1)   # h + (a - h) / 2
		sh -= 1
	if sh > 0:
		g.a.a64ShiftImm(1, q, 6, sh, true)
	else:
		g.a.a64Mov(q, 6)
