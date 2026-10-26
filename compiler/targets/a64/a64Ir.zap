# The intermediate form's AArch64 code (ir.zap, with irRegs.zap's registers and irX64Frame.zap's
# slots, the knowledge both machines share): the frame, the operands and the walk of the blocks;
# a64Ops.zap writes each instruction. The allocator gives AArch64's own registers (irArmPools):
# x15..x17, x8 and v0..v2 are the code's own scratch, and x0..x7 the scratch of the instructions
# a64Clobbers names, which no vreg they meet holds.
#
# The frame is AAPCS64's frame record: x29 points at the saved x29 and x30 (the return address at
# x29 + 8), the slots below it at the offsets the slots were given as rbp saw them, the registers
# saved below the slots, and the calls' argument words at sp (the words a call takes on the stack
# are there in the order x64 pushes them, so a callee reads them at x29 + 16 up, as on x64). A
# function that takes its arguments in registers has them in x0..x3 and d0..d5 (a64RegArgs.zap),
# its result in x0 (a float's bits) or a small aggregate's in x0, x1 and d0..d3; the address a
# non-scalar result is written to is the last argument word.

alias nodes = g.c.nodes

# A check's exit after the function: a call of its stub from where the check is, so the return
# address names the place. A check before the frame is made (leaf: x30 still the function's own
# return address) first pushes the frame record the report's walk of the calls reads.
type A64Site:
	label i64
	stub i64
	line i64
	col i64
	file i64
	leaf bool

mut a64Sites A64Site[] = []

# whether the block being emitted runs before its function's frame is made
mut a64InLeaf = false

# ZAP_RUN=a64: the operations AArch64 does not take yet, each a brk in the code
fn a64Word():
	TraceWord(
		"a64",
		"each operation the AArch64 build writes as a stop (one it does not take yet), by its place"
	)

# the frame of the function being emitted: the registers it gives back (irSavedRegs' codes) and
# the bytes it takes below x29
type A64Frame:
	saved i64[]
	size i64

# A function's code from its first instruction. The frame is made at the start of the block
# that first needs it (irSaves.zap's irFrameAt: the entry unless some way returns without one),
# given back at its one way out after the blocks; the blocks before it run as a leaf, x30 the
# return address throughout, each return a ret. A loop's step block goes before its top
# (irRotateLoops). The checks' exits come last.
fn a64EmitWhole(mut g Gen, mut em IrEmit):
	a64Narrows = em.f.irNarrowVectors()
	g.irSpillSlots(em)
	saved = em.savedCodes.copy()
	em.irRotateLoops()
	frame = A64Frame(
		saved,
		size = (g.f.maxFrame + 8 * saved.len + 8 * em.f.irAreaWords(em.rs)).alignUp(16)
	)
	a64FrameBytes = frame.size
	a64Far = em.f.blocks.sum(.insts.len) > a64FarInsts
	for oi, b in em.order:
		next = em.order[oi + 1] if oi + 1 < em.order.len else -1
		g.a.asmPlace(em.labels[b])
		if b == em.frameAt: g.a64Prologue(em, frame)
		g.a64EmitBlock(em, frame, b, next)
	if em.frameAt >= 0:
		g.a.asmPlace(em.retLabel)
		g.a64Epilogue(frame)
	a64FrameBytes = -1
	g.a64EmitSites()
	g.irPlaceSwitchTables()
	a64Far = false

# the block that makes the frame (-1: none), the blocks it dominates (framed) laid out after the
# others; a function with arguments on the stack makes it at entry (it reads them from x29). Read
# from the function alone, so made with the passes (irMade.zap).
fn a64PlanFrame(mut em IrEmit):
	saved = em.f.irSavedRegs(em.rs, false)
	em.savedCodes = saved.copy()
	d = em.f.irDomTree(em.rs.order)
	em.frameAt = em.f.irFrameAt(em.rs, em.f.irSavePoints(em.rs, saved, d), d)
	if em.f.blocks[0].insts.any(.op == irParam and not .regArgs): em.frameAt = 0
	em.framed = (0..em.f.blocks.len).map(em.frameAt >= 0 and d.irDominates(em.frameAt, it))
	em.irOrderBlocks()

fn a64EmitBlock(mut g Gen, em IrEmit, frame A64Frame, b i64, next i64):
	insts = em.f.blocks[b].insts
	a64InLeaf = not em.framed[b]
	stillZero = []   # irZerosOverZeros' slots
	joined = 0   # instructions the one before wrote with it
	for ii, inst in insts:
		if joined > 0:
			joined -= 1
			continue
		if irIsMarker(inst.op) or inst.op == irNote or irInstKey(b, ii) in em.deadStores: continue
		if inst.op == irJmp and not irGoesOn(insts, ii): continue
		if em.irZerosOverZeros(inst, stillZero): continue
		if inst.line > 0 and inst.line != g.curLine:
			g.curLine = inst.line
			g.curCol = inst.col
			g.noteDebugLine(g.curLine, g.curCol, g.curFile)
		if g.a64ZeroRun(em, insts, ii, stillZero) is run:
			joined = run - 1
		elif ii + 1 < insts.len and inst.irDivPair(insts[ii + 1]):
			g.a64EmitDivide(em, inst, insts[ii + 1].dst)   # one division gives both
			joined = 1
		elif g.a64CarryOf(em, insts, ii) is taken:
			joined = taken - 1
		elif inst.op == irRet:
			g.a64EmitReturn(em, inst, next, em.framed[b])
		elif em.irTailCallAt(insts, ii):
			# its arguments in their registers, the frame given back, then a jump to the callee
			g.a64LeavesIn(em, inst.args)
			if em.framed[b]: g.a64FrameGone(frame)
			g.a.a64B(fnLabel(g.fnLabels, g.a, inst.key))
			return
		elif not insts.irCallOutsAt(ii).isEmpty:
			outs = insts.irCallOutsAt(ii)
			g.a64EmitCall(em, inst, outs)   # its result's leaves with it
			joined = outs.len
		else:
			g.a64EmitInst(em, inst, next)
	if (insts.isEmpty or not isTerminator(insts[len - 1].op)) and next != b + 1 and
		irGoesOn(insts, insts.len):
		g.a.a64B(em.labels[b + 1])   # falls into the block after it

# the frame record, the frame's bytes, the registers saved and the slots zeroed (a drop of one
# never written frees nothing)
fn a64Prologue(mut g Gen, em IrEmit, frame A64Frame):
	g.a.a64Pair(false, a64Fp, a64Lr, a64Sp, -16, 1)   # stp x29, x30, [sp, -16]!
	g.a.a64AddImm(a64Fp, a64Sp, 0)
	g.a.a64AddImm(a64Sp, a64Sp, -frame.size)
	g.a64SaveRegs(frame, false)
	g.a64ZeroFrame(em.zeroLow, em.zeroHigh)

fn a64Epilogue(mut g Gen, frame A64Frame):
	g.a64FrameGone(frame)
	g.a.a64Ret()

# the registers saved given back, then the frame and its record
fn a64FrameGone(mut g Gen, frame A64Frame):
	g.a64SaveRegs(frame, true)
	g.a.a64AddImm(a64Sp, a64Fp, 0)
	g.a.a64Pair(true, a64Fp, a64Lr, a64Sp, 16, 2)   # ldp x29, x30, [sp], 16

# each saved register stored below the slots (restore: loaded back), two of a kind side by side
# by one stp or ldp
fn a64SaveRegs(mut g Gen, frame A64Frame, restore bool):
	k = 0
	while k < frame.saved.len:
		code = frame.saved[k]
		at = -g.f.maxFrame - 8 * (k + 1)
		float = code >= irFloatCode
		r = code - irFloatCode if float else code
		base, off = a64FrameBase(a64Fp, at - 8)
		if k + 1 < frame.saved.len and (frame.saved[k + 1] >= irFloatCode) == float and
			off >= -512 and off < 512:
			next = frame.saved[k + 1]
			below = next - irFloatCode if float else next
			g.a.a64Pair(restore, below, r, base, off, 0, float)
			k += 2
			continue
		if float:
			if restore:
				g.a.a64LoadF(r, a64Fp, at, 8)
			else:
				g.a.a64StoreF(r, a64Fp, at, 8)
		elif restore:
			g.a.a64Ldr(r, a64Fp, at)
		else:
			g.a.a64Str(r, a64Fp, at)
		k += 1

# the frame's bytes [low, high) from x29 zeroed: word by word, or by a loop over many
fn a64ZeroFrame(mut g Gen, low i64, high i64):
	if high <= low: return
	if high - low <= 128:
		g.a.a64ZeroWordsAt(a64Fp, low, (high - low) / 8)
		return
	g.a.a64AddImm(a64T0, a64Fp, low)
	g.a.a64ZeroWords(a64T0, (high - low) / 8)

# n words of zero at base + off: two at a time by stp xzr, xzr where its offset reaches, the last
# one alone
fn a64ZeroWordsAt(mut a Asm, base i64, off i64, n i64):
	k = 0
	while k + 2 <= n:
		pairBase, at = a64FrameBase(base, off + 8 * k)
		if at >= -512 and at < 512 and at % 8 == 0:
			a.a64Pair(false, a64Zr, a64Zr, pairBase, at, 0)
		else:
			a.a64Str(a64Zr, base, off + 8 * k)
			a.a64Str(a64Zr, base, off + 8 * k + 8)
		k += 2
	if k < n: a.a64Str(a64Zr, base, off + 8 * k)

# The stores of zero from ii on into the consecutive words of one address with no index
# (irZeroRun), two or more, as pairs of zero: how many, none for another shape. A frame slot so
# zeroed whole is known zero after (stillZero).
fn a64ZeroRun(mut g Gen, em IrEmit, insts IrInst[], ii i64, mut stillZero i64[]) i64?:
	run = em.irZeroRun(insts, ii)
	inst = insts[ii]
	if run < 2 or not inst.frame and em.rs.isData[inst.a]: return none
	if inst.frame:
		g.a.a64ZeroWordsAt(a64Fp, inst.imm, run)
	elif em.rs.isFrame[inst.a]:
		g.a.a64ZeroWordsAt(a64Fp, inst.imm + em.rs.constVal[inst.a], run)
	else:
		g.a.a64ZeroWordsAt(g.a64IntIn(em, inst.a, a64T0), inst.imm, run)
	if not inst.frame and em.rs.isFrame[inst.a] and inst.imm == 0 and em.sealed[inst.a] > 0 and
		8 * run >= em.sealed[inst.a]:
		stillZero.push(inst.a)
	run

# n words from the address in r zeroed (r moved past them; x17 counts)
fn a64ZeroWords(mut a Asm, r i64, n i64):
	a.a64MovImm(a64T1, n)
	again = a.asmNewLabel()
	a.asmPlace(again)
	a.a64(0xF800_8400 | r << 5 | a64Zr)   # str xzr, [r], 8
	a.a64(0xF100_0400 | a64T1 << 5 | a64T1)   # subs x17, x17, 1
	a.a64BCond(a64Ne, again)

# the result in x0, then the way out: a block without the frame's a ret, else the epilogue
# (right after the last block)
fn a64EmitReturn(mut g Gen, em IrEmit, inst IrInst, next i64, framed bool):
	if not inst.args.isEmpty:
		leaves = [inst.a]
		leaves.extend(inst.args)
		g.a64LeavesIn(em, leaves)   # a small aggregate's
	elif inst.a >= 0:
		if em.f.classes[inst.a] == irFloat:
			g.a.a64Op2(a64FmovXD, 0, g.a64FloatIn(em, inst.a, 0))
		else:
			g.a.a64Mov(0, g.a64IntIn(em, inst.a, a64T0))
	if not framed:
		g.a.a64Ret()
	elif next >= 0:
		g.a.a64B(em.retLabel)

# a branch to the exit of a check taken when cond holds, the exit calling stub
fn a64FailIf(mut g Gen, cond i64, stub i64):
	g.a.a64BCond(cond, g.a64Site(stub))

# a new check's exit to stub, at the place being generated: its label
fn a64Site(mut g Gen, stub i64):
	label = g.a.asmNewLabel()
	a64Sites.push(
		A64Site(label, stub, line = g.curLine, col = g.curCol, file = g.curFile, leaf = a64InLeaf)
	)
	label

# the exits of the function's checks: each a call of its stub, noted with the check's place
fn a64EmitSites(mut g Gen):
	for site in a64Sites:
		g.a.asmPlace(site.label)
		g.noteDebugLine(site.line, site.col, site.file)
		if site.leaf:
			g.a.a64Pair(false, a64Fp, a64Lr, a64Sp, -16, 1)   # stp x29, x30, [sp, -16]!
			g.a.a64AddImm(a64Fp, a64Sp, 0)
		g.a.a64Bl(site.stub)
	if not a64Sites.isEmpty:
		g.a.a64Brk(0)
	a64Sites.clear()

# ---------- operands ----------

# the register holding integer vreg v: its own, or scratch loaded with it
fn a64IntIn(mut g Gen, em IrEmit, v i64, scratch i64):
	if em.rs.isFrame[v]:
		g.a.a64AddImm(scratch, a64Fp, em.rs.constVal[v])
		return scratch
	if em.rs.isConst[v]:
		g.a.a64MovImm(scratch, em.rs.constVal[v])
		return scratch
	if em.rs.isData[v]:
		g.a.a64AdrData(scratch, em.rs.constVal[v])
		return scratch
	if em.rs.spilled[v]:
		g.a.a64Ldr(scratch, a64Fp, em.slots[v])
		return scratch
	em.rs.reg[v]

# Whether the code of inst sets x0..x7 (or reads its operands after it does): a call, a return
# and a call's result, and those whose code takes them as scratch (a division, a checked
# product, a rotation, an atomic update, a copy or a fill of memory, a jump table, an address
# scaled by other than a power of two, a vector's operations); the vreg it writes is met too.
fn a64Clobbers(f IrFn, inst IrInst):
	op = inst.op
	vec = inst.dst >= 0 and f.classes[inst.dst] == irVec or
		op == irStore and inst.c >= 0 and f.classes[inst.c] == irVec
	odd = op in [irLoad, irStore] and inst.b >= 0 and inst.scale & (inst.scale - 1) != 0
	irCalls(op) or vec or odd or op == irMul and inst.trap or
		op in [
			irRet,
			irCallOut,
			irDiv,
			irRem,
			irUpdate,
			irRotate,
			irMemCopy,
			irMemCopyN,
			irMemSet,
			irXadd,
			irCmpxchg,
			irSwitch,
			irVecOp,
			irVecSplat,
			irVecMask,
			irVecLaneOf
		]

# the same, xzr for a zero constant (for an instruction that reads register 31 as xzr)
fn a64IntOrZero(mut g Gen, em IrEmit, v i64, scratch i64) i64:
	if em.rs.isConst[v] and em.rs.constVal[v] == 0: return a64Zr
	g.a64IntIn(em, v, scratch)

# the register an instruction computes integer vreg v into (x16 when v lives in a slot)
fn a64IntOut(em IrEmit, v i64):
	a64T0 if em.rs.spilled[v] or em.rs.reg[v] < 0 else em.rs.reg[v]

# v's value, computed into register r, put where v lives
fn a64IntDone(mut g Gen, em IrEmit, v i64, r i64):
	if em.rs.spilled[v]:
		g.a.a64Str(r, a64Fp, em.slots[v])
	elif em.rs.reg[v] >= 0:
		g.a.a64Mov(em.rs.reg[v], r)

# the d register holding float vreg v: its own, or scratch (d0..d2) loaded with it
fn a64FloatIn(mut g Gen, em IrEmit, v i64, scratch i64):
	if em.rs.isConst[v]:
		g.a64FloatConst(scratch, em.rs.constVal[v])
		return scratch
	if em.rs.spilled[v]:
		g.a.a64LoadF(scratch, a64Fp, em.slots[v], 8)
		return scratch
	em.rs.reg[v]

fn a64FloatOut(em IrEmit, v i64):
	0 if em.rs.spilled[v] or em.rs.reg[v] < 0 else em.rs.reg[v]

fn a64FloatDone(mut g Gen, em IrEmit, v i64, x i64):
	if em.rs.spilled[v]:
		g.a.a64StoreF(x, a64Fp, em.slots[v], 8)
	elif em.rs.reg[v] >= 0 and em.rs.reg[v] != x:
		g.a.a64Op2(a64Fmov, em.rs.reg[v], x)

# where a load or a store goes: a base register and an offset from it, or (index >= 0) a base
# and an index register, times the access's size when shifted
type A64At:
	base i64
	off i64
	index i64 = -1
	shifted bool = false

# The address of a load, a store or an update of size bytes at a + b * scale + imm: a base
# register and an offset from it (x29 for the frame; the data's address and an index's product
# in x16), or a base and the index when it is scaled by size or not at all (size 0: never)
fn a64Address(mut g Gen, em IrEmit, inst IrInst, size i64):
	base = a64T0
	off = inst.imm
	if inst.frame:
		base = a64Fp
	elif em.rs.isFrame[inst.a]:
		base = a64Fp
		off += em.rs.constVal[inst.a]
	elif em.rs.isData[inst.a] and inst.b < 0:
		g.a.a64AdrData(a64T0, em.rs.constVal[inst.a] + inst.imm)
		return A64At(a64T0, 0)
	else:
		base = g.a64IntIn(em, inst.a, a64T0)
	if inst.b < 0: return A64At(base, off)
	index = g.a64IntIn(em, inst.b, a64T1)
	if size > 0 and off == 0 and (inst.scale == 1 or inst.scale == size):
		return A64At(base, 0, index, shifted = inst.scale > 1)
	if inst.scale & (inst.scale - 1) == 0:
		shift = inst.scale.trailingZeros()
		g.a.a64Op3Shifted(a64Add, a64T0, base, index, 0, shift)
	else:
		g.a.a64MovImm(6, inst.scale)
		g.a.a64(0x9B00_0000 | 6 << 16 | base << 10 | index << 5 | a64T0)   # madd x16, index, x6, base
	A64At(a64T0, off)

# rt loaded or stored by op (a64Access's) at
fn a64AccessAt(mut a Asm, op i64, size i64, rt i64, at A64At, kind i64):
	if at.index >= 0:
		a.a64AccessIndexed(op, rt, at.base, at.index, at.shifted)
	else:
		a.a64Access(op, size, rt, at.base, at.off, kind)

# n bytes copied from the address in x5 to the address in x4 (x6 carries them, x7 counts; both
# addresses move when the copy is long)
fn a64CopyBytes(mut a Asm, n i64):
	if n <= 256:
		a.a64CopyTail(0, n)
		return
	a.a64MovImm(7, n / 8)
	again = a.asmNewLabel()
	a.asmPlace(again)
	a.a64(0xF840_8400 | 5 << 5 | 6)   # ldr x6, [x5], 8
	a.a64(0xF800_8400 | 4 << 5 | 6)   # str x6, [x4], 8
	a.a64(0xF100_0400 | 7 << 5 | 7)   # subs x7, x7, 1
	a.a64BCond(a64Ne, again)
	a.a64CopyTail(0, n % 8)

# the bytes [from, n) from x5 to x4: words, then a word's half, a half's and a byte
fn a64CopyTail(mut a Asm, from i64, n i64):
	off = from
	for size in [8, 4, 2, 1]:
		while n - off >= size:
			a.a64Load(6, 5, off, size, true)
			a.a64Store(6, 4, off, size)
			off += size
