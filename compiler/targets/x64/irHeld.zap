# A round's functions emitted as they come back from their passes, while its lowering goes on, so
# a round holds the forms of the functions in flight, not of every function it lowered: a held
# function's code is emitted and kept as a kept code is (keptCode.zap: its bytes and what it names
# outside them by what it is, the labels and data made before it by their numbers), then what its
# emission added to the program taken out again, so the lowering after it finds the program as it
# was. The round's end places the held codes in order among the functions emitted then
# (irMakeAll), as their emission would write them there: the executable is the one emitting all of
# them at the end makes, byte for byte. A function is held only when placing its code at once gives
# back what its emission added; else it waits for the round's end with its form.

alias nodes = g.c.nodes
alias kidIds = g.c.kidIds

# the program's lists as they stood before an emission, and what it may change in place
type HeldMark:
	code i64
	fixes i64
	labels i64
	pads i64
	regions i64
	regionLast i64   # the last region's kind (one begun at its place takes it)
	infos i64
	lines i64
	lineLast i32[]   # the last source line's note (one at its place takes it)
	files i64
	imports i64
	data i64
	planned i64
	libc i64
	addresses i64
	types i64
	envs i64
	bss i64
	peephole i64[]
	jumpLabels i64[]
	emitting i64
	nested bool
	floor i64
	below i64[]
	line i64
	col i64
	file i64
	inRt bool
	xmm0Zero bool
	xmm0Held i64

fn heldMarkOf(g Gen):
	n = g.debugLines.len
	regions = g.a.unwindAt.len
	HeldMark(
		code = g.a.code.len,
		fixes = g.a.fixAt.len,
		labels = g.a.labelPos.len,
		pads = g.a.padAt.len,
		regions,
		regionLast = g.a.unwindKind[regions - 1] if regions > 0 else 0,
		infos = g.a.unwindInfos.len,
		lines = n,
		lineLast = g.debugLines[n - 4..].copy() if n >= 4 else [],
		files = g.debugFiles.len,
		imports = g.a.imports.len,
		data = g.a.data.len,
		planned = g.planned.len,
		libc = g.a.libcNames.len,
		addresses = g.a.addresses.len,
		types = g.c.types.len,
		envs = g.envs,
		bss = g.a.bss,
		peephole = g.a.asmPeephole(),
		jumpLabels = g.a.endJmpLabels.copy(),
		emitting = g.emitting,
		nested = g.nested,
		floor = g.a.labelFloor,
		below = g.a.placedBelow.copy(),
		line = g.curLine,
		col = g.curCol,
		file = g.curFile,
		inRt = g.inRt,
		xmm0Zero = g.xmm0Zero,
		xmm0Held = g.xmm0Held
	)

# the program as it stood at mark: what an emission since added taken out, what it changed put back
fn heldUndo(mut g Gen, mark HeldMark):
	while (g.a.fnMade.last ?? -1) >= mark.labels:
		g.a.fnMade.pop()
		key = g.a.fnMadeKeys.pop() ?? fail("a function's label without its key")
		g.fnLabels.remove(key)
	for f in mark.fixes..g.a.fixAt.len:
		kind = g.a.fixKind[f]
		target = g.a.entryLabel(g.a.fixTarget[f]) if kind == fxTable else i64(g.a.fixTarget[f])
		if (kind == fxLabel or kind == fxTable) and target < mark.labels:
			g.a.labelJumps[target] -= 1
	for l in g.a.placedBelow:
		g.a.labelPos[l] = -1
	g.a.code.truncate(mark.code)
	g.a.fixKind.truncate(mark.fixes)
	g.a.fixAt.truncate(mark.fixes)
	g.a.fixTarget.truncate(mark.fixes)
	g.a.fixJump.truncate(mark.fixes)
	g.a.labelPos.truncate(mark.labels)
	g.a.labelJumps.truncate(mark.labels)
	g.a.padAt.truncate(mark.pads)
	g.a.padLen.truncate(mark.pads)
	g.a.unwindAt.truncate(mark.regions)
	g.a.unwindKind.truncate(mark.regions)
	if mark.regions > 0: g.a.unwindKind[mark.regions - 1] = mark.regionLast
	for info in g.a.unwindInfos[mark.infos..]:
		g.a.unwindInfoOf.remove(unwindInfoKey(info))
	g.a.unwindInfos.truncate(mark.infos)
	g.debugLines.truncate(mark.lines - mark.lineLast.len)
	g.debugLines.extend(mark.lineLast)
	g.debugFiles.truncate(mark.files)
	g.a.imports.truncate(mark.imports)
	g.a.importDlls.truncate(mark.imports)
	if g.a.data.len > mark.data: g.dataBack(mark.data)
	g.planned.truncate(mark.planned)
	g.a.libcNames.truncate(mark.libc)
	g.a.libcAt.truncate(mark.libc)
	g.a.addresses.truncate(mark.addresses)
	g.envs = mark.envs
	g.a.bss = mark.bss
	g.a.asmPeepholeSet(mark.peephole)
	g.a.endJmpLabels = mark.jumpLabels.copy()
	g.emitting = mark.emitting
	g.nested = mark.nested
	g.a.labelFloor = mark.floor
	g.a.placedBelow = mark.below.copy()
	g.curLine = mark.line
	g.curCol = mark.col
	g.curFile = mark.file
	g.inRt = mark.inRt
	g.xmm0Zero = mark.xmm0Zero
	g.xmm0Held = mark.xmm0Held

# what an emission since mark added to the program: its lists' lengths, the functions it planned
# and the files it named (a held code placed again must add the same, and the same data)
fn heldAdded(g Gen, mark HeldMark):
	planned = g.planned[mark.planned..].map(.key).join(",")
	files = g.debugFiles[mark.files..].join(",")
	counts = [g.a.code.len, g.a.fixAt.len, g.a.labelPos.len, g.a.padAt.len, g.a.unwindAt.len,
		g.a.unwindInfos.len, g.debugLines.len, g.a.imports.len, g.a.data.len, g.a.libcNames.len,
		g.a.addresses.len, g.c.types.len, g.envs, g.a.bss, g.fnLabels.len]
	"{counts.map(str(it)).join(",")}|{planned}|{files}"

# whether the round's function m may be emitted now: lowered with its passes run, not kept, at a
# line of its own (where its emission begins), and nothing traced from its form
fn irHoldable(g Gen, m IrMade):
	node = m.node ?? return false
	m.em != none and m.code == none and m.kept == none and m.keptForm.isEmpty and
		nodes[node].line > 0 and g.emitting == 0 and not irWord().on() and not irDumpWord().on()

# m's code emitted and held (in m.code, as a kept code is), the program as it was; file and inRt
# the source file and the runtime's flag its emission begins in (a lambda's: the function's
# before it). m keeps its form when its code cannot be held.
fn irHold(mut g Gen, mut m IrMade, file str, inRt bool):
	em = move m.em ?? return
	m.em = none
	state = move m.state ?? fail("a function held without its frame")
	m.state = none
	f = move em.f
	rs = move em.rs
	em.f = newIrFn()
	em.rs = noRegs()
	before = em.copy()
	em.f = move f
	em.rs = move rs
	stateBefore = state.copy()
	subst = move g.c.subst
	g.c.subst = Subst(names = [], types = [])
	spans = move spansAsked
	spansAsked = []
	asking = g.asksNoting
	g.asksNoting = false
	outer = move g.f
	g.f = newFnState(none, none, m.ret)
	mark = g.heldMarkOf()
	g.a.asmPeepholeClear()   # (the code before it is not its neighbour at the round's end)
	g.curFile = g.debugFile(file)
	g.inRt = inRt
	g.irEnterMade(m)
	g.f = move state
	begun = g.keptCodeBegin()
	begun.stable = mark.labels
	begun.stableData = mark.data
	g.irEmitWhole(em)
	data = []
	code = g.keptCodeEnd(begun, data, [])
	added = g.heldAdded(mark)
	bytes = g.a.data[mark.data..].copy()
	g.heldUndo(mark)
	if code is held:
		g.a.asmPeepholeClear()
		g.curFile = g.debugFile(file)
		g.inRt = inRt
		g.irEnterMade(m)
		g.f = newFnState(none, none, m.ret)
		g.placeKeptCode(held, data, [])
		again = g.heldAdded(mark)
		same = again == added and g.a.data[mark.data..] == bytes
		g.heldUndo(mark)
		if same:
			m.heldCode.pushKeptCode(held)
			m.heldCode = m.heldCode.copy()   # (its room exact)
			m.keptData = data
			m.held = true
	g.f = move outer
	g.asksNoting = asking
	spansAsked = move spans
	g.c.subst = move subst
	if m.held: return
	f2 = move em.f
	rs2 = move em.rs
	em = move before
	em.f = move f2
	em.rs = move rs2
	m.em = move em
	m.state = move stateBefore

# the round's functions back from their passes in order from irHeldNext held when they may be,
# irHeldFile and irHeldRt following the emission's (irPipe.zap)
fn irHoldInOrder(mut g Gen):
	while irHeldNext < irBackIn.len and irBackIn[irHeldNext]:
		if not irBack[irHeldNext].lambda and irBack[irHeldNext].node is node:
			irHeldFile = nodes[node].file(kidIds).copy()
			irHeldRt = nodes[node].mod(kidIds) == "rt"
		if g.irHoldable(irBack[irHeldNext]):
			g.irHold(irBack[irHeldNext], irHeldFile, irHeldRt)
		irHeldNext += 1

# registers of no vreg (an IrEmit's while its form is set aside)
fn noRegs():
	IrRegs(
		order = [],
		reg = [],
		spilled = [],
		isConst = [],
		isFrame = [],
		isData = [],
		constVal = [],
		weight = [],
		saved = []
	)

# ---------- the assembler's peephole state, whole ----------

fn asmPeephole(a Asm):
	[a.lastStoreDisp, a.lastStoreEnd, a.lastJmpEnd, a.lastJmpTarget, a.endJmpEnd, a.endJmpTarget,
		a.lastWidenStart, a.lastWidenEnd, a.lastLabelEnd, a.lastRaxFromEnd, a.lastRaxFromReg,
		a.lastRaxToEnd, a.lastRaxToReg, a.lastQmovEnd, 1 if a.lastQmovToRax else 0, a.lastXStoreEnd,
		a.lastXStoreDisp, a.lastXStoreReg, a.lastXStorePfx, a.lastAddRcxEnd]

fn asmPeepholeSet(mut a Asm, p i64[]):
	a.lastStoreDisp = p[0]
	a.lastStoreEnd = p[1]
	a.lastJmpEnd = p[2]
	a.lastJmpTarget = p[3]
	a.endJmpEnd = p[4]
	a.endJmpTarget = p[5]
	a.lastWidenStart = p[6]
	a.lastWidenEnd = p[7]
	a.lastLabelEnd = p[8]
	a.lastRaxFromEnd = p[9]
	a.lastRaxFromReg = p[10]
	a.lastRaxToEnd = p[11]
	a.lastRaxToReg = p[12]
	a.lastQmovEnd = p[13]
	a.lastQmovToRax = p[14] == 1
	a.lastXStoreEnd = p[15]
	a.lastXStoreDisp = p[16]
	a.lastXStoreReg = p[17]
	a.lastXStorePfx = p[18]
	a.lastAddRcxEnd = p[19]

# no instruction before the code that follows for a peephole to take in
fn asmPeepholeClear(mut a Asm):
	a.asmPeepholeSet([0, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 0, -1, 0, -1, 0, -1])
	a.endJmpLabels = []
