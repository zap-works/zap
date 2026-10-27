# The AArch64 code of one instruction of the intermediate form (a64Ir.zap).

# long: a dispatch of one arm per operation
fn a64EmitInst(mut g Gen, em IrEmit, inst IrInst, next i64):
	op = inst.op
	if inst.dst >= 0 and em.f.classes[inst.dst] == irVec and op != irLoad or
		op in [irVecOp, irVecSplat, irVecMask, irVecLaneOf]:
		g.a64EmitVec(em, inst)
	elif op >= irMake and op <= irBarrier:
		g.a64Refuse(inst)   # the GPU's
	elif op == irFence:
		g.a.a64(a64DmbIsh)
	elif op == irPrefetch:
		g.a.a64(0xF980_0000 | g.a64IntIn(em, inst.a, a64T0) << 5)   # prfm pldl1keep, [a]
	elif op == irPause:
		g.a.a64(0xD503_203F)   # yield
	elif op == irConst:
		if em.rs.isConst[inst.dst]: return
		if em.f.classes[inst.dst] == irFloat:
			x = em.a64FloatOut(inst.dst)
			g.a64FloatConst(x, inst.imm)
			g.a64FloatDone(em, inst.dst, x)
		else:
			r = em.a64IntOut(inst.dst)
			g.a.a64MovImm(r, inst.imm)
			g.a64IntDone(em, inst.dst, r)
	elif op == irCopy:
		if em.irCopyInPlace(inst): return
		if em.f.classes[inst.dst] == irFloat:
			g.a64FloatDone(em, inst.dst, g.a64FloatIn(em, inst.a, em.a64FloatOut(inst.dst)))
		else:
			g.a64IntDone(em, inst.dst, g.a64IntIn(em, inst.a, em.a64IntOut(inst.dst)))
	elif op == irParam:
		g.a64EmitParam(em, inst)
	elif op in [irAdd, irSub, irAnd, irOr, irXor, irMul]:
		g.a64EmitAlu(em, inst)
	elif op == irShl or op == irShr:
		g.a64EmitShift(em, inst)
	elif op == irDiv or op == irRem:
		g.a64EmitDivide(em, inst, -1)
	elif op == irNeg or op == irNot:
		r = em.a64IntOut(inst.dst)
		a = g.a64IntIn(em, inst.a, a64T0)
		wide = inst.size != 4
		if op == irNeg:
			sub = a64Subs if inst.trap else a64Sub
			g.a.a64Op3(sub if wide else a64Narrow(sub), r, a64Zr, a)
			if inst.trap: g.a64FailIf(a64Vs, g.failOverflow)
		else:
			g.a.a64Op3(0xAA20_0000 if wide else 0x2A20_0000, r, a64Zr, a)   # orn r, xzr, a
		g.a64IntDone(em, inst.dst, r)
	elif op == irSet:
		cc = g.a64Compare(em, inst.a, inst.b, inst.cond, inst.uns)
		r = em.a64IntOut(inst.dst)
		g.a.a64Cset(r, cc)
		g.a64IntDone(em, inst.dst, r)
	elif op == irSelect:
		cc = g.a64Compare(em, inst.a, inst.b, inst.cond, inst.uns)
		yes = g.a64IntOrZero(em, inst.c, a64T0)
		no = g.a64IntOrZero(em, inst.d, a64T1)
		r = em.a64IntOut(inst.dst)
		g.a.a64Csel(r, yes, no, cc)
		g.a64IntDone(em, inst.dst, r)
	elif op in [irFAdd, irFSub, irFMul, irFDiv]:
		fop = a64Fadd if op == irFAdd else a64Fsub if op == irFSub else a64Fmul if op == irFMul
			else a64Fdiv
		x = em.a64FloatOut(inst.dst)
		g.a.a64Op3(fop, x, g.a64FloatIn(em, inst.a, 0), g.a64FloatIn(em, inst.b, 1))
		g.a64FloatDone(em, inst.dst, x)
	elif op == irCall or op == irCallPtr:
		g.a64EmitCall(em, inst)
	elif op == irCallOut:
		die("a64: a call's result leaf apart from its call")
	else:
		g.a64EmitInstFlow(em, inst, next)

fn a64EmitInstFlow(mut g Gen, em IrEmit, inst IrInst, next i64):
	op = inst.op
	if op == irJmp:
		if inst.target != next:
			g.a.a64B(em.labels[inst.target])
	elif op == irBranch:
		zero = g.a64ZeroTested(em, inst)
		if zero >= 0:
			# cbz or cbnz: to target when the test holds, to other when it fails
			holds = inst.cond == irNe
			if inst.target == next:
				g.a.a64Cbz(zero, em.labels[inst.other], not holds)
			else:
				g.a.a64Cbz(zero, em.labels[inst.target], holds)
				if inst.other != next: g.a.a64B(em.labels[inst.other])
		else:
			cc = g.a64Compare(em, inst.a, inst.b, inst.cond, inst.uns)
			g.a64Branches(em, cc, inst.target, inst.other, next)
	elif op == irBranchBit and em.rs.isConst[inst.b]:
		# tst of the bit's mask
		k = em.rs.constVal[inst.b] & 63
		mask = 1 << k if k < 63 else -9_223_372_036_854_775_807 - 1
		g.a.a64LogicalImm(a64Ands, a64Zr, g.a64IntIn(em, inst.a, a64T0), mask, true)
		g.a64Branches(em, a64Ne if inst.cond == irNe else a64Eq, inst.target, inst.other, next)
	elif op == irBranchBit:
		x = g.a64IntIn(em, inst.a, a64T0)
		k = g.a64IntIn(em, inst.b, a64T1)
		g.a.a64Op3(a64Lsrv, a64T0, x, k)
		g.a.a64(0xD340_0000 | a64T0 << 5 | a64T0)   # ubfx x16, x16, 0, 1
		set = inst.cond == irNe
		if inst.target == next:
			g.a.a64Cbz(a64T0, em.labels[inst.other], not set)
		else:
			g.a.a64Cbz(a64T0, em.labels[inst.target], set)
			if inst.other != next: g.a.a64B(em.labels[inst.other])
	elif op == irSwitch:
		values, labels = em.irSwitchCases(inst)
		x = g.a64IntIn(em, inst.a, a64T0)
		fall = em.labels[next] if next >= 0 else -1
		g.a64SwitchSearch(
			x,
			values,
			labels,
			0,
			values.len,
			em.labels[inst.other],
			fall,
			inst.uns,
			inst.cond == 1
		)
	elif op == irLoad or op == irStore:
		g.a64EmitMemory(em, inst)
	elif op == irUpdate:
		at = g.a64Address(em, inst, 8)
		g.a.a64AccessAt(a64LoadOp(8, true), 8, 6, at, accessLoad)
		value = g.a64IntIn(em, inst.c, a64T2)
		k = inst.cond
		alu = a64Add if k == irAdd else a64Sub if k == irSub else a64And if k == irAnd
			else a64Orr if k == irOr
			else a64Eor
		g.a.a64Op3(alu, 6, 6, value)
		g.a.a64AccessAt(a64StoreOp(8), 8, 6, at, accessStore)
	elif op == irFailIf:
		zero = g.a64ZeroTested(em, inst)
		if zero >= 0:
			g.a.a64Cbz(zero, g.a64Site(inst.imm), inst.cond == irNe)
		else:
			g.a64FailIf(g.a64Compare(em, inst.a, inst.b, inst.cond, inst.uns), inst.imm)
	else:
		g.a64EmitInstPlace(em, inst)

# the register of the integer a comparison of inst tests for == 0 or != 0 (cbz, cbnz), -1 when
# it is another comparison
fn a64ZeroTested(mut g Gen, em IrEmit, inst IrInst) i64:
	if inst.cond != irEq and inst.cond != irNe or em.f.classes[inst.a] == irFloat: return -1
	zeroB = em.rs.isConst[inst.b] and em.rs.constVal[inst.b] == 0
	zeroA = em.rs.isConst[inst.a] and em.rs.constVal[inst.a] == 0
	if zeroB == zeroA: return -1
	g.a64IntIn(em, inst.a if zeroB else inst.b, a64T0)

# a comparison's two ways: the one to the next block falls through
fn a64Branches(mut g Gen, em IrEmit, cc i64, target i64, other i64, next i64):
	if target == next:
		g.a.a64BCond(cc ^ 1, em.labels[other])
		return
	g.a.a64BCond(cc, em.labels[target])
	if other != next: g.a.a64B(em.labels[other])

# the addresses and the words of the frame, the data and the thread
fn a64EmitInstPlace(mut g Gen, em IrEmit, inst IrInst):
	op = inst.op
	if op == irDataAddr:
		if em.rs.isData[inst.dst]: return   # each use makes its address
		r = em.a64IntOut(inst.dst)
		g.a.a64AdrData(r, inst.imm)
		g.a64IntDone(em, inst.dst, r)
	elif op == irFnAddr:
		r = em.a64IntOut(inst.dst)
		g.a.a64AdrLabel(r, fnLabel(g.fnLabels, g.a, inst.key()) if inst.key() != "" else inst.imm)
		g.a64IntDone(em, inst.dst, r)
	elif op == irFrameSlot:
		if em.zeroAt[inst.dst]:   # an offset shared with a slot dropped before it
			at = em.rs.constVal[inst.dst]
			g.a64ZeroFrame(at, at + inst.imm.alignUp(8))
	elif op == irFrameAddr:
		if em.rs.isFrame[inst.dst]: return
		r = em.a64IntOut(inst.dst)
		g.a.a64AddImm(r, a64Fp, inst.imm)
		g.a64IntDone(em, inst.dst, r)
	elif op == irReturnAddress:
		r = em.a64IntOut(inst.dst)
		g.a.a64Ldr(r, a64Fp, 8)
		g.a64IntDone(em, inst.dst, r)
	elif op == irTlsGet or op == irTlsSet:
		g.a.a64(0xD53B_D040 | a64T0)   # mrs x16, tpidr_el0: the thread's slots
		index = g.a64IntIn(em, inst.a, a64T1)
		g.a.a64(a64Add | index << 16 | 3 << 10 | a64T0 << 5 | a64T0)   # add x16, x16, index, lsl 3
		if op == irTlsGet:
			r = em.a64IntOut(inst.dst)
			g.a.a64Ldr(r, a64T0, 0)
			g.a64IntDone(em, inst.dst, r)
		else:
			g.a.a64Str(g.a64IntOrZero(em, inst.b, a64T2), a64T0, 0)
	elif op == irMemCopy:
		g.a.a64Mov(4, g.a64IntIn(em, inst.a, a64T0))
		g.a.a64Mov(5, g.a64IntIn(em, inst.b, a64T0))
		g.a.a64CopyBytes(inst.imm)
	elif op == irMemCopyN or op == irMemSet:
		g.a64EmitBlockOp(em, inst)
	elif op == irDrop:
		g.a.a64Mov(0, g.a64IntIn(em, inst.a, a64T0))
		g.a64DropAt(inst.ty ?? fail("a drop of no type"))
	elif op == irDeepCopy:
		g.a.a64Mov(1, g.a64IntIn(em, inst.a, a64T0))
		g.a.a64Mov(0, g.a64IntIn(em, inst.b, a64T0))
		g.a64CopyAt(inst.ty ?? fail("a copy of no type"))
	else:
		g.a64EmitInstBits(em, inst)

# the operations on the bits of a word, the atomic ones and the floats' conversions
fn a64EmitInstBits(mut g Gen, em IrEmit, inst IrInst):
	op = inst.op
	if op == irXadd or op == irCmpxchg:
		g.a.a64Mov(4, g.a64IntIn(em, inst.a, a64T0))
		g.a.a64Mov(5, g.a64IntIn(em, inst.b, a64T0))
		if op == irCmpxchg: g.a.a64Mov(7, g.a64IntIn(em, inst.c, a64T0))
		if armAtomics():
			if op == irXadd:
				g.a.a64Op3(a64LdaddAl, 6, 4, 5)
			else:
				g.a.a64Mov(6, 5)
				g.a.a64Op3(a64CasAl, 7, 4, 6)
			g.a64IntDone(em, inst.dst, 6)
			return
		again = g.a.asmNewLabel()
		done = g.a.asmNewLabel()
		g.a.asmPlace(again)
		g.a.a64(0xC85F_FC00 | 4 << 5 | 6)   # ldaxr x6, [x4]
		if op == irXadd:
			g.a.a64Op3(a64Add, 7, 6, 5)
		else:
			g.a.a64Cmp(6, 5)
			g.a.a64BCond(a64Ne, done)
		g.a.a64(0xC800_FC00 | 8 << 16 | 4 << 5 | 7)   # stlxr w8, x7, [x4]
		g.a.a64Fixed(fxA64Cond, again, 0x3500_0000 | 8)   # cbnz w8, again
		g.a.asmPlace(done)
		g.a.a64(a64DmbIsh)   # a full barrier, as x64's lock prefix is
		g.a64IntDone(em, inst.dst, 6)
	elif op == irBswap:
		r = em.a64IntOut(inst.dst)
		a = g.a64IntIn(em, inst.a, a64T0)
		if inst.imm == 16:
			g.a.a64Op2(0x5AC0_0400, r, a)   # rev16 w
			g.a.a64Extend(r, r, 2, true)
		else:
			g.a.a64Op2(0x5AC0_0800 if inst.imm == 32 else a64Rev, r, a)
		g.a64IntDone(em, inst.dst, r)
	elif op == irRotate:
		g.a64EmitRotate(em, inst)
	elif op == irMulHigh:
		r = em.a64IntOut(inst.dst)
		g.a.a64Op3(a64Umulh, r, g.a64IntIn(em, inst.a, a64T0), g.a64IntIn(em, inst.b, a64T1))
		g.a64IntDone(em, inst.dst, r)
	elif op == irTzcnt:
		r = em.a64IntOut(inst.dst)
		a = g.a64IntIn(em, inst.a, a64T0)
		if inst.imm == 1:
			g.a.a64Op2(a64FmovDX, 0, a)
			g.a.a64(0x0E20_5800)   # cnt v0.8b, v0.8b
			g.a.a64(0x0E31_B800)   # addv b0, v0.8b
			g.a.a64Op2(a64FmovXD, r, 0)
		elif inst.imm == 2:
			g.a.a64Op2(a64Clz, r, a)
		else:
			g.a.a64Op2(a64Rbit, a64T0, a)
			g.a.a64Op2(a64Clz, r, a64T0)
		g.a64IntDone(em, inst.dst, r)
	elif op == irTrunc:
		r = em.a64IntOut(inst.dst)
		g.a.a64Extend(r, g.a64IntIn(em, inst.a, a64T0), inst.imm / 8, inst.uns)
		g.a64IntDone(em, inst.dst, r)
	else:
		g.a64EmitFloatOp(em, inst)

# the floats' own operations and their moves to and from the integers
fn a64EmitFloatOp(mut g Gen, em IrEmit, inst IrInst):
	op = inst.op
	if op in [irFloatToInt, irFloatBits, irF32Bits]:
		r = em.a64IntOut(inst.dst)
		x = g.a64FloatIn(em, inst.a, 0)
		if op == irFloatToInt:
			g.a.a64Op2(a64Fcvtzs, r, x)
		elif op == irFloatBits:
			g.a.a64Op2(a64FmovXD, r, x)
		else:
			g.a.a64Op2(a64FcvtDS, 1, x)
			g.a.a64Op2(a64FmovWS, r, 1)
		g.a64IntDone(em, inst.dst, r)
		return
	if op not in [
		irIntToFloat,
		irBitsToFloat,
		irBitsToF32,
		irRoundF32,
		irFNeg,
		irFSqrt,
		irFRoundTo
	]:
		die("a64: no AArch64 code for the intermediate form's op {op}")
	x = em.a64FloatOut(inst.dst)
	if op == irIntToFloat:
		g.a.a64Op2(a64Scvtf, x, g.a64IntIn(em, inst.a, a64T0))
	elif op == irBitsToFloat:
		g.a.a64Op2(a64FmovDX, x, g.a64IntIn(em, inst.a, a64T0))
	elif op == irBitsToF32:
		g.a.a64Op2(a64FmovSW, 1, g.a64IntIn(em, inst.a, a64T0))
		g.a.a64Op2(a64FcvtSD, x, 1)
	elif op == irRoundF32:
		g.a.a64Op2(a64FcvtDS, 1, g.a64FloatIn(em, inst.a, 0))
		g.a.a64Op2(a64FcvtSD, x, 1)
	elif op in [irFNeg, irFSqrt, irFRoundTo]:
		f = a64Fneg if op == irFNeg else a64Fsqrt if op == irFSqrt
			else [0, 0x1E65_4000, 0x1E64_C000, 0x1E65_C000][inst.imm]   # frintm, frintp, frintz
		g.a.a64Op2(f, x, g.a64FloatIn(em, inst.a, 0))
	g.a64FloatDone(em, inst.dst, x)

# an instruction AArch64 does not take yet: a stop where it would run
fn a64Refuse(mut g Gen, inst IrInst):
	if a64Word().on():
		name = g.curFileName()
		file = name if name != "" else "?"
		code = inst.imm
		avx = " (AVX map {code & 3}, pp {(code >> 2) & 3}, opcode {(code >> 8) & 255:x}, form {inst.cond}{", one operand" if inst.b < 0 else ""})"
		eprint("a64: {file}:{g.curLine}: op {inst.op}{avx if inst.op == irVecOp else ""} is a stop")
	g.a.a64Brk(1)

# a parameter on entry: from its register, or its word above the frame record
fn a64EmitParam(mut g Gen, em IrEmit, inst IrInst):
	if inst.regArgs:
		g.a64LeafDone(em, inst.dst, inst.imm)   # x imm, or d imm
		return
	at = 16 + 8 * inst.imm
	if em.slots[inst.dst] == at: return   # spilled where it came
	if em.f.classes[inst.dst] == irFloat:
		x = em.a64FloatOut(inst.dst)
		g.a.a64LoadF(x, a64Fp, at, inst.size if inst.size == 4 else 8)
		if inst.size == 4: g.a.a64Op2(a64FcvtSD, x, x)   # the word holds the f32 itself
		g.a64FloatDone(em, inst.dst, x)
	else:
		r = em.a64IntOut(inst.dst)
		g.a.a64Ldr(r, a64Fp, at)
		g.a64IntDone(em, inst.dst, r)

# dst = a op b on integers (32 bits when size is 4: the upper half zero); a trap's overflow stops
fn a64EmitAlu(mut g Gen, em IrEmit, inst IrInst):
	op = inst.op
	wide = inst.size != 4
	r = em.a64IntOut(inst.dst)
	a = g.a64IntIn(em, inst.a, a64T0)
	c = em.rs.constVal[inst.b] if em.rs.isConst[inst.b] else 0
	if (op == irAdd or op == irSub) and em.rs.isConst[inst.b] and c > -4096 and c < 4096:
		# add, adds, sub or subs of an immediate: of -c when c is negative
		sum = c if op == irAdd else -c
		word = (0x9100_0000 if sum >= 0 else 0xD100_0000) | (1 << 29 if inst.trap else 0)
		g.a.a64((word if wide else a64Narrow(word)) | sum.abs() << 10 | a << 5 | r)
		g.a64Checked(inst, r)
		g.a64IntDone(em, inst.dst, r)
		return
	logic = a64And if op == irAnd else a64Orr if op == irOr else a64Eor
	if op in [irAnd, irOr, irXor] and em.rs.isConst[inst.b] and
		g.a.a64LogicalImm(logic, r, a, c, wide):
		g.a64IntDone(em, inst.dst, r)
		return
	if op == irMul and em.rs.isConst[inst.b] and g.a64MulByConstant(inst, r, a, c):
		g.a64IntDone(em, inst.dst, r)
		return
	b = g.a64IntIn(em, inst.b, a64T1)
	if op == irMul:
		g.a64EmitMul(inst, r, a, b)
	else:
		base = (a64Adds if inst.trap else a64Add) if op == irAdd
			else (a64Subs if inst.trap else a64Sub) if op == irSub
			else a64And if op == irAnd
			else a64Orr if op == irOr
			else a64Eor
		g.a.a64Op3(base if wide else a64Narrow(base), r, a, b)
		g.a64Checked(inst, r)
	g.a64IntDone(em, inst.dst, r)

# after an add or a sub that stops on overflow: the stop, and an i32's result sign-extended (as
# it is held)
fn a64Checked(mut g Gen, inst IrInst, r i64):
	if not inst.trap: return
	g.a64FailIf(a64Vs, g.failOverflow)
	if inst.size == 4: g.a.a64Extend(r, r, 4, false)

# A sum's carry or a difference's borrow tested right after it (irCarryTest): adds or subs, then
# cset of the flag; when the test's one reader adds it next, h + carry is one cinc. The
# instructions taken, none for another shape.
fn a64CarryOf(mut g Gen, em IrEmit, insts IrInst[], ii i64) i64?:
	if ii + 1 >= insts.len: return none
	op = insts[ii]
	test = insts[ii + 1]
	if not op.irCarryTest(test) or em.rs.isConst[op.dst] or em.rs.isConst[test.dst]: return none
	add = op.op == irAdd
	r = em.a64IntOut(op.dst)
	a = g.a64IntIn(em, op.a, a64T0)
	c = em.rs.constVal[op.b] if em.rs.isConst[op.b] else -1
	if c >= 0 and c < 4096:
		g.a.a64((0xB100_0000 if add else 0xF100_0000) | c << 10 | a << 5 | r)   # adds, subs
	else:
		g.a.a64Op3(a64Adds if add else a64Subs, r, a, g.a64IntIn(em, op.b, a64T1))
	g.a64IntDone(em, op.dst, r)
	cond = a64Hs if add else a64Lo   # the carry out, or the borrow
	if ii + 2 < insts.len and em.reads[test.dst] == 1:
		use = insts[ii + 2]
		if use.op == irAdd and not use.trap and use.size == 8 and use.dst >= 0 and
			(use.a == test.dst) != (use.b == test.dst):
			h = g.a64IntIn(em, use.b if use.a == test.dst else use.a, a64T1)
			u = em.a64IntOut(use.dst)
			g.a.a64(0x9A80_0400 | h << 16 | (cond ^ 1) << 12 | h << 5 | u)   # cinc u, h, cond
			g.a64IntDone(em, use.dst, u)
			return 3
	t = em.a64IntOut(test.dst)
	g.a.a64Cset(t, cond)
	g.a64IntDone(em, test.dst, t)
	2

# r = a * c without a mul: a shift for a power of two (a trap's checked by shifting it back),
# an add of a shifted for 3, 5 and 9; false for another c
fn a64MulByConstant(mut g Gen, inst IrInst, r i64, a i64, c i64):
	wide = inst.size != 4
	if c > 0 and c & (c - 1) == 0:
		k = c.trailingZeros()
		t = 6 if inst.trap else r   # (a is read after it)
		g.a.a64ShiftImm(0, t, a, k, wide or inst.trap)
		if not inst.trap: return true
		if wide:
			g.a.a64Op3Shifted(a64Subs, a64Zr, a, t, 2, k)   # cmp a, x6, asr k
		else:
			g.a.a64(0xEB20_C000 | t << 16 | t << 5 | a64Zr)   # cmp x6, w6, sxtw
		g.a64FailIf(a64Ne, g.failOverflow)
		g.a.a64Mov(r, t)
		return true
	if inst.trap or c not in [3, 5, 9]: return false
	add = a64Add if wide else a64Narrow(a64Add)
	g.a.a64Op3Shifted(add, r, a, a, 0, (c - 1).trailingZeros())
	true

# r = a * b; a trap's product checked against the high half (smulh), or a 32-bit one against its
# sign extension
fn a64EmitMul(mut g Gen, inst IrInst, r i64, a i64, b i64):
	wide = inst.size != 4
	if not inst.trap:
		g.a.a64Op3(a64Mul if wide else a64Narrow(a64Mul), r, a, b)
		return
	if wide:
		g.a.a64Op3(a64Smulh, 6, a, b)
		g.a.a64Op3(a64Mul, r, a, b)
		g.a.a64(a64Subs | 2 << 22 | r << 16 | 63 << 10 | 6 << 5 | a64Zr)   # cmp x6, r, asr 63
	else:
		g.a.a64Op3(a64Smull, r, a, b)
		g.a.a64(0xEB20_C000 | r << 16 | r << 5 | a64Zr)   # cmp r, wr, sxtw
		g.a.a64Extend(r, r, 4, false)
	g.a64FailIf(a64Ne, g.failOverflow)

# a shift by a constant (32 bits when size is 4), or by a register (64 bits, the count modulo 64)
fn a64EmitShift(mut g Gen, em IrEmit, inst IrInst):
	r = em.a64IntOut(inst.dst)
	a = g.a64IntIn(em, inst.a, a64T0)
	kind = 0 if inst.op == irShl else 1 if inst.uns else 2
	if em.rs.isConst[inst.b]:
		g.a.a64ShiftImm(kind, r, a, em.rs.constVal[inst.b], inst.size != 4)
	else:
		count = g.a64IntIn(em, inst.b, a64T1)
		g.a.a64Op3([a64Lslv, a64Lsrv, a64Asrv][kind], r, a, count)
	g.a64IntDone(em, inst.dst, r)

# rol (cond 0) or ror (1) of a's low imm bits by b modulo imm, the bits above them zero
fn a64EmitRotate(mut g Gen, em IrEmit, inst IrInst):
	w = inst.imm
	r = em.a64IntOut(inst.dst)
	g.a.a64Extend(5, g.a64IntIn(em, inst.a, a64T0), w / 8, true)
	count = g.a64IntIn(em, inst.b, a64T1)
	g.a.a64MovImm(6, w - 1)
	g.a.a64Op3(a64And, 6, count, 6)   # x6 = the count modulo w
	if inst.cond == 0:
		g.a.a64Op3(a64Sub, 6, a64Zr, 6)   # left by n is right by -n
	if w >= 32:
		g.a.a64Op3(a64Rorv if w == 64 else a64Narrow(a64Rorv), r, 5, 6)
	else:
		g.a.a64MovImm(7, w - 1)
		g.a.a64Op3(a64And, 6, 6, 7)   # right by n in 0..w
		g.a.a64Op3(a64Lsrv, 7, 5, 6)
		g.a.a64MovImm(4, w)
		g.a.a64Op3(a64Sub, 6, 4, 6)
		g.a.a64Op3(a64Lslv, 5, 5, 6)
		g.a.a64Op3(a64Orr, 5, 5, 7)
		g.a.a64Extend(r, 5, w / 8, true)
	g.a64IntDone(em, inst.dst, r)

# the comparison of a and b (floats when a is one): the AArch64 condition that then tells cond
fn a64Compare(mut g Gen, em IrEmit, a i64, b i64, cond i64, uns bool) i64:
	if em.f.classes[a] == irFloat:
		g.a.a64Fcmp(g.a64FloatIn(em, a, 0), g.a64FloatIn(em, b, 1))
		return a64FloatCond(cond)
	if em.rs.isConst[a] and not em.rs.isConst[b]:
		return g.a64Compare(em, b, a, irSwappedCond(cond), uns)
	x = g.a64IntIn(em, a, a64T0)
	if not (em.rs.isConst[b] and g.a.a64CmpImm(x, em.rs.constVal[b])):
		g.a.a64Cmp(x, g.a64IntOrZero(em, b, a64T1))
	a64CondOf(cond, uns)

# a load or a store at a + b * scale + imm, extended by uns; a float's single converted
fn a64EmitMemory(mut g Gen, em IrEmit, inst IrInst):
	load = inst.op == irLoad
	class = em.f.classes[inst.dst] if load else em.f.classes[inst.c]
	if class == irVec:
		g.a64EmitVec(em, inst)
		return
	if class == irFloat and inst.size == 2:
		g.a64Refuse(inst)
		return
	value = -1 if load or class == irFloat else g.a64IntOrZero(em, inst.c, a64T2)
	fvalue = g.a64FloatIn(em, inst.c, 2) if not load and class == irFloat else -1
	size = inst.size
	at = g.a64Address(em, inst, size)
	if class == irFloat:
		if load:
			x = em.a64FloatOut(inst.dst)
			g.a.a64AccessAt(a64LoadOp(size, true) | a64FloatAccess, size, x, at, accessFloat)
			if size == 4: g.a.a64Op2(a64FcvtSD, x, x)
			g.a64FloatDone(em, inst.dst, x)
		else:
			if size == 4: g.a.a64Op2(a64FcvtDS, 1, fvalue)
			stored = 1 if size == 4 else fvalue
			g.a.a64AccessAt(a64StoreOp(size) | a64FloatAccess, size, stored, at, accessFloat)
	elif load:
		r = em.a64IntOut(inst.dst)
		g.a.a64AccessAt(a64LoadOp(size, inst.uns), size, r, at, accessLoad)
		g.a64IntDone(em, inst.dst, r)
	else:
		g.a.a64AccessAt(a64StoreOp(size), size, value, at, accessStore)

# c bytes from b to a (irMemCopyN), or c bytes at a set to the byte b (irMemSet): a word at a
# time while eight remain, then byte by byte (x4 the destination, x5 the source or the byte's
# pattern, x7 the count)
fn a64EmitBlockOp(mut g Gen, em IrEmit, inst IrInst):
	set = inst.op == irMemSet
	g.a.a64Mov(7, g.a64IntIn(em, inst.c, a64T0))
	g.a.a64Mov(4, g.a64IntIn(em, inst.a, a64T0))
	g.a.a64Mov(5, g.a64IntIn(em, inst.b, a64T0))
	if set:
		g.a.a64Extend(5, 5, 1, true)
		g.a.a64MovImm(6, 0x0101_0101_0101_0101)
		g.a.a64Op3(a64Mul, 5, 5, 6)
	words = g.a.asmNewLabel()
	bytes = g.a.asmNewLabel()
	done = g.a.asmNewLabel()
	g.a.asmPlace(words)
	g.a.a64CmpImm(7, 8)
	g.a.a64BCond(a64Lo, bytes)
	if not set: g.a.a64(0xF840_8400 | 5 << 5 | 6)   # ldr x6, [x5], 8
	g.a.a64(0xF800_8400 | 4 << 5 | (5 if set else 6))   # str, [x4], 8
	g.a.a64AddImm(7, 7, -8)
	g.a.a64B(words)
	g.a.asmPlace(bytes)
	g.a.a64Cbz(7, done, false)
	if not set: g.a.a64(0x3840_1400 | 5 << 5 | 6)   # ldrb w6, [x5], 1
	g.a.a64(0x3800_1400 | 4 << 5 | (5 if set else 6))   # strb, [x4], 1
	g.a.a64AddImm(7, 7, -1)
	g.a.a64B(bytes)
	g.a.asmPlace(done)

# A call: each word in the area at sp as if pushed in order (a closure's environment first, then
# the arguments on the stack, then where the result goes: the last nearest sp), then those of the
# register convention in theirs (a64RegArgs.zap); the result in x0, or a small aggregate's leaves
fn a64EmitCall(mut g Gen, em IrEmit, inst IrInst, outs IrInst[] = []):
	n = em.f.irArgWords(inst)
	k = 0
	if inst.op == irCallPtr:
		f = g.a64IntIn(em, inst.a, a64T0)
		g.a.a64Ldr(a64T0, f, 8)   # the environment
		g.a.a64Str(a64T0, a64Sp, 8 * (n - 1))
		k = 1
	for v in em.f.irCallArgs(inst, true):
		g.a64ArgWord(em, v, k, n)
		k += 1
	if inst.c >= 0:
		g.a64ArgWord(em, inst.c, k, n)
	if inst.regArgs:
		g.a64LeavesIn(em, em.f.irCallArgs(inst, false))

	if inst.op == irCallPtr:
		g.a.a64Ldr(a64T0, g.a64IntIn(em, inst.a, a64T0), 0)   # the code
		g.a.a64Blr(a64T0)
	else:
		g.a.a64Bl(fnLabel(g.fnLabels, g.a, inst.key()))
	if not outs.isEmpty:
		g.a64ResultOut(em, inst, outs)
	elif inst.dst >= 0:
		if em.f.classes[inst.dst] == irFloat:
			x = em.a64FloatOut(inst.dst)
			g.a.a64Op2(a64FmovDX, x, 0)
			g.a64FloatDone(em, inst.dst, x)
		else:
			g.a64IntDone(em, inst.dst, 0)

# word k of n of a call's arguments: vreg v's value (a float's bits) in the area at sp
fn a64ArgWord(mut g Gen, em IrEmit, v i64, k i64, n i64):
	at = 8 * (n - 1 - k)
	if em.f.classes[v] == irFloat:
		g.a.a64StoreF(g.a64FloatIn(em, v, 0), a64Sp, at, 8)
	else:
		g.a.a64Str(g.a64IntOrZero(em, v, a64T0), a64Sp, at)
