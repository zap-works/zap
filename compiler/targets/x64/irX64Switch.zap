# The emission of one instruction (irX64.zap).

fn irEmitInst(mut g Gen, em IrEmit, inst IrInst, next i64):
	op = inst.op
	float = inst.dst >= 0 and em.f.classes[inst.dst] == irFloat
	if (op == irConst or op == irCopy) and em.f.classes[inst.dst] == irVec:
		if op == irCopy or not em.rs.isConst[inst.dst]:
			g.irEmitVecMove(em, inst, -1, -1)
	elif op == irVecOp:
		g.irEmitVecOp(em, inst)
	elif op == irVecSplat:
		g.irEmitVecSplat(em, inst)
	elif op == irVecLaneOf:
		g.irEmitVecLaneOf(em, inst)
	elif op == irVecMask:
		g.irEmitVecMask(em, inst)
	elif op == irConst:
		if em.rs.isConst[inst.dst]: return
		if float:
			g.irFloatConst(em.irFloatOut(inst.dst), inst.imm)
			g.irFloatDone(em, inst.dst, em.irFloatOut(inst.dst))
		else:
			r = em.irIntOut(inst.dst)
			g.irMovImm(r, inst.imm)
			g.irIntDone(em, inst.dst, r)
	elif op == irCopy or op == irParam:
		g.irEmitCopy(em, inst)
	elif op == irFence:
		return   # x64 keeps the order itself: the fence only kept the optimizer's moves out
	elif op in [irAdd, irSub, irAnd, irOr, irXor, irMul]:
		g.irEmitAlu(em, inst)
	elif op == irShl or op == irShr:
		g.irEmitShift(em, inst)
	elif op == irDiv or op == irRem:
		g.irEmitDivide(em, inst, -1)
	elif op == irNeg or op == irNot:
		r = em.irIntOut(inst.dst)
		g.irMov(r, g.irIntIn(em, inst.a, r))
		g.regOp(inst.size != 4, 0xF7, -1, 3 if op == irNeg else 2, r)
		g.irOverflowJump(inst)
		g.irIntDone(em, inst.dst, r)
	elif op == irSet:
		g.irEmitSet(em, inst)
	elif op in [irFAdd, irFSub, irFMul, irFDiv]:
		g.irEmitFloatArith(em, inst, none)
	elif op == irFNeg:
		x = em.irFloatOut(inst.dst)
		a = g.irFloatIn(em, inst.a, 0)
		g.irMovImm(0, 1 << 63)
		g.irMovqToXmm(1, 0)
		g.irVexRR(1, 0, 0x57, x, a, 1)   # vxorpd: the sign flipped
		g.irFloatDone(em, inst.dst, x)
	elif op == irFSqrt:
		x = em.irFloatOut(inst.dst)
		a = g.irFloatIn(em, inst.a, 0)
		g.irVexRR(3, 0, 0x51, x, a, a)   # vsqrtsd: the upper half from a itself
		g.irFloatDone(em, inst.dst, x)
	elif op == irIntToFloat:
		x = em.irFloatOut(inst.dst)
		g.irVexRR(0, 0, 0x57, x, x, x)   # vxorps: no wait on x's old value
		if em.rs.spilled[inst.a]:
			g.irVexRM(3, 1, 0x2A, x, x, 4, -1, 1, g.irSlot(em, inst.a))
		else:
			g.irVexRR(3, 1, 0x2A, x, x, g.irIntIn(em, inst.a, 0))   # vcvtsi2sd
		g.irFloatDone(em, inst.dst, x)
	elif op == irCall or op == irCallPtr:
		g.irEmitCall(em, inst)
	elif op == irCallOut:
		die("x64: a call's result leaf apart from its call")
	elif op == irFnAddr:
		r = em.irIntOut(inst.dst)
		g.a.emRexOpcode(true, 0x8D, -1, r, -1, -1)
		g.a.em1(0x05 | (r & 7) << 3)   # lea r, [rip + the function]
		g.a.asmRel32Label(fnLabel(g.fnLabels, g.a, inst.key) if inst.key != "" else inst.imm)
		g.irIntDone(em, inst.dst, r)
	else:
		g.irEmitInstFlow(em, inst, next)

fn irEmitInstFlow(mut g Gen, em IrEmit, inst IrInst, next i64):
	op = inst.op
	if op == irJmp:
		g.a.jmpLabel(em.labels[inst.target])
	elif op == irBranch:
		g.irEmitBranch(em, inst, next)
	elif op == irSwitch:
		g.irEmitSwitch(em, inst)
	elif op == irBranchBit:
		x = g.irIntIn(em, inst.a, 0)
		k = g.irIntIn(em, inst.b, 1)
		g.regOp(true, 0x0F, 0xA3, k, x)   # bt x, k
		cc = 0x82 if inst.cond == irNe else 0x83   # jc: set, jnc: clear
		if inst.target == next:
			g.a.jccLabel(cc ^ 1, em.labels[inst.other])
		else:
			g.a.jccLabel(cc, em.labels[inst.target])
			g.a.jmpLabel(em.labels[inst.other])
	elif op == irLoad or op == irStore:
		g.irEmitMemory(em, inst)
	elif op == irUpdate:
		at = g.irOnFrame(em, inst)
		base = 4 if at.frame else g.irIntIn(em, at.a, 0)
		index = g.irIntIn(em, inst.b, 1) if inst.b >= 0 else -1
		k = inst.cond
		if em.rs.isConst[inst.c] and fitsImm32(em.rs.constVal[inst.c]):
			x = em.rs.constVal[inst.c]
			digit = 0 if k == irAdd
				else 5 if k == irSub
				else 4 if k == irAnd
				else 1 if k == irOr
				else 6
			short = x >= -128 and x <= 127
			g.irMemOperand(   # op [mem], imm
				true,
				0x83 if short else 0x81,
				-1,
				digit,
				base,
				index,
				inst.scale,
				at.imm
			)
			if short:
				g.a.em1(x & 0xFF)
			else:
				g.a.emit32(x)
		else:
			value = g.irIntIn(em, inst.c, 2)
			opRR = 0x01 if k == irAdd
				else 0x29 if k == irSub
				else 0x21 if k == irAnd
				else 0x09 if k == irOr
				else 0x31
			g.irMemOperand(true, opRR, -1, value, base, index, inst.scale, at.imm)   # op [mem], value
	elif op == irDataAddr:
		if em.rs.isData[inst.dst]: return   # each use reaches it rip-relative
		r = em.irIntOut(inst.dst)
		g.a.emRexOpcode(true, 0x8D, -1, r, -1, -1)
		g.a.em1(0x05 | (r & 7) << 3)   # lea r, [rip + data]
		g.a.asmDisp32Data(inst.imm)
		g.irIntDone(em, inst.dst, r)
	elif op == irFrameSlot:
		# its address is in the frame at the slot's offset (irSlotOffsets); a shared offset is
		# zeroed here
		if em.zeroAt[inst.dst]:
			g.irZeroWords(4, g.irDisp(em.rs.constVal[inst.dst]), inst.imm.alignUp(8) / 8)
	elif op == irMemCopy:
		g.irMov(1, g.irIntIn(em, inst.a, 1))
		g.irMov(0, g.irIntIn(em, inst.b, 0))
		g.copyBytes(inst.imm)   # rax to rcx (rdx between; rsi, rdi kept)
	elif op == irDrop:
		g.irMov(0, g.irIntIn(em, inst.a, 0))
		g.emitDropAt(inst.ty ?? fail("a drop of no type"))
	elif op == irDeepCopy:
		g.irMov(1, g.irIntIn(em, inst.a, 1))
		g.irMov(0, g.irIntIn(em, inst.b, 0))
		g.emitCopyAt(inst.ty ?? fail("a copy of no type"))
	elif op == irTlsGet or op == irTlsSet:
		g.irMov(1, g.irIntIn(em, inst.a, 1))   # the slot's index in rcx
		if op == irTlsGet:
			g.a.emN(x64TlsAccess(false))   # mov rax, seg:[rcx*8+disp]
			g.irIntDone(em, inst.dst, 0)
		else:
			g.irMov(0, g.irIntIn(em, inst.b, 0))
			g.a.emN(x64TlsAccess(true))   # mov seg:[rcx*8+disp], rax
	else:
		g.irEmitInstWord(em, inst, next)

fn irEmitInstWord(mut g Gen, em IrEmit, inst IrInst, next i64):
	op = inst.op
	if op == irReturnAddress:
		g.a.memOp(true, 0x8B, -1, 0, 4, -1, g.irDisp(8))   # mov rax, [rsp+the return address]
		g.irIntDone(em, inst.dst, 0)
	elif op == irPrefetch:
		base = g.irIntIn(em, inst.a, 1)
		if base >= 8:
			g.a.em1(0x41)
		g.a.em2(0x0F, 0x18)   # prefetcht0 [base]
		g.irModRm(1, base, -1, 1, 0)
	elif op == irPause:
		g.a.em2(0xF3, 0x90)   # pause
	elif op == irXadd:
		g.irMov(1, g.irIntIn(em, inst.a, 1))
		g.irMov(0, g.irIntIn(em, inst.b, 0))
		g.a.em5(0xF0, 0x48, 0x0F, 0xC1, 0x01)   # lock xadd [rcx], rax
		g.irIntDone(em, inst.dst, 0)
	elif op == irCmpxchg:
		g.irMov(1, g.irIntIn(em, inst.a, 1))
		g.irMov(2, g.irIntIn(em, inst.c, 2))
		g.irMov(0, g.irIntIn(em, inst.b, 0))
		g.a.em5(0xF0, 0x48, 0x0F, 0xB1, 0x11)   # lock cmpxchg [rcx], rdx: rax the value before
		g.irIntDone(em, inst.dst, 0)
	elif op == irBswap:
		r = em.irIntOut(inst.dst)
		g.irMov(r, g.irIntIn(em, inst.a, r))
		if inst.imm == 16:
			g.irTurn(r, 16, 0, 8)   # rol r16, 8, then the upper bits zero
		else:
			if r >= 8 or inst.imm != 32:
				g.a.em1(0x40 | (0 if inst.imm == 32 else 8) | (1 if r >= 8 else 0))
			g.a.em2(0x0F, 0xC8 | (r & 7))   # bswap r (r32 zeroes the upper half)
		g.irIntDone(em, inst.dst, r)
	elif op == irMulHigh:
		g.irEmitMulHigh(em, inst, -1)
	elif op == irRotate:
		r = em.irIntOut(inst.dst)
		count = em.rs.constVal[inst.b] & (inst.imm - 1) if em.rs.isConst[inst.b] else -1
		if count < 0:
			g.irMov(1, g.irIntIn(em, inst.b, 1))   # the count in cl, before r may take its register
		g.irMov(r, g.irIntIn(em, inst.a, r))
		g.irTurn(r, inst.imm, inst.cond, count)
		g.irIntDone(em, inst.dst, r)
	else:
		g.irEmitInstBlock(em, inst, next)

# the words a setting of bytes zeroes, when they are a known few (stored from xmm0 then)
fn irZeroWordsSet(em IrEmit, inst IrInst) i64?:
	if not em.rs.isConst[inst.b] or em.rs.constVal[inst.b] != 0 or not em.rs.isConst[inst.c]:
		return none
	bytes = em.rs.constVal[inst.c]
	if bytes <= 0 or bytes % 8 != 0 or bytes > unrolledCopyMost: return none
	bytes / 8

fn irEmitInstBlock(mut g Gen, em IrEmit, inst IrInst, next i64):
	op = inst.op
	if op == irMemSet and em.irZeroWordsSet(inst) is words:
		g.irZeroWords(g.irIntIn(em, inst.a, 2), 0, words)   # (rep stosb costs more to start)
	elif op == irMemCopyN or op == irMemSet:
		# rcx the count, rdx the destination, rax the source (or the byte); rsi and rdi may hold
		# locals of the function: kept
		g.irMov(1, g.irIntIn(em, inst.c, 1))
		g.irMov(2, g.irIntIn(em, inst.a, 2))
		g.irMov(0, g.irIntIn(em, inst.b, 0))
		g.keepRsiRdi(false)
		g.a.em3(0x48, 0x89, 0xD7)   # mov rdi, rdx
		if op == irMemSet:
			g.a.em2(0xF3, 0xAA)   # rep stosb
		else:
			g.a.em3(0x48, 0x89, 0xC6)   # mov rsi, rax
			g.genMemcpyInline()
		g.keepRsiRdi(true)
	elif op == irFRoundTo:
		x = em.irFloatOut(inst.dst)
		a = g.irFloatIn(em, inst.a, 0)
		g.irVexMap(3, 1, 0, x, a, -1, a)   # vroundsd x, a, a, imm
		g.a.em2(0x0B, 0xC0 | (x & 7) << 3 | (a & 7))
		g.a.em1(inst.imm)
		g.irFloatDone(em, inst.dst, x)
	elif op == irRoundF32:
		x = em.irFloatOut(inst.dst)
		a = g.irFloatIn(em, inst.a, 0)
		g.irVexRR(3, 0, 0x5A, x, a, a)   # vcvtsd2ss x, a
		g.irVexRR(2, 0, 0x5A, x, x, x)   # vcvtss2sd x, x
		g.irFloatDone(em, inst.dst, x)
	elif op == irF32Bits:
		a = g.irFloatIn(em, inst.a, 0)
		g.irVexRR(3, 0, 0x5A, 1, a, a)   # vcvtsd2ss xmm1, a
		r = em.irIntOut(inst.dst)
		g.irVexRR(1, 0, 0x7E, 1, 0, r)   # vmovd r32, xmm1 (the upper bits cleared)
		g.irIntDone(em, inst.dst, r)
	elif op == irBitsToF32:
		r = g.irIntIn(em, inst.a, 0)
		g.irVexRR(1, 0, 0x6E, 1, 0, r)   # vmovd xmm1, r32
		x = em.irFloatOut(inst.dst)
		g.irVexRR(2, 0, 0x5A, x, 1, 1)   # vcvtss2sd x, xmm1
		g.irFloatDone(em, inst.dst, x)
	elif op == irBitsToFloat:
		x = em.irFloatOut(inst.dst)
		g.irMovqToXmm(x, g.irIntIn(em, inst.a, 0))
		g.irFloatDone(em, inst.dst, x)
	elif op == irTzcnt:
		src = g.irIntIn(em, inst.a, 0)   # loaded first: nothing may come between the prefix and the opcode
		r = em.irIntOut(inst.dst)
		g.a.em1(0xF3)
		code = 0xB8 if inst.imm == 1 else 0xBD if inst.imm == 2 else 0xBC
		g.regOp(true, 0x0F, code, r, src)   # popcnt / lzcnt / tzcnt r, a
		g.irIntDone(em, inst.dst, r)
	elif op == irFloatToInt or op == irFloatBits:
		r = em.irIntOut(inst.dst)
		x = g.irFloatIn(em, inst.a, 0)
		if op == irFloatToInt:
			g.irVexRR(3, 1, 0x2C, r, 0, x)   # vcvttsd2si r, x
		else:
			g.irMovqFromXmm(r, x)
		g.irIntDone(em, inst.dst, r)
	elif op == irSelect:
		g.irEmitSelect(em, inst)
	elif op == irFrameAddr:
		if em.rs.isFrame[inst.dst]: return
		r = em.irIntOut(inst.dst)
		g.a.memOp(true, 0x8D, -1, r, 4, -1, g.irDisp(inst.imm))   # lea r, [rsp+imm]
		g.irIntDone(em, inst.dst, r)
	elif op == irTrunc:
		r = em.irIntOut(inst.dst)
		g.irExtend(r, g.irIntIn(em, inst.a, r), inst.imm / 8, inst.uns)
		g.irIntDone(em, inst.dst, r)
	elif op == irFailIf:
		cc = g.irCompareIntFor(em, inst.a, inst.b, inst.cond)
		g.failJump(irJcc(cc, inst.uns), inst.imm)
	else:
		die("ir: op {op}")
