# The optimizer's control flow: tail copies, jump threading, branch folding and hoisting (iropt.zap).

# the loops each block belongs to
fn irLoopsOf(f IrFn):
	of i64[,] = []
	loop f.blocks.len:
		of.push([])
	for li in 0..f.loops.len:
		for b in f.loops[li].blocks:
			of[b].push(li)
	of

# A jump to a short run of blocks that ends in a branch (where an inlined body's value meets
# the test on it) replaced by the run's instructions when the value is known on the way: the
# branch then folds (irBranchFold). Only within the same loops, so each loop is still entered
# through its block before.
fn irTailCopy(mut f IrFn):
	loopsOf = f.irLoopsOf()
	consts = f.irFacts().consts
	changed = false
	for b in 0..f.blocks.len:
		n = f.blocks[b].insts.len
		if n == 0 or f.blocks[b].insts[n - 1].op != irJmp: continue
		run = f.irTailRun(b, loopsOf)
		if run.isEmpty or not f.irFoldsAfter(b, run, consts): continue
		f.blocks[b].insts.pop()
		for inst in run:
			# a constant assigned once is written where it is read; a frame slot's or frame address's
			# value does not depend on where it is
			keep = not (inst.op == irConst and consts[inst.dst] != none) and
				inst.op != irFrameSlot and inst.op != irFrameAddr
			if keep:
				f.blocks[b].insts.push(inst.copy())
		changed = true
	changed

irTailLength = 6   # the most instructions a tail copy writes again, its branch included

# An interpreter's loop: its top block ends in a switch on the operation, and its arms jump to a
# short way back to the top (the step, the loop's test). Each arm then takes its own copy of that
# way and of the top, so each has its own switch (threaded code): the processor predicts the
# next operation from the one before it, where one shared jump predicts it from nothing. The
# copies write the same vregs (the form is not SSA), and only the arms enter them. True when a
# loop was so.
fn irDispatchCopies(mut f IrFn):
	changed = false
	consts = f.irFacts().consts
	for li in 0..f.loops.len:
		blocks = f.loops[li].blocks.copy()
		for top in blocks:
			n = f.blocks[top].insts.len
			if n == 0 or f.blocks[top].insts[n - 1].op != irSwitch or n > irDispatchLength or
				f.blocks[top].insts.any(not .irDispatchCopyable()):
				continue
			way = f.irWayBack(top, blocks) ?? continue
			arms = (0..f.blocks.len).filter(f.irJumpsTo(it, way[0]) and it in blocks)
			if arms.len < irDispatchArms: continue
			for arm in arms:
				copyTop = f.irBlock()
				# a constant assigned once is written where it is read: not written again, so it
				# stays one (an immediate operand)
				f.blocks[copyTop].insts = f.blocks[top].insts.filter(not .irOnceConst(consts))
				f.blocks[arm].insts.pop()
				for b in way:
					for k in 0..f.blocks[b].insts.len - 1:
						if not f.blocks[b].insts[k].irOnceConst(consts):
							f.blocks[arm].insts.push(f.blocks[b].insts[k].copy())
				back = way[len - 1]   # the way's last block: its branch to the top
				test = f.blocks[back].insts[f.blocks[back].insts.len - 1].copy()
				if test.target == top:
					test.target = copyTop
				else:
					test.other = copyTop
				f.blocks[arm].insts.push(test)
				for lj in 0..f.loops.len:
					if top in f.loops[lj].blocks: f.loops[lj].blocks.push(copyTop)
			changed = true
			break
	changed

# whether an instruction assigns a constant its vreg has nowhere else
fn irOnceConst(inst IrInst, consts i64?[]):
	inst.op == irConst and inst.dst >= 0 and consts[inst.dst] != none

irDispatchLength = 8   # the most instructions of the top a copy takes
irDispatchArms = 4   # the fewest arms that make a loop an interpreter's

# whether an instruction may be written again in another block: no call, no ownership marker,
# nothing that makes or names a frame slot
fn irDispatchCopyable(inst IrInst):
	not irCalls(inst.op) and not irIsMarker(inst.op) and inst.op != irFrameSlot and
		inst.op != irFrameAddr

# the blocks from the one the arms jump to back to the top: each but the last ends in a jump to
# the next, the last in a branch to the top or out of the loop; their instructions few and
# copyable (none when the way is another)
fn irWayBack(f IrFn, top i64, inLoop i64[]) i64[]?:
	n = f.blocks[top].insts.len
	sw = f.switches[f.blocks[top].insts[n - 1].imm]
	first = try f.irJumpEnd0(sw.targets[0], inLoop)
	way = [first]
	written = 0
	loop irTailLength:
		b = way[len - 1]
		insts = f.blocks[b].insts
		if insts.isEmpty or b == top or b not in inLoop: return none
		written += insts.len - 1
		if written > irTailLength or insts[..len - 1].any(not .irDispatchCopyable()): return none
		last = insts[len - 1]
		if last.op == irBranch: return way if last.target == top or last.other == top else none
		if last.op != irJmp: return none
		way.push(last.target)
	none

# where the first arm ends: the block its jump goes to (each arm's is the same way back)
fn irJumpEnd0(f IrFn, arm i64, inLoop i64[]) i64?:
	insts = f.blocks[arm].insts
	if insts.isEmpty or insts[len - 1].op != irJmp: return none
	t = insts[len - 1].target
	t if t in inLoop else none

# whether block b ends in a jump to block to
fn irJumpsTo(f IrFn, b i64, to i64):
	insts = f.blocks[b].insts
	not insts.isEmpty and insts[len - 1].op == irJmp and insts[len - 1].target == to

# the instructions from block b's closing jump on to a branch, through blocks that end in a jump
# (none in other loops than b, a loop's top or the block before one); empty when there is no
# such short run
fn irTailRun(f IrFn, b i64, loopsOf i64[,]):
	run = []
	written = 0   # the run's instructions that write code (markers write none)
	at = f.blocks[b].insts[len - 1].target
	loop irTailLength + 2:
		insts = f.blocks[at].insts
		if at == b or f.blocks[at].loopTop or loopsOf[at] != loopsOf[b] or
			f.loops.any(.pre == at) or insts.isEmpty:
			return []
		last = insts[len - 1]
		if last.op != irBranch and last.op != irJmp or
			written + insts.count(not irIsMarker(.op)) - (1 if last.op == irJmp else 0) >
			irTailLength:
			return []
		for k in 0..insts.len - 1:
			run.push(insts[k].copy())
		written = run.count(not irIsMarker(.op))
		if last.op == irBranch:
			run.push(last.copy())
			return run
		at = last.target
	[]

# each jump's and branch's target past the blocks that only jump on (in the same loops as the
# jump, none a loop's top or the block before one)
fn irThreadJumps(mut f IrFn):
	loopsOf = f.irLoopsOf()
	pres = f.loops.map(.pre)
	for b in 0..f.blocks.len:
		n = f.blocks[b].insts.len
		if n == 0: continue
		alias last = f.blocks[b].insts[n - 1]
		if last.op in [irJmp, irBranch, irBranchBit]:
			last.target = f.irJumpEnd(last.target, loopsOf, b, pres)
			if last.op != irJmp:
				last.other = f.irJumpEnd(last.other, loopsOf, b, pres)
		elif last.op == irSwitch:
			last.other = f.irJumpEnd(last.other, loopsOf, b, pres)
			cases = f.switches[last.imm].targets.map(f.irJumpEnd(it, loopsOf, b, pres))
			f.switches[last.imm].targets = cases

# where a jump from block b to m lands past the blocks that only jump on
fn irJumpEnd(f IrFn, m i64, loopsOf i64[,], b i64, pres i64[]):
	at = m
	loop 8:
		insts = f.blocks[at].insts
		if insts.len != 1 or insts[0].op != irJmp or f.blocks[at].loopTop or at in pres or
			insts[0].target == at or loopsOf[at] != loopsOf[b] or
			loopsOf[insts[0].target] != loopsOf[b]:
			return at
		at = insts[0].target
	at

# whether a run's closing branch is decided when the run follows block b: its operands known
# from the constants b sets (or those set once), through the run's copies and operations on them
fn irFoldsAfter(f IrFn, b i64, run IrInst[], consts i64?[]):
	known {i64: i64} = {}
	for inst in f.blocks[b].insts:
		if inst.dst >= 0:
			if inst.op == irConst:
				known[inst.dst] = inst.imm
			else:
				known.remove(inst.dst)
	for inst in run:
		if inst.op == irBranch:
			return irKnownAt(known, consts, inst.a) != none and
				irKnownAt(known, consts, inst.b) != none
		if inst.dst >= 0:
			a = irKnownAt(known, consts, inst.a)
			value i64? = inst.imm if inst.op == irConst
				else a if inst.op == irCopy
				else inst.irFolded(a, irKnownAt(known, consts, inst.b)) if irPureOp(inst.op)
				else none
			if value is v:
				known[inst.dst] = v
			else:
				known.remove(inst.dst)
	false

# vreg v's constant where known says (or set once), none for no vreg
fn irKnownAt(known {i64: i64}, consts i64?[], v i64) i64?:
	if v < 0: return none
	if known.get(v) is x: return x
	consts[v]

# a branch whose operands are constants known in its block (set there, or assigned once)
# becomes a jump, an operation on them its constant
fn irBranchFold(mut f IrFn):
	global = f.irFacts().consts
	known = global.copy()
	setHere i64[] = []   # the vregs the block set in known, put back before the next block
	for bi in 0..f.blocks.len:
		for v in setHere:
			known[v] = global[v]
		setHere.clear()
		for ii in 0..f.blocks[bi].insts.len:
			alias inst = f.blocks[bi].insts[ii]
			op = inst.op
			dst = inst.dst
			line = inst.line
			col = inst.col
			if op == irBranch and known[inst.a] is x and known[inst.b] is y:
				taken = irFloatHolds(inst.cond, x, y) if f.classes[inst.a] == irFloat
					else irIntHolds(inst.cond, inst.uns, x, y)
				target = inst.target if taken else inst.other
				f.blocks[bi].insts[ii] = IrInst(op = irJmp, target, line, col)
			elif op == irSwitch and known[inst.a] is x:
				k = f.switches[inst.imm].values.findIndex(it == x) ?? -1
				target = f.switches[inst.imm].targets[k] if k >= 0 else inst.other
				f.blocks[bi].insts[ii] = IrInst(op = irJmp, target, line, col)
			elif dst >= 0:
				a = known[inst.a] if inst.a >= 0 else none
				b = known[inst.b] if inst.b >= 0 else none
				setHere.push(dst)
				if op == irConst:
					known[dst] = inst.imm
				elif op == irCopy:
					known[dst] = known[inst.a]
				elif irPureOp(op) and inst.irFolded(a, b) is value:
					f.blocks[bi].insts[ii] = IrInst(op = irConst, dst, imm = value, line, col)
					known[dst] = value
				else:
					if b is y and irIdentity(op, y) and not inst.irIs32():
						src = inst.a
						f.blocks[bi].insts[ii] = IrInst(op = irCopy, dst, a = src, line, col)
					known[dst] = none

fn irIntHolds(cond i64, uns bool, x i64, y i64):
	a, b = (x ^ (1 << 63), y ^ (1 << 63)) if uns else (x, y)   # unsigned order as signed
	a == b if cond == irEq
		else a != b if cond == irNe
		else a < b if cond == irLt
		else a <= b if cond == irLe
		else a > b if cond == irGt
		else a >= b

fn irFloatHolds(cond i64, x i64, y i64):
	a = f64.fromBits(u64(x))
	b = f64.fromBits(u64(y))
	a == b if cond == irEq
		else a != b if cond == irNe
		else a < b if cond == irLt
		else a <= b if cond == irLe
		else a > b if cond == irGt
		else a >= b

# Each loop's instructions that compute the same every time (pure, their operands set outside
# the loop, their result assigned only there) moved to the end of the block before the loop:
# a list's length and items when nothing in the loop may write them (irMayWrite), a pure
# function's call that never stops, never an element (its check stays in the loop) nor a division
# (it may fail). A loop entered other than from its block before keeps its instructions: a
# generator's loop, whose turn's blocks the yields before the loop run too.
fn irHoist(mut f IrFn):
	defs = f.irFacts().defs
	inside = fill(f.classes.len, -1)   # the loop whose walk last met an assignment of each vreg
	constIn = fill(f.classes.len, -1)   # the loop a constant is made in
	constValue = zeros(f.classes.len)
	# a frame slot's address: an owner's, whose uses the ownership check places (never hoisted
	# through a constant made in the loop)
	slot = fill(f.classes.len, false)
	for b in f.blocks:
		for inst in b.insts:
			if inst.dst >= 0 and (inst.op == irFrameSlot or inst.op == irFrameAddr):
				slot[inst.dst] = true
	preds i64[,] = []
	loop f.blocks.len:
		preds.push([])
	for b in 0..f.blocks.len:
		for s in f.irBlockSuccessors(b):
			preds[s].push(b)
	member = fill(f.blocks.len, -1)   # the loop being walked, for its blocks
	at = f.irBases(defs)
	for li in 0..f.loops.len:
		blocks = f.loops[li].blocks.copy()
		pre = f.loops[li].pre
		for b in blocks:
			member[b] = li
		if blocks.any(preds[it].any(member[it] != li and it != pre)): continue
		writers = []   # what may write a header
		for b in blocks:
			for inst in f.blocks[b].insts:
				if inst.dst >= 0:
					inside[inst.dst] = li
					if inst.op == irConst and defs[inst.dst] == 1:
						constIn[inst.dst] = li
						constValue[inst.dst] = inst.imm
				if inst.irWritesHeader(): writers.push(inst.copy())
		moved = []
		for b in blocks:
			any = false
			for k in 0..f.blocks[b].insts.len:
				alias inst = f.blocks[b].insts[k]
				invariant = inst.irPure() and inst.op != irConst and inst.op != irParam and
					inst.dst >= 0 and defs[inst.dst] == 1 and
					not inst.irReads().any(inside[it] == li and constIn[it] != li) and
					not inst.args.any(inside[it] == li) and
					not (inst.irReads().any(inside[it] == li) and inst.irReads().any(slot[it]))
				if invariant and (inst.op != irLoad or inst.header and
						(inst.steady or not writers.any(.irMayWrite(inst, at, defs)))):
					inside[inst.dst] = -1
					out = inst.copy()
					f.irConstantsBefore(out, constIn, constValue, li, moved)
					while defs.len < f.classes.len:   # the constants made again, each once
						defs.push(1)
						slot.push(false)
						inside.push(-1)
						constIn.push(-1)
						constValue.push(0)
					moved.push(out)
					f.irTakeOut(b, k)
					any = true
			if any:
				f.irDropTakenOut(b)
		if not moved.isEmpty:
			f.irBeforeEnd(pre, move moved)

# each vreg's address as a base and a displacement: the vreg a chain of additions of constants
# (each assigned once) starts from, and their sum; the vreg itself and 0 for the rest
type IrBases:
	base i64[]
	disp i64[]

fn irBases(f IrFn, defs i64[]):
	n = f.classes.len
	known = fill(n, false)
	value = zeros(n)
	for b in f.blocks:
		for inst in b.insts:
			if inst.op == irConst and inst.dst >= 0 and defs[inst.dst] == 1:
				known[inst.dst] = true
				value[inst.dst] = inst.imm
	base = (0..n).map(it)
	disp = zeros(n)
	for b in f.blocks:
		for inst in b.insts:
			if inst.op == irAdd and not inst.trap and inst.dst >= 0 and defs[inst.dst] == 1 and
				inst.b >= 0 and known[inst.b]:
				base[inst.dst] = inst.a
				disp[inst.dst] = value[inst.b]
	for v in 0..n:
		steps = 0   # (a chain that reads itself, assigned once in a loop, ends somewhere)
		while base[base[v]] != base[v] and steps < 64:
			disp[v] += disp[base[v]]
			base[v] = base[base[v]]
			steps += 1
	IrBases(base, disp)

# Whether w may write the header word load reads: anything that writes memory may, but a store,
# an update or a list's growth (irGrowKeys: its header's three words) at a known displacement from
# the base of load's address (assigned once) that misses the word.
fn irMayWrite(w IrInst, load IrInst, at IrBases, defs i64[]):
	addr = w.a
	from = w.imm
	size = w.size
	if w.op == irCall and w.key in irGrowKeys and not w.args.isEmpty:
		addr = w.args[0]
		from = 0
		size = 24
	elif w.op != irStore and w.op != irUpdate or w.b >= 0:
		return true
	n = at.base.len   # (the constants hoisting makes again are past it)
	if addr < 0 or addr >= n or load.a < 0 or load.a >= n or load.b >= 0: return true
	base = at.base[addr]
	if base != at.base[load.a] or defs[base] != 1: return true
	lo = at.disp[addr] + from
	word = at.disp[load.a] + load.imm
	lo < word + load.size and word < lo + size

# instructions put at the end of block b, before its closing jump
fn irBeforeEnd(mut f IrFn, b i64, move insts IrInst[]):
	last = f.blocks[b].insts.pop()
	f.blocks[b].insts.extend(insts)
	if last is t:
		f.blocks[b].insts.push(t.copy())

# the constants made in loop li that inst reads, made again (as vregs of their own) in moved,
# before inst where it is moved out of the loop
fn irConstantsBefore(
	mut f IrFn,
	mut inst IrInst,
	constIn i64[],
	constValue i64[],
	li i64,
	mut moved IrInst[]
):
	for slot in 0..4:
		v = inst.irSlotVreg(slot)
		if v < 0 or v >= constIn.len or constIn[v] != li: continue
		w = f.irVreg(f.classes[v])
		moved.push(IrInst(op = irConst, dst = w, imm = constValue[v]))
		inst.irSetSlotVreg(slot, w)

# The constants a loop reads that cost an instruction or more at each read, put in a register
# before the loop instead, one register a value however many vregs name it: one it shifts by a
# register (`1 << k`: x64's shift by a register takes no immediate), and one written in more than
# one instruction (irLongConstant), but where the backend needs it as a constant (irHeldSlots);
# and a shuffle's indices the loop does not assign, cleared once (irvecmasks.zap)
fn irHeldConstants(mut f IrFn, arm bool):
	consts = f.irFacts().consts
	preds i64[,] = []
	loop f.blocks.len:
		preds.push([])
	for b in 0..f.blocks.len:
		for s in f.irBlockSuccessors(b):
			preds[s].push(b)
	# the outer loops first: what one holds, the loops inside it read as held
	for li in (0..f.loops.len).sortedBy(-f.loops[it].blocks.len):
		pre = f.loops[li].pre
		inLoop = f.loops[li].blocks
		if inLoop.any(preds[it].any(it != pre and it not in inLoop)): continue   # entered elsewhere too
		heldInts {i64: i64} = {}   # by an integer's value, the vreg holding it through the loop
		heldFloats {i64: i64} = {}   # by a float's bits
		cleared {i64: i64} = {}   # by a shuffle's indices, the vreg holding them cleared
		assigned = fill(f.classes.len, false)
		for b in inLoop:
			for inst in f.blocks[b].insts:
				if inst.dst >= 0: assigned[inst.dst] = true
		made = []
		for b in f.loops[li].blocks.copy():
			for k in 0..f.blocks[b].insts.len:
				if f.blocks[b].insts[k].irUnclearedShuffle(assigned):
					indices = f.blocks[b].insts[k].b
					if cleared.get(indices) == none:
						cleared[indices] = f.irClearedIndices(
							indices,
							(f.blocks[b].insts[k].imm >> 5) & 1,
							made
						)
					f.blocks[b].insts[k].b = cleared.get(indices) ?? indices
					f.blocks[b].insts[k].uns = true
				for slot in f.blocks[b].insts[k].irHeldSlots(consts, f.classes, arm):
					v = f.blocks[b].insts[k].irSlotVreg(slot)
					alias held = heldInts if f.classes[v] == irInt else heldFloats
					c = consts[v] ?? continue
					if held.get(c) == none:
						w = f.irVreg(f.classes[v])
						held[c] = w
						made.push(IrInst(op = irCopy, dst = w, a = v))
					f.blocks[b].insts[k].irSetSlotVreg(slot, held.get(c) ?? v)
		if not made.isEmpty:
			f.irBeforeEnd(pre, move made)

# the operands of inst (0 a, 1 b, 2 c, 3 d, 4 on its args) a loop holds in a register: an integer
# constant shifted by a register, or one written in more than one instruction (irLongConstant)
# other than a divisor, a shift's count or a bit's number, which the backend writes as
# immediates; on AArch64 a float written in more than one (a64FloatLong: x64 reads it from the
# data as an operand)
fn irHeldSlots(inst IrInst, consts i64?[], classes i64[], arm bool):
	shift = inst.op == irShl or inst.op == irShr
	known = consts.len   # (the vregs made here hold no constant)
	slots = []
	for slot in 0..(4 + inst.args.len):
		v = inst.irSlotVreg(slot)
		if v < 0 or v >= known or (slot == 1 or slot == 3) and not irReadsBD(inst.op): continue
		c = consts[v] ?? continue
		if classes[v] == irFloat and arm and a64FloatLong(c):
			slots.push(slot)
		if classes[v] != irInt: continue
		count = inst.b
		if shift and slot == 0 and count >= 0 and (count >= known or consts[count] == none) or
			irLongConstant(c, arm) and
			not (slot == 1 and inst.op in [irDiv, irRem, irShl, irShr, irRotate, irBranchBit]):
			slots.push(slot)
	slots

# whether the integer constant c is written in more than one instruction: past 32 bits on x64
# (movabs), a movz and movks on AArch64 (a64MovImmLength)
fn irLongConstant(c i64, arm bool):
	a64MovImmLength(c) > 1 if arm else c < -0x8000_0000 or c > 0x7FFF_FFFF

# inst's operand slot (0 a, 1 b, 2 c, 3 d, then its args)
fn irSlotVreg(inst IrInst, slot i64):
	inst.a if slot == 0 else inst.b if slot == 1 else inst.c if slot == 2 else inst.d if slot == 3
		else inst.args[slot - 4]

fn irSetSlotVreg(mut inst IrInst, slot i64, v i64):
	if slot == 0: inst.a = v
	elif slot == 1: inst.b = v
	elif slot == 2: inst.c = v
	elif slot == 3: inst.d = v
	else: inst.args[slot - 4] = v
