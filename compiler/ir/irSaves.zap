# Shrink-wrapping: the frame and each register the function gives back (irSavedRegs) are made
# and saved in the block that first needs them instead of at entry, when some way through the
# function returns without passing there (a fast path, the end of a recursion). The blocks the
# frame's block dominates run with the frame and are emitted after the others, which run as a
# leaf (their returns a ret each). A register saved past the frame's block has a restore stub
# after the epilogue: the returns its block dominates jump there, the stub gives its registers
# back and goes on to the stub of the save point above it, the last to the epilogue.

# each reached block's place in the layout, -1 for the others
fn irLayoutPos(f IrFn, order i64[]):
	pos = fill(f.blocks.len, -1)
	for i, b in order:
		pos[b] = i
	pos

# each reached block's immediate dominator (the entry's own: itself), -1 for the others
# (Cooper, Harvey and Kennedy's iteration over the layout, a reverse postorder)
fn irDominators(f IrFn, order i64[], pos i64[]):
	n = f.blocks.len
	preds i64[,] = []
	loop n:
		preds.push([])
	for b in order:
		for s in f.irBlockSuccessors(b):
			preds[s].push(b)
	idom = fill(n, -1)
	idom[order[0]] = order[0]
	changed = true
	while changed:
		changed = false
		for i in 1..order.len:
			b = order[i]
			d = -1
			for p in preds[b]:
				if idom[p] >= 0:
					d = p if d < 0 else irMeet(idom, pos, d, p)
			if d != idom[b]:
				idom[b] = d
				changed = true
	idom

# the nearest block dominating both a and b
fn irMeet(idom i64[], pos i64[], a i64, b i64):
	x = a
	y = b
	while x != y:
		while pos[x] > pos[y]:
			x = idom[x]
		while pos[y] > pos[x]:
			y = idom[y]
	x

# The dominator tree of the reached blocks: each one's immediate dominator, its place in the
# layout and its span in a walk of the tree (a dominates b when b's span lies in a's)
type IrDom:
	idom i64[]
	pos i64[]
	enter i64[]   # -1 for a block not reached
	leave i64[]

fn irDomTree(f IrFn, order i64[]):
	pos = f.irLayoutPos(order)
	idom = f.irDominators(order, pos)
	n = f.blocks.len
	kids i64[,] = []
	loop n:
		kids.push([])
	for b in order:
		if idom[b] >= 0 and idom[b] != b:
			kids[idom[b]].push(b)
	enter = fill(n, -1)
	leave = fill(n, -1)
	enter[order[0]] = 0
	clock = 1
	stack = [(order[0], 0)]   # (block, children walked)
	while not stack.isEmpty:
		b, next = stack[len - 1]
		if next < kids[b].len:
			stack[len - 1] = b, next + 1
			k = kids[b][next]
			enter[k] = clock
			clock += 1
			stack.push((k, 0))
		else:
			leave[b] = clock
			clock += 1
			stack.pop()
	IrDom(idom, pos, enter, leave)

fn irDominates(d IrDom, a i64, b i64):
	d.enter[a] >= 0 and d.enter[b] >= 0 and d.enter[a] <= d.enter[b] and d.leave[b] <= d.leave[a]

# the nearest block dominating both a and b, at once when a does (a huge function's long chains)
fn irMeetOf(d IrDom, a i64, b i64):
	a if d.irDominates(a, b) else irMeet(d.idom, d.pos, a, b)

# Each reached block's whether a way from it comes back to it (Kosaraju's two walks: the flow's,
# then its ways back from the last block it finished): a cycle's blocks share one part
fn irCyclic(f IrFn, order i64[]):
	n = f.blocks.len
	preds i64[,] = []
	loop n:
		preds.push([])
	seen = fill(n, false)
	finished = []
	for root in order:
		if seen[root]: continue
		seen[root] = true
		stack = [(root, 0)]   # (block, ways walked)
		while not stack.isEmpty:
			b, i = stack[len - 1]
			if i < f.irNextCount(b):
				stack[len - 1] = b, i + 1
				s = f.irNextAt(b, i)
				preds[s].push(b)
				if not seen[s]:
					seen[s] = true
					stack.push((s, 0))
			else:
				finished.push(b)
				stack.pop()
	part = fill(n, -1)
	cyclic = fill(n, false)
	i = finished.len - 1
	while i >= 0:
		root = finished[i]
		i -= 1
		if part[root] >= 0: continue
		part[root] = root
		members = [root]
		k = 0
		while k < members.len:
			for p in preds[members[k]]:
				if part[p] < 0:
					part[p] = root
					members.push(p)
			k += 1
		for b in members:
			cyclic[b] = members.len > 1 or preds[b].any(it == b)
	cyclic

fn irReturns(f IrFn, b i64):
	insts = f.blocks[b].insts
	not insts.isEmpty and insts[len - 1].op == irRet

# Each register of saved's save point: the nearest block dominating every block that writes or
# reads it, raised until it is in no loop and every return after it is among the blocks it
# dominates; the entry (0) when every return passes there anyway.
fn irSavePoints(f IrFn, rs IrRegs, saved i64[], d IrDom):
	cyclic = f.irCyclic(rs.order)
	at = fill(saved.len, -1)
	metIn = fill(saved.len, -1)   # the block that last met each register
	savedOf = fill(f.classes.len, -1)
	for v in 0..f.classes.len:
		code = f.irRegCode(rs, v)
		for k in 0..saved.len:
			if saved[k] == code:
				savedOf[v] = k
	for b in rs.order:
		for inst in f.blocks[b].insts:
			for v in inst.irReads():
				k = savedOf[v]
				if k >= 0 and metIn[k] != b:
					metIn[k] = b
					at[k] = b if at[k] < 0 else d.irMeetOf(at[k], b)
			if inst.dst >= 0 and savedOf[inst.dst] >= 0 and metIn[savedOf[inst.dst]] != b:
				k = savedOf[inst.dst]
				metIn[k] = b
				at[k] = b if at[k] < 0 else d.irMeetOf(at[k], b)
	for k in 0..at.len:
		p = at[k].max(0)
		while p != 0 and not f.irWrapsAt(rs, d, cyclic, p, false):
			p = d.idom[p]
		at[k] = p
	at

# whether saving at p (making the frame there: all) is right and worth it: p is in no loop,
# every return (every block) reached from p is dominated by it, and some return is reached
# without passing p
fn irWrapsAt(f IrFn, rs IrRegs, d IrDom, cyclic bool[], p i64, all bool):
	if cyclic[p]: return false
	seen = fill(f.blocks.len, false)
	stack = f.irBlockSuccessors(p)
	while not stack.isEmpty:
		b = stack[len - 1]
		stack.pop()
		if b == p: return false
		if seen[b]: continue
		seen[b] = true
		if (all or f.irReturns(b)) and not d.irDominates(p, b): return false
		for i in 0..f.irNextCount(b):
			stack.push(f.irNextAt(b, i))
	rs.order.any(f.irReturns(it) and not d.irDominates(p, it))

# The block that makes the frame: the nearest dominating every save point and every block that
# needs the frame, raised until it fits (irWrapsAt); -1 when nothing needs one.
fn irFrameAt(f IrFn, rs IrRegs, saveAt i64[], d IrDom):
	at = -1
	for p in saveAt:
		at = p if at < 0 else d.irMeetOf(at, p)
	for b in rs.order:
		if f.irBlockNeedsFrame(rs, b):
			at = b if at < 0 else d.irMeetOf(at, b)
	cyclic = f.irCyclic(rs.order)
	while at > 0 and not f.irWrapsAt(rs, d, cyclic, at, true):
		at = d.idom[at]
	at

# whether block b needs the frame: an instruction of it does (irNeedsFrame), or reads or writes a
# vreg in a slot, or an address in the frame
fn irBlockNeedsFrame(f IrFn, rs IrRegs, b i64):
	for inst in f.blocks[b].insts:
		if f.irNeedsFrame(inst) or
			(inst.dst >= 0 and rs.spilled[inst.dst]) or
			inst.irReads().any(rs.spilled[it] or rs.isFrame[it]):
			return true
	false

# the block whose restore stub a return in each block goes to: the nearest save point dominating
# it, or -1 for the function's return (the layout puts a block's dominator before it)
fn irRestoreOwners(d IrDom, order i64[], stubAt i64[]):
	to = fill(stubAt.len, -1)
	for b in order:
		up = d.idom[b]
		to[b] = b if stubAt[b] >= 0 else -1 if up < 0 or up == b else to[up]
	to

# a register given back: its code, its save point (frameAt, or a block past it) and its slot (0:
# the frame's prologue pushes it)
type IrSave:
	code i64
	at i64
	slot i64

# The frame's plan, read from the function alone (so made with the passes, irMade.zap): the
# registers to give back and their save points (rbp's always the frame's block: the unwind codes
# say where it is, for the frames on rbp above), the frame's block, the blocks that run with it
# and the order of all, what its prologue pushes (the integer registers saved there), and whose
# stub each return, and each stub's way on, goes to (irFinishFrame gives the labels and slots).
fn irPlanFrame(mut em IrEmit):
	d = em.f.irDomTree(em.rs.order)
	codes = em.f.irSavedRegs(em.rs, false)
	points = em.f.irSavePoints(em.rs, codes, d)
	em.frameAt = em.f.irFrameAt(em.rs, points, d)
	frame = em.frameAt
	n = em.f.blocks.len
	em.framed = (0..n).map(frame >= 0 and d.irDominates(frame, it))
	em.irOrderBlocks()
	em.saves = []
	for i, code in codes:
		em.saves.push(IrSave(code, at = frame if code == 5 else points[i], slot = 0))
	em.pushed = em.saves.filter(.at == frame and .code < irFloatCode).map(.code)
	em.stubAt = fill(n, -1)
	for s in em.saves:
		if s.at != frame:
			em.stubAt[s.at] = 0
	em.retOwner = d.irRestoreOwners(em.rs.order, em.stubAt)
	em.stubUpOwner = (0..n).map(
		-2 if em.stubAt[it] < 0 else -1 if d.idom[it] < 0 else em.retOwner[d.idom[it]]
	)

# The labels and slots the plan (irPlanFrame) asked for, taken in the order the code is emitted:
# a slot for each save the prologue does not push, a label for each save point's stub.
fn irFinishFrame(mut g Gen, mut em IrEmit):
	for i, s in em.saves:
		if not (s.at == em.frameAt and s.code < irFloatCode):
			em.saves[i].slot = g.allocSlot(16 if s.code >= irFloatCode else 8)
	stubs = fill(em.stubAt.len, -1)
	for s in em.saves:
		if s.at != em.frameAt and stubs[s.at] < 0:
			stubs[s.at] = g.a.asmNewLabel()
	em.stubAt = stubs.copy()
	em.retTo = em.retOwner.map(em.retLabel if it < 0 else stubs[it])
	em.stubUp = em.stubUpOwner.map(
		-1 if it == -2 else em.retLabel if it == -1 else stubs[it]
	)

# The blocks in the order they are emitted: those without the frame, then the frame's (its block
# first, which dominates them), each part's panic paths last, out of the way of the code that runs
# (lead 23 of .NET's layout). The entry stays first.
fn irOrderBlocks(mut em IrEmit):
	panics = em.f.irPanicPaths()
	panics[0] = false
	if em.frameAt >= 0:
		panics[em.frameAt] = false
	em.order = []
	for framed in [false, true]:
		for cold in [false, true]:
			em.order.extend(em.rs.order.filter(em.framed[it] == framed and panics[it] == cold))

# the saves of the registers whose save point is block b (but those the frame's prologue pushes)
fn irSavesAt(mut g Gen, em IrEmit, b i64, restore bool):
	for s in em.saves:
		if s.at == b and not (b == em.frameAt and s.code < irFloatCode):
			g.irSaveReg(s.code, s.slot, restore)

# after the epilogue: each save point's stub, its registers given back
fn irEmitRestoreStubs(mut g Gen, em IrEmit):
	for b in em.rs.order:
		if em.stubAt[b] >= 0:
			g.a.asmPlace(em.stubAt[b])
			g.irSavesAt(em, b, true)
			g.a.jmpLabel(em.stubUp[b])
