# A function's frame (its slots, below where rbp would be: irX64.zap's irDisp places them from
# rsp; the stubs' prologue on rbp), its variables and its parameters. A parameter's slot on the
# stack: 8 bytes for scalars and borrowed aggregates, the whole value for `move`. A function
# called only by name (the program's or the runtime's), with one to four parameters of one word
# that are not floats and a result in rax, takes its arguments in rcx, rdx, r8 and r9 instead of
# on the stack: the caller loads them last, the callee stores them in slots of its frame and a
# parameter the body keeps in a register is moved there directly.

alias nodes = g.c.nodes
alias kidIds = g.c.kidIds
alias vars = g.f.vars

fn allocSlot(mut g Gen, size i64) i64:
	g.f.takeSlot(size)

# a frame slot of size bytes (8 at least, a multiple of 8) taken in the function's frame: its offset
fn takeSlot(mut s FnState, size i64):
	n = size
	if n < 8:
		n = 8
	n = (n + 7) / 8 * 8
	s.frameSize += n
	if s.frameSize > s.maxFrame:
		s.maxFrame = s.frameSize
	-s.frameSize

# The state of the function being generated: its variables, its frame, where it returns, the
# loops and scopes open, its temporaries and the registers it caches; a lambda's body sets the
# enclosing one aside and gets one of its own.
type FnState:
	vars LocalVar[]   # the function's variables, the first nvars in use
	nvars i64
	frameSize i64   # bytes of slots in use
	maxFrame i64
	frameFixPos i64
	retLabel i64
	inMethod bool
	implType TypeId?
	curFields NodeId?   # struct declaration whose fields are in scope through `this`
	cached CachedVar[]   # scalar locals held in registers for the loops being generated
# are known (no placeholder, no jump over unused saves)
	avxUsed bool   # this function emitted a 256-bit instruction: its epilogue runs vzeroupper
	failSites FailSite[]   # the checks that may fail, each to its own exit after the function
	minusOnes i64[] = []   # the narrow divisions' cases of a divisor -1: its label and the one back, in pairs (irEmitDivide32)
	body NodeId? = none   # the function's body
	area bool = false   # a function of the intermediate form is being emitted: rsp stays put
#   through its body, a call's argument words go to the area at the bottom of its frame
	frameAlloc i64 = 0   # its frame: the bytes its prologue takes below the registers it pushes
	framePushed i64 = 0   #   and the bytes of those
	framed bool = false   # the code being emitted runs with that frame made
	switchTables i64[,] = []   # the jump tables to place after the function: each its label, then
#   the label of each entry

# A check that may fail (an index out of bounds, a division by zero): its own exit, placed
# after the function's code, calls the shared failure stub, so the return address it leaves
# says which expression failed.
type FailSite:
	label i64
	stub i64
	line i64
	col i64
	file i64
	framed bool = true   # the check runs with the frame made (else its exit is a leaf's)

# a fresh state for a function (a method of implType, -1 none, its fields those of curFields)
# returning ret
fn newFnState(implType TypeId?, curFields NodeId?, ret TypeId):
	FnState(
		vars = [],
		nvars = 0,
		frameSize = 0,
		maxFrame = 0,
		frameFixPos = 0,
		retLabel = -1,
		inMethod = implType != none,
		implType,
		curFields,
		avxUsed = false,
		cached = [],
		failSites = []
	)

# A variable of the function being generated: its name (the frame's own), its frame slot, its
# type, whether the slot holds the address of the value (borrowed aggregate parameters, this),
# the frame slot of its drop flag (owned values; 0 never dropped) and the literal node an
# inlined parameter stands for (-1: a real slot).
type LocalVar:
	name str
	disp i64
	t i64
	isPtr bool
	dropFlag i64
	literal NodeId?
	fixedLen i64 = -1   # a list whose length nothing in the function changes: that length
	rangeLo i64 = 0   # an integer never rebound: the values it may have (none when hi < lo)
	rangeHi i64 = -1

# the prologue of a generated function: rbp, then rbx and r13..r15 saved (the registers the
# bodies keep their addresses in across calls)
fn genHelperPrologue(mut g Gen, label i64):
	g.a.asmPlace(label)
	g.a.framePrologue()
	g.a.em1(0x53)   # push rbx
	g.a.em2(0x41, 0x55)   # push r13
	g.a.em2(0x41, 0x56)   # push r14
	g.a.em2(0x41, 0x57)   # push r15

fn genHelperEpilogue(mut g Gen):
	g.a.em2(0x41, 0x5F)   # pop r15
	g.a.em2(0x41, 0x5E)   # pop r14
	g.a.em2(0x41, 0x5D)   # pop r13
	g.a.em1(0x5B)   # pop rbx
	g.a.em1(0x5D)   # pop rbp
	g.a.em1(0xC3)   # ret

fn findVar(g Gen, name str):
	i = g.f.nvars - 1
	while i >= g.varFloor:
		if vars[i].name == name: return i
		i -= 1
	-1

fn paramIsPtr(g Gen, pt TypeId, mode i64):
	not g.c.isScalar(pt) and mode != modeMove

fn paramSlot(mut g Gen, pt TypeId, mode i64) i64:
	if g.paramIsPtr(pt, mode) or g.c.isScalar(pt): return 8
	g.c.slotSize(pt)

fn emitPrologue(mut g Gen):
	g.a.framePrologue()
	g.a.em3(0x48, 0x81, 0xEC)
	g.f.frameFixPos = g.a.code.len
	g.a.emit32(0)

fn regArgRegs():
	[1, 2, 8, 9]

# word k (0 the first, the deepest) of a call's n argument words, from register r: pushed, or
# written to the area at [rsp] when the function's rsp stays put (g.f.area)
fn argWord(mut g Gen, r i64, k i64, n i64):
	if g.f.area:
		g.a.memOp(true, 0x89, -1, r, 4, -1, 8 * (n - 1 - k))   # mov [rsp+...], r
		return
	if r >= 8:
		g.a.em1(0x41)
	g.a.em1(0x50 | (r & 7))   # push r

# after a call that took n argument words: the pushed ones taken back
fn argsTaken(mut g Gen, n i64):
	if not g.f.area:
		g.a.addRsp(8 * n)

# rsi and rdi kept around code that uses them (rep movsb): pushed and popped, or in the area's
# first two words when rsp stays put
fn keepRsiRdi(mut g Gen, restore bool):
	if g.f.area:
		g.a.memOp(true, 0x8B if restore else 0x89, -1, 6, 4, -1, 0)   # rsi <-> [rsp]
		g.a.memOp(true, 0x8B if restore else 0x89, -1, 7, 4, -1, 8)   # rdi <-> [rsp+8]
	elif restore:
		g.a.em2(0x5F, 0x5E)   # pop rdi, rsi
	else:
		g.a.em2(0x56, 0x57)   # push rsi, rdi

# the names of the functions some code uses as a value (a callback, a closure): the kept stages
# name theirs apart (keptBodies.zap)
fn noteFnValues(mut g Gen):
	for name in waitingBodies.valueNames:
		g.fnValueNames[name.copy()] = true
	for i in waitingBodies.nodes..g.c.nodes.len:
		if nodes[i].kind == nIdent and nodes[i].hasFlag(flagFnRef):
			g.fnValueNames[nodes[i].text.copy()] = true   # the map keeps a key of its own

# whether a call of fnd takes Zap's own convention (irArgPlan)
fn takesRegArgs(mut g Gen, maybeFnd NodeId?, method bool, selfType TypeId? = none):
	g.irArgPlan(maybeFnd, method, selfType) != none

# Zap's own convention for a call of fnd (a method's receiver, of type selfType, first): for the
# receiver and each parameter, whether it is a read small aggregate spread over the registers as
# its leaves (irSpreadClasses: when they all fit in those its class has left), else one word (a
# scalar, an address). The words and leaves take the integer registers (rcx, rdx, r8, r9; x0..x3)
# and the float ones (xmm0..xmm5; d0..d5) in order, the rest the stack (irArgPlaces); the result
# comes in registers (a scalar's in rax, x0; irResultClasses). None: every word on the stack, an
# aggregate by its address and an aggregate result through a hidden pointer (spec 14.2).
fn irArgPlan(mut g Gen, maybeFnd NodeId?, method bool, selfType TypeId? = none) bool[]?:
	fnd = try maybeFnd
	# the declaration is read through g at each use: resolveType changes g.c
	if nodes[fnd].kind != nFnDecl or nodes[fnd].hasFlag(flagExtern): return none
	n = nodes[fnd].kids(kidIds).len
	scalar = g.c.isScalar(g.c.fnRetType(fnd))
	if (n == 0 and not method and scalar) or method and nodes[fnd].text == "drop" or
		not scalar and g.irResultClasses(g.c.fnRetType(fnd)) == none or
		nodes[fnd].text in g.fnValueNames:
		return none
	left = [irArgInts, irArgFloats]   # the registers each class has left
	plan = []
	if method:
		plan.push(irTakeRegs(left, g.irSelfSpread(fnd, selfType), irInt))
	for i in 0..n:
		p = nodes[fnd].kids(kidIds)[i]
		pt = g.c.resolveType(nodes[p].types(kidIds)[0])
		mode = nodes[p].ival
		if g.irSpreads(pt, mode) == none and
			(g.paramSlot(pt, mode) != 8 or not g.c.isScalar(pt) and mode == modeMove):
			return none
		word = irFloat if g.c.isScalar(pt) and g.tyK(pt) == tFloat else irInt
		plan.push(irTakeRegs(left, g.irSpreads(pt, mode), word))
	plan

irArgInts = 4
irArgFloats = 6

# whether leaves (none: the value is one word of class word) fit in the registers left, taken
# from them; else the word takes one, when its class has one left
fn irTakeRegs(mut left i64[], leaves i64[]?, word i64):
	if leaves is spread:
		ints = spread.count(it == irInt)
		floats = spread.len - ints
		if ints <= left[0] and floats <= left[1]:
			left[0] -= ints
			left[1] -= floats
			return true
	k = 1 if word == irFloat else 0
	left[k] = (left[k] - 1).max(0)
	false

# whether the receiver (method) or the parameter at of a plan is spread as its leaves
fn irSpreadIn(maybePlan bool[]?, at i64):
	if maybePlan is plan: return plan[at]
	false

# the classes of the leaves a read value of type t is spread over (a struct, a tuple or an
# optional of up to four numbers that owns nothing), or none: passed by its address
fn irSpreadClasses(mut g Gen, t TypeId) i64[]?:
	if not g.irLentAsCopy(t) or g.isOwningType(t): return none
	leaves = g.irLeaves(t, 0)
	if leaves.len > 4 or leaves.any(g.irIsNicheTag(.t) or g.irClassOf(.t) not in [irInt, irFloat]):
		return none
	leaves.map(g.irClassOf(.t))

# the same for a parameter of mode mode: only one the callee reads
fn irSpreads(mut g Gen, pt TypeId, mode i64) i64[]?:
	if mode != modeRead: return none
	g.irSpreadClasses(pt)

# the classes of the leaves a method's receiver of type self is spread over (one the method only
# reads), or none: passed by its address
fn irSelfSpread(mut g Gen, fnd NodeId, selfType TypeId?) i64[]?:
	t = try selfType
	if nodes[fnd].hasFlag(flagMut): return none
	g.irSpreadClasses(t)

# the classes of the leaves a result of type rt comes back in, in registers (two to four, at most
# two integers: rax and rdx, x0 and x1; the floats in xmm0..xmm3, v0..v3), or none
fn irResultClasses(mut g Gen, rt TypeId) i64[]?:
	if g.c.isScalar(rt): return none
	classes = try g.irSpreadClasses(rt)
	if classes.len < 2 or classes.count(it == irInt) > 2: return none
	classes

# each argument's register among those of its class (irRegIndexes), -1 past the class's registers:
# on the stack, those in order after the others
fn irArgPlaces(classes i64[]):
	at = irRegIndexes(classes)
	for i, c in classes:
		if at[i] >= (irArgFloats if c == irFloat else irArgInts): at[i] = -1
	at

# each value's register among those of its class, in order (the integers' and the floats' counted
# apart)
fn irRegIndexes(classes i64[]):
	seen = [0, 0]
	out = []
	for c in classes:
		k = 1 if c == irFloat else 0
		out.push(seen[k])
		seen[k] += 1
	out
