# The intermediate form's machine code (ir.zap, with irRegs.zap's registers): the frame
# (on rsp, made where first needed: irSaves.zap; the fail sites, the debug lines) and calling
# convention, so its functions and these call one another. Scratch: rax, rcx, rdx (a division's, a shift's count) and xmm0, xmm1. Every float
# instruction is a VEX one (three operands, the upper halves zeroed); a float constant is read
# from the data.

alias nodes = g.c.nodes

# ZAP_RUN=irmax=n: only the first n functions through the form, for finding by bisection the one it
# gets wrong (the n-th is named)
mut irBisect = [0, 0]

fn irMaxWord():
	TraceWord("irmax", "n: only the first n functions through the form (a bisection)")

fn irWord():
	TraceWord("ir", "each function's registers and blocks, and what the form refused")

fn irDumpWord():
	TraceWord("irdump", "each function's instructions with each value's register")

fn irInlineWord():
	TraceWord("irinline", "why a call or a lambda the form meant to inline was not")

fn irBlocksWord():
	TraceWord("irblocks", "each block the form lowers: its statements' kinds and types")

fn irDropsWord():
	TraceWord("irdrops", "the drops the ownership check places where the values die")

# the functions the form could not take, or whose ownership a pass broke (irOwn.zap): each an
# error, the build refused once all are named
mut irMissing = 0

# The program's functions nothing calls (pending, their labels never placed): lowered and their
# ownership checked (irOwnProgram) as any other's, nothing emitted (the data their lowering made
# taken out again), and not again those of the kept stages a build with the same checked. A
# generic impl's methods are checked in their instances.
fn irCheckUnreached(mut g Gen, pending PendingFn[]):
	data = g.a.data.len
	for p in pending:
		label = g.fnLabels.get(p.key) ?? -1
		if label >= 0 and g.a.labelPos[label] >= 0 or p.implDecl != none or
			nodes[p.fnd].mod() == "rt" or
			nodes[p.fnd].hasFlag(flagExtern) or
			g.checkedBefore(p) or g.keptChecked(p.fnd, p.key):
			continue
		lambdas = g.irLambdaFns.len
		faults = irOwnErrors + irMissing
		low = g.irLowerChecked(p.fnd, p.implType, p.key, g.isEntry(p.key))
		g.irOwnSettle()
		g.irLambdaFns.truncate(lambdas)
		clean = low.ok and irOwnErrors + irMissing == faults
		g.noteChecked(p, clean)
		if clean: g.noteKeptChecked(p.fnd, p.key)
	g.dataBack(data)

# ---------- the checks of a group of entries ----------
# zap test's check checks a group of entry files in one process (spec 13.1). A function of a
# module, not a generic's instance, is the same code in every entry whose module and the modules
# it imports are the same files (a module sees its own files and its imports, never the entry's),
# so once lowered and checked without an error it is not lowered again for the next entry: its
# label is placed, nothing else. The entry's own functions, the ones the compiler writes
# (`derive`) and the instances (their types may be the entry's) are checked for each entry.

mut checksShared = false   # set by the check group's zap
mut checkedShared {str: bool} = {}   # by sharedCheckKey: lowered and checked without an error

# whether the lint's check again (canon.zap) lowers only the functions of the files it patched: the
# program's own lowering passed the others, and a note changes no other function's ownership, only
# types the check again checks whole
mut lowersPatchedOnly = false

fn unpatchedFn(g Gen, p PendingFn):
	file = nodes[p.fnd].file()
	lowersPatchedOnly and not file.startsWith("<") and sourceOverrides.get(notePath(file)) == none

# the key a function checked once is known by (its file, the files of its module's imports, its
# key, and the texts the lint's check again puts in place of those files'), "" when it is checked
# for every entry
fn sharedCheckKey(g Gen, p PendingFn):
	if not checksShared or p.implDecl != none: return ""
	module = nodes[p.fnd].mod()
	if module == "" or module == "derive": return ""
	m = moduleIndex(g.c.modules, module)
	if m < 0: return ""
	imported = g.c.modules[m].imports.map(i:
		at = moduleIndex(g.c.modules, nodes[i].text)
		g.c.modules[at].file.copy() if at >= 0 else ""
	)
	files = imported.copy()
	files.push(nodes[p.fnd].file().copy())
	texts = []
	for f in files:
		if sourceOverrides.get(notePath(f)) is patched: texts.push(hashWord(patched))
	"{nodes[p.fnd].file()} {imported.join(" ")} {p.key} {texts.join(" ")}"

# whether p was checked for an entry before, or the lint's check again leaves it (unpatchedFn):
# then its label is placed and it is not lowered
fn checkedBefore(mut g Gen, p PendingFn):
	key = g.sharedCheckKey(p)
	if not g.unpatchedFn(p) and (key == "" or checkedShared.get(key) == none): return false
	g.a.asmPlace(fnLabel(g.fnLabels, g.a, p.key))
	true

# p checked for this entry, clean when it found no error
fn noteChecked(g Gen, p PendingFn, clean bool):
	key = g.sharedCheckKey(p)
	if clean and key != "":
		checkedShared[key] = true

# fnd lowered and its ownership checked (irOwnProgram), its lambdas' too, lowered again while the
# check decides something (irOwnMarks): the lowering, not ok when the form cannot take it; the
# errors the check found left pending (irOwnSettle)
fn irLowerChecked(mut g Gen, fnd NodeId, implType TypeId?, key str, entry bool):
	lambdas = g.irLambdaFns.len
	file = nodes[fnd].file().copy()
	g.irFileNow = file.copy()   # (the lowering's errors are of this file)
	rounds = 0
	timed = phasesWord().on()
	at = threadCycles() if timed else 0
	low = g.irLowerFunction(fnd, implType, entry)
	while low.ok:
		marks = g.irOwnMarks.len
		if timed:
			now = threadCycles()
			loweringCycles += now - at
			at = now
		g.irOwnProgram(low.f, key, file)
		lambdaFns = move g.irLambdaFns
		g.irLambdaFns = []
		for i in lambdas..lambdaFns.len:
			lambdaKey = lambdaFns[i].key.copy()
			g.irOwnProgram(lambdaFns[i].f, lambdaKey, file)
			lambdaFns[i].checked = true
		g.irLambdaFns = move lambdaFns
		if timed:
			now = threadCycles()
			owningCycles += now - at
			at = now
		rounds += 1
		if g.irOwnMarks.len == marks or rounds > 8: break
		g.irOwnPending.clear()   # lowered again with what the check decided
		g.irLambdaFns.truncate(lambdas)
		low = g.irLowerFunction(fnd, implType, entry)
	low

# The function fnd under key lowered through the intermediate form, made with the others of its
# round (irMade.zap); false when the form cannot take it. A function checked once for a group of
# entries (once) is noted once made without an error.
fn irTryFunction(mut g Gen, fnd NodeId, key str, implType TypeId?, move once PendingFn?):
	limit = i64.parse(irMaxWord().value() ?? "-1") ?? -1
	if limit >= 0 and irBisect[0] >= limit: return false
	if g.irKeptForm(fnd, key): return true
	g.c.readBody(fnd)
	pendingLambdas = g.irLambdaFns.len
	faults = irOwnErrors + irMissing
	counted = lowerSharedWord().on()
	keeps = g.mayKeep(fnd, key)
	before = [g.lowerSharedSizes(), g.lowerMemoSizes()] if counted or keeps else []
	start = clockSeconds() if counted else 0.0
	low = g.irLowerChecked(fnd, implType, key, g.isEntry(key))
	g.irOwnSettle()
	plan = g.keptPlanOf(fnd, low.f, before, low.ok and irOwnErrors + irMissing == faults) if keeps
		else none
	if counted:
		noteLowerShared(
			before,
			[g.lowerSharedSizes(), g.lowerMemoSizes()],
			clockSeconds() - start
		)
	if not g.irAttempted(low, 0, limit, key, pendingLambdas): return false
	if irOwnErrors + irMissing == faults: g.noteKeptChecked(fnd, key)
	g.irFileNow = nodes[fnd].file().copy()
	g.made.push(
		IrMade(
			key = key.copy(),
			node = fnd,
			ret = g.c.fnRetType(fnd),
			f = low.f,
			once,
			clean = irOwnErrors + irMissing == faults,
			kept = plan
		)
	)
	g.irMadeLambdas()
	g.irShip()
	true

# whether the lowering low (of the function or region named what) succeeded: counted for the
# bisection (slot 0 functions, 1 regions; the limit-th named), its reason traced when it did
# not, the lambdas it lowered then forgotten (earlier ones of the same function stay)
fn irAttempted(mut g Gen, low IrLower, slot i64, limit i64, what str, pendingLambdas i64):
	if low.ok:
		irBisect[slot] += 1
		if limit >= 0 and irBisect[slot] == limit:
			eprint("ir bisect: {what}")
		return true
	if slot == 0:
		eprint(compileError("BackendRefused", ["{what}", "{low.why}"]))
		irMissing += 1
	elif irWord().on():
		eprint("ir: {what}: {low.why}")
	g.irLambdaFns.truncate(pendingLambdas)
	false

type IrEmit:
	f IrFn
	rs IrRegs
	slots i64[]   # a spilled vreg's frame slot
	zeroAt bool[]   # a frame slot sharing its offset with one dropped before it: zeroed where it is made
	filled bool[]   # a frame slot written whole where it is made before anything reads it: never zeroed
	deadStores {i64: bool} = {}   # by irInstKey: a store into a frame slot nothing reads after
	sealed i64[]   # a frame slot whose address no other vreg or memory holds: its bytes (0 for any
	# other vreg), so zeroing them all leaves it known zero
	labels i64[]   # each block's label
	retLabel i64
	zeroLow i64 = 0   # the frame slots' span [zeroLow, zeroHigh) (irSlotOffsets), zeroed where the
	zeroHigh i64 = 0   #   frame is made
	frameAt i64 = -1   # the block that makes the frame (irSaves.zap's irPlanFrame), -1: none
	framed bool[] = []   # each block: whether it runs with the frame (frameAt dominates it)
	order i64[] = []   # the blocks in the order they are emitted: those without the frame first
	rotated bool[] = []   # a loop's step block placed right before its top (irRotateLoops): aligned instead
	pushed i64[] = []   # the registers the frame's prologue pushes (the integer ones saved there)
	saves IrSave[] = []   # the registers given back (irSavedRegs): pushed, or each in its slot
	stubAt i64[] = []   # a save point's restore stub, per block (-1: none)
	stubUp i64[] = []   # where a stub goes on to
	retTo i64[] = []   # where a return in each block goes
	savedCodes i64[] = []   # AArch64: the registers given back (a64PlanFrame)
	retOwner i64[] = []   # the plan's retTo before the labels: the block whose stub (-1: the return)
	stubUpOwner i64[] = []   # the plan's stubUp so (-2: no stub)
	tailCalls bool = false   # no frame slot nor frame address: a call may leave the frame behind
	reads i64[] = []   # how many instructions read each vreg

# A function's code from its first byte: its frame planned (irSaves.zap), then made where first
# needed; a function that needs none (it calls nothing, none of its checks may fail, its values
# stay in registers no function saves) is a leaf to the unwinder, its return address on top of the
# stack throughout. The frame lives on rsp, which stays put through the body: the registers saved
# pushed, then the slots, then the area of the calls' argument words at [rsp]; rbp is a register
# like the others.
fn irEmitWhole(mut g Gen, mut em IrEmit):
	g.irLabelBlocks(em)
	if onArm():
		g.a64EmitWhole(em)
		return
	g.irFinishFrame(em)
	em.irRotateLoops()
	g.irSpillSlots(em)
	g.irEmitBody(em)

# an instruction that calls, takes argument words or reads the frame (a check's exit calls its
# stub as a leaf's: without the frame)
fn irNeedsFrame(f IrFn, inst IrInst):
	irCalls(inst.op) or inst.frame or f.irArgWords(inst) > 0 or
		inst.op in [irFrameSlot, irFrameAddr, irReturnAddress]

# The argument words an instruction writes to the area at [rsp]: a call's on the stack (its
# environment, its arguments, then where its result goes), a drop's and a deep copy's (the
# runtime's arguments), and rsi and rdi kept around a long copy.
fn irArgWords(f IrFn, inst IrInst):
	op = inst.op
	if op == irCall or op == irCallPtr:
		return (1 if op == irCallPtr else 0) + f.irCallArgs(inst, true).len +
			(1 if inst.c >= 0 else 0)
	if op == irDrop: return 1
	if op == irDeepCopy: return 3
	if op == irMemCopyN or op == irMemSet or (op == irMemCopy and inst.imm > 128): return 2
	0

# the most argument words an instruction of the function writes
fn irAreaWords(f IrFn, rs IrRegs):
	n = 0
	for b in rs.order:
		for inst in f.blocks[b].insts:
			n = n.max(f.irArgWords(inst))
	n

# a function's blocks, those that run without the frame first (a leaf to the unwinder), then the
# frame's, made by the prologue at frameAt, given back by the epilogue each of their returns
# reaches (after the restore stubs of the save points past frameAt)
fn irEmitBody(mut g Gen, mut em IrEmit):
	frame = g.f.maxFrame
	g.f.area = true
	g.f.frameAlloc = frame + 8 * em.f.irAreaWords(em.rs)
	g.f.framePushed = 8 * em.pushed.len
	if em.frameAt != 0:
		g.a.asmUnwindRegion(unwindLeaf)
	g.irEmitBlocks(em)
	if em.frameAt >= 0:
		g.f.framed = true
		g.a.asmPlace(em.retLabel)
		g.irEmitEpilogue(em)
		g.a.em1(0xC3)   # ret
		g.emitFailSites(true)
		g.irEmitRestoreStubs(em)
	g.irEmitMinusOnes()   # (past every return: no block falls into it)
	g.irPlaceSwitchTables()
	if g.f.failSites.any(.framed):
		die("x64: a check with the frame in a function without one")
	if not g.f.failSites.isEmpty:
		g.a.asmUnwindRegion(unwindLeaf)   # the exits of the checks made without the frame
		g.emitFailSites(false)
	if g.f.maxFrame != frame:
		die("x64: a frame slot taken while the code was emitted")
	g.f.area = false
	g.f.framed = false

# the frame given back: the registers saved at its block restored, its bytes and pushes undone
fn irEmitEpilogue(mut g Gen, em IrEmit):
	g.irSavesAt(em, em.frameAt, true)
	g.a.addRsp(g.f.frameAlloc)
	i = em.pushed.len - 1
	while i >= 0:
		g.irPushPop(em.pushed[i], 0x58)
		i -= 1

# Whether the call at insts[ii] of block b is a tail call: its result (or nothing) returned right
# after it, nothing between but ownership's markers, its arguments in registers, a function that
# owns no bytes of its frame a pointer could reach, and the way out the epilogue itself (no restore
# stub). It becomes a jump once the frame is given back; a call of the runtime's stays one, so its
# allocations and stops name the caller (they read the frames).
fn irTailCall(em IrEmit, insts IrInst[], ii i64, b i64):
	not (em.framed[b] and em.retTo[b] != em.retLabel) and em.irTailCallAt(insts, ii)

# irTailCall but for the way out, which AArch64's frame always has one of (a64Ir.zap)
fn irTailCallAt(em IrEmit, insts IrInst[], ii i64):
	call = insts[ii]
	if call.op != irCall or call.key == "" or call.key.startsWith("rt__") or call.c >= 0 or
		not em.f.irCallArgs(call, true).isEmpty or not em.tailCalls:
		return false
	k = ii + 1
	while k < insts.len and irIsMarker(insts[k].op):
		k += 1
	k == insts.len - 1 and insts[k].op == irRet and insts[k].args.isEmpty and
		(insts[k].a < 0 or insts[k].a == call.dst)

# a tail call: its arguments in their registers, the frame given back, then a jump to the callee
fn irEmitTailCall(mut g Gen, em IrEmit, inst IrInst):
	g.irRegArgsIn(em, inst.args)
	if g.f.framed:
		g.irEmitEpilogue(em)
	g.a.jmpLabel(fnLabel(g.fnLabels, g.a, inst.key))

# push r (op 0x50) or pop r (0x58)
fn irPushPop(mut g Gen, r i64, op i64):
	if r >= 8:
		g.a.em1(0x41)
	g.a.em1(op | (r & 7))

# The frame, made at the start of block frameAt: the registers saved there pushed, the rest taken
# below them, a region of code of its own from here (asmRspFrame describes the prologue); then the
# vector registers saved there and the slots zeroed (a drop of one never written frees nothing).
fn irEmitFrame(mut g Gen, em IrEmit):
	start = g.a.code.len
	ends = []
	for r in em.pushed:
		g.irPushPop(r, 0x50)
		ends.push(g.a.code.len - start)
	alloc = g.f.frameAlloc
	if alloc > 0:
		if alloc <= 127:
			g.a.em4(0x48, 0x83, 0xEC, alloc)   # sub rsp, imm8
		else:
			g.a.em3(0x48, 0x81, 0xEC)   # sub rsp, imm32
			g.a.emit32(alloc)
		ends.push(g.a.code.len - start)
	g.a.asmUnwindRegionAt(start, g.a.asmRspFrame(em.pushed, ends, alloc))
	g.irSavesAt(em, em.frameAt, false)
	g.irZeroSlots(em.zeroLow, em.zeroHigh, em.frameAt == 0 and em.f.irFloatRegParams())

# The slots of [low, high) zeroed: a few word by word from rax, many by a loop over the span
# storing four words a step from xmm0 (rax counting its words up to 0, so it takes no other
# register: values may be live here; xmm0 is every instruction's scratch), or a word a step when
# xmm0 holds an argument yet (keepXmm0)
fn irZeroSlots(mut g Gen, low i64, high i64, keepXmm0 bool):
	if high <= low: return
	if keepXmm0 and high - low > 64:
		g.irMovImm(0, -(high - low) / 8)
		again = g.a.asmNewLabel()
		g.a.asmPlace(again)
		g.irStoreImm(0, 8, 4, 0, 8, g.irDisp(high))   # mov qword [rsp+rax*8+high], 0
		g.a.em4(0x48, 0x83, 0xC0, 1)   # add rax, 1
		g.a.jccLabel(0x85, again)   # jnz again
		return
	if high - low <= 64:
		g.a.em2(0x31, 0xC0)   # xor eax, eax
		at = low
		while at < high:
			g.a.memOp(true, 0x89, -1, 0, 4, -1, g.irDisp(at))   # mov [rsp+at], rax
			at += 8
		return
	words = (high - low) / 8
	extra = words % 4
	if extra > 0:
		g.irZeroWords(4, g.irDisp(low), extra)
	if extra < 2:   # (irZeroWords cleared xmm0 for two or three)
		g.irVexRR(0, 0, 0x57, 0, 0, 0)   # vxorps xmm0, xmm0, xmm0
	g.irMovImm(0, -(words - extra))
	again = g.a.asmNewLabel()
	g.a.asmPlace(again)
	for half in 0..2:
		g.irVexRM(0, 0, 0x11, 0, 0, 4, 0, 8, g.irDisp(high) + 16 * half)   # vmovups [rsp+rax*8+high], xmm0
	g.a.em4(0x48, 0x83, 0xC0, 4)   # add rax, 4
	g.a.jccLabel(0x85, again)   # jnz again

# A place in the frame as rsp sees it in the code being emitted: d below 0 a slot (from the
# top of what the prologue takes), d from 8 up the words above the frame as rbp saw them (8 the
# return address, 16 on the caller's argument words).
fn irDisp(g Gen, d i64):
	if not g.f.framed: return d - 8
	g.f.frameAlloc + d if d <= 0 else g.f.frameAlloc + g.f.framePushed + d - 8

# where a spilled vreg lives, from rsp
fn irSlot(g Gen, em IrEmit, v i64):
	g.irDisp(em.slots[v])
