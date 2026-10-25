# The backend's intermediate form (TODO.md, performance 14): a function as blocks of
# instructions over virtual registers. A virtual register (vreg) holds one scalar of class irInt
# (an integer, a bool, an address), irFloat (an f64) or irVec (a vector: 16 or 32 bytes, in an
# x/ymm register); it may be assigned in several places (not
# SSA): liveness comes from the flow between blocks. irlower.zap builds it from the checked tree,
# irregs.zap gives each vreg a register or a frame slot, irx64.zap writes the machine code.
# A GPU function (irgpu.zap) is the same form with a type for each vreg, any value of the
# GPU's (a number, a vector, a matrix, a struct, an array, a texture) in one, and its branches'
# and loops' structure kept (merges); irspirv.zap writes SPIR-V from it, irhlsl.zap HLSL.

irInt = 0
irFloat = 1
irVec = 2

# the operations: dst = f(a, b, imm)
irConst = 0   # imm (a float's bits)
irCopy = 1
irAdd = 2
irSub = 3
irMul = 4
irAnd = 5
irOr = 6
irXor = 7
irShl = 8   # a shift's count is checked against the width unless it is a constant
irShr = 9   # logical when uns, arithmetic otherwise
irDiv = 10   # the divisor checked for 0; signed: -1 negates; imm the operands' bits
irRem = 11
irNeg = 12
irNot = 13   # bitwise
irSet = 14   # 1 when a cond b, else 0
irFAdd = 15
irFSub = 16
irFMul = 17
irFDiv = 18
irFNeg = 19
irFSqrt = 20
irIntToFloat = 21
irParam = 22   # on entry: argument register imm (regArgs), else the stack slot imm from the last
irCall = 23   # key(args), dst the result or -1; c the address a non-scalar result is written to
irJmp = 24   # to target
irBranch = 25   # to target when a cond b, else to other
irRet = 26   # a the result or -1; args a small aggregate's leaves past it (in registers)
irFailIf = 27   # the stub imm when a cond b (a check's failure, at line/col/file)
irLoad = 28   # the size bytes at a + b * scale + imm (b -1: none), extended by uns
irStore = 29   # c into the size bytes at a + b * scale + imm
irTrunc = 30   # a wrapped to imm bits, extended by uns (an integer narrower than 64 bits)
irFrameAddr = 31   # the frame's address imm as rbp saw it (irDisp): a moved parameter's words
irUpdate = 32   # the 8 bytes at a + b * scale + imm, op= c (the operation in cond: irAdd, irAnd...)
irSelect = 33   # a cond b ? c : d, integers, no branch (a choice no branch predictor can guess)
irFloatToInt = 34   # the float a truncated (cvttsd2si: 1 << 63 when it does not fit)
irFloatBits = 35   # the float a's bits
irBranchBit = 36   # to target when bit b of a is set (cond irNe) or clear (irEq), else to other
irFrameSlot = 37   # the address of imm bytes of the frame, zeroed when the function (region) starts
irMemCopy = 38   # imm bytes from address b to address a; cond 1: a value's bytes moved (b's emptied)
irDrop = 39   # the value of type ty at address a dropped (what it owns freed): a call
irDeepCopy = 40   # the value of type ty at address b copied deep to address a: a call; cond, a
# copy the program did not write (irown.zap takes the value out of its place instead, or refuses
# it): 1 a value given away, 2 bound mut, 3 taken apart, 4 a loop's element given away, 5 a capture
# of a lambda run once given away (always taken), 6 a field a literal's `..base` gives; key the
# place's text (cond 2 and 3: the binding's name, a tab, the place's)
irDataAddr = 41   # the address of the program's data at offset imm (a literal's bytes)
irCallPtr = 42   # a call through the fn value at address a: its environment ([a+8]) pushed first, then args, then c; code at [a]
irFnAddr = 43   # the address of the function labelled imm, or of the one named key
irBitsToFloat = 44   # the float whose bits are the integer a
irTzcnt = 45   # the trailing zero bits of a (64 when a is 0); imm 1: the bits set in a (popcnt),
# imm 2: its leading zero bits (lzcnt)
irRoundF32 = 46   # the float a rounded to single precision (an f32 travels as the f64 of its value)
irF32Bits = 47   # the bits of the float a as a single
irBitsToF32 = 48   # the float whose single's bits are the integer a
irMemCopyN = 49   # c bytes from address b to address a (the runtime's __memcpy)
irMemSet = 50   # c bytes at address a set to the byte b (the runtime's __memset)
irTlsGet = 51   # the thread's TLS slot a (gs:[a*8 + 0x1480])
irTlsSet = 52   # the thread's TLS slot a set to b
irReturnAddress = 53   # where the function returns to (for walking the callers)
irXadd = 54   # the value at address a before b is added to it, atomically
irCmpxchg = 55   # the value at address a before, which becomes c when it was b, atomically
irBswap = 56   # the bytes of a in the other order: its low imm bits (16, 32; 0 or 64: all), the
# rest zero
irFRoundTo = 57   # the float a rounded to an integer value: imm 1 down, 2 up, 3 toward zero
irVecOp = 58   # an AVX instruction on x/ymm vregs (vectors, floats): imm its encoding (irVecCode), cond
# its form: 0 dst = a op b (b -1: op a), 1 dst = c + a op b (FMA), 2 dst = a, b blended by c; uns
# what is known of an operand's bytes (irvecmasks.zap)
irVecSplat = 59   # the scalar a in every lane: imm the lane's kind (irLaneF32...), size the vector's bytes
irVecMask = 60   # a bit per lane of a, its sign: imm 0 of 4-byte lanes, 1 of 8, 2 of bytes; size a's bytes

# the GPU's (irgpu.zap), on values of any of its types
irMake = 61   # dst = a value of dst's type made of args: a vector's numbers (or shorter vectors), a
# matrix's columns, a struct's fields, an array's elements
irPart = 62   # dst = part imm of a (a vector's component, a matrix's column, a struct's field, an
# array's element), or its part at index b when b >= 0
irSetPart = 63   # part imm of a (or its part at index b when b >= 0) becomes c, in place
irSwizzle = 64   # dst = the components of vector a that key names (x y z w), or the scalar a repeated
irMatMul = 65   # dst = a @ b: a matrix by a matrix or a vector, a vector by a matrix, or two vectors'
# dot product
irConvert = 66   # dst = a as dst's type: numbers component by component, a number spread over a
# vector, a bool from a number (whether it is not zero) and a number from a bool
irBuiltin = 67   # dst = the built-in function key (shader.builtinFunctions' Zap name) of args, the
# value it is a method of first
irTexture = 68   # dst = texture a's read key (sample, sampleLevel, size, compare) of args
irStageIn = 69   # dst = what the stage is given that key names: a parameter, a texture, a storage
# buffer, a value the GPU gives (pixelPosition); its element at index b when b >= 0
irStageOut = 70   # what the stage writes that key names (a compute stage's group memory or storage
# buffer) gets a, or its element at index b when b >= 0
irDiscard = 71   # the pixel left unwritten: its invocation ends
irBarrier = 72   # a compute stage's invocations of a group wait for each other, their writes to the
# group's memory seen by all

# Ownership, stated in the form (irown.zap verifies it after each pass); no code. A value that
# owns memory lives in an owner: a frame slot (or a moved parameter's words) named by vreg a.
# An owner's bytes are zero while it owns nothing (a drop of zero bytes frees nothing): before its
# value is made, and once it is consumed, but where its bytes were moved as they are.
irOwn = 73   # a begins owning a value of type imm: key the local's name ("" a temporary), b the
# vreg of the value's word (a map, a box) or -1; cond 1: its drop is the lowering's (a list a loop
# keeps from turn to turn)
irOwnEnd = 74   # a's value consumed (cond: how, ownDropped...): a owns nothing from here; imm 1:
# a local's value moved by a written `move`; other the node that gives it (or -1)
irSwitch = 75   # to the block of the case a equals (f.switches[imm]), else to other; uns orders
# the cases as unsigned; cond 1: a is always one of the cases (other is never reached)
irRotate = 76   # a's imm bits (8, 16, 32 or 64) turned by b modulo imm: left (cond 0) or right (1)
irNote = 77   # what the program does here, for the ownership check only (taken out after it): kind
# imm (noteBorrow...), the vreg it is about in target, the node it is about in other, key its text
irFence = 81   # no load or store moves across it, nor is a load after it one before it (AArch64's
# dmb; x64 keeps the order of the processor's loads and stores itself: no code, __fence)
irVecLaneOf = 78   # integer lane imm of vector a (in its first 16 bytes): size bytes, extended by uns
irPrefetch = 79   # the memory at address a fetched into the caches ahead of its use: no result, a hint
irMulHigh = 80   # the high 64 bits of the unsigned 128-bit product a * b
irPause = 82   # a spin loop's turn: the processor told it waits (x64's pause, AArch64's yield), so it
# leaves its sibling hyperthread the core; no result, a hint
irCallOut = 83   # dst = the result leaf the call right before it gave in register imm of dst's class
# (a small aggregate's leaves past the first, the call's dst; irResultClasses)

# how an owned value is consumed
ownDropped = 0   # dropped where it is
ownMoved = 1   # its bytes moved to another place
ownGiven = 2   # its word (a map's, a box's) stored in another place
ownReturned = 3   # moved to the function's result
ownMovedAsIs = 4   # its bytes moved to another place and left as they are (never read again)
ownSuspended = 5   # kept, set aside while a walk's turn runs (irOwn again where the walk resumes)
ownCaptured = 6   # moved into a closure that keeps it

# the kinds of irNote
noteBorrow = 1   # a name (key: "name	place	place...") borrows the places while target is live
noteChanged = 2   # a place changed (key: "place	via	param": the borrow it went through, the callee's
# mut parameter it was given to, other the callee's node)
noteReadFrom = 3   # a loop or a pipeline reads a place in place (key: "place	what") until its
noteReadTo = 4   #   noteReadTo of the same target
noteRead = 5   # a place read (key: "place\tvia") while a name lent it for changing (irLower.exclusive)
noteUsed = 6   # target used here (`_ = x`), for the borrows it holds
notePart = 7   # target is the address of the field key of the struct at vreg other: a borrow's
# uses through it read that field alone
noteCallRead = 8   # the call before it reads only these parts of target, a name that borrows (key:
# "name\tat", "$" the whole; reads.zap)

# the kinds of lanes of irVecSplat
irLaneF32 = 0
irLaneI32 = 1
irLaneI64 = 2
irLaneU8 = 3
irLaneF64 = 4

# conditions; uns compares integers as unsigned, a float's class makes it a float comparison
irEq = 0
irNe = 1
irLt = 2
irLe = 3
irGt = 4
irGe = 5

type IrInst:
	op i64
	dst i64 = -1
	a i64 = -1
	b i64 = -1
	c i64 = -1
	d i64 = -1
	imm i64 = 0
	ty TypeId? = none   # irDrop, irDeepCopy: the value's type
	size i64 = 8
	scale i64 = 1
	cond i64 = 0
	uns bool = false
	target i64 = -1
	other i64 = -1
	args i64[] = []
	key str = ""
	regArgs bool = false   # a call's (a parameter's) arguments in rcx, rdx, r8, r9, else on the stack
	header bool = false   # a load or store of a list's length or items (only those stores and calls change them)
	steady bool = false   # a header's load of a list a read parameter holds: nothing changes it while the function runs
	frame bool = false   # a load or store in the frame at imm as rbp saw it (a in no register)
	trap bool = false   # irAdd, irSub, irMul, irNeg: the program stops (failOverflow) when the
# result leaves 64 bits, signed (32 when size is 4: an i32's, its result sign-extended)
	pure i64 = 0   # a call of a pure function (purity.zap's pureCallLevel): 1 made once for the
# same arguments, 2 also never stops: an operation like any other
	line i64 = 0
	col i64 = 0
	foreign bool = false   # put by a body of another file inlined: its errors are said in that file

type IrBlock:
	insts IrInst[]
	loopTop bool = false   # a back edge comes here: placed at a fetch boundary
	cold bool = false   # a rare way (a list's growth): the registers weigh it as seldom run

# a switch's cases: each value (one each) and the block it goes to
type IrSwitch:
	values i64[]
	targets i64[]

# a loop: the block that runs right before it (every way in passes there) and its own blocks
type IrLoop:
	pre i64
	blocks i64[]

# a branch's or a loop's structure, which a GPU's code keeps: the block that branches (a loop's
# first), the block its ways meet in after it, and a loop's continue block (-1 for a branch)
type IrMerge:
	header i64
	merge i64
	cont i64 = -1

type IrFn:
	blocks IrBlock[]
	classes i64[]   # each vreg's class
	cur i64   # the block being filled
	loops IrLoop[]   # inner loops before the loops around them
	merges IrMerge[] = []   # a GPU function's branches and loops
	leafTypes i64[] = []   # as lowered: the type of the value each vreg holds (-1 or past the end:
# not known), read by the ownership check (irown.zap)
	places {i64: str} = {}   # as lowered: by the address of a place's value, the place's text

	switches IrSwitch[] = []   # the cases of its irSwitch terminators
	check IrOwnCheck = IrOwnCheck()   # the ownership verified after each pass (irowntrace.zap)

fn newIrFn():
	IrFn(blocks = [IrBlock(insts = [])], classes = [], cur = 0, loops = [])

fn irVreg(mut f IrFn, class i64):
	f.classes.push(class)
	f.classes.len - 1

# vreg v's leaf type (leafTypes) set
fn irLeafTyped(mut f IrFn, v i64, t i64):
	while f.leafTypes.len <= v:
		f.leafTypes.push(-1)
	f.leafTypes[v] = t

# whether some parameter comes in a float register (xmm0..xmm5: irx64regargs.zap)
fn irFloatRegParams(f IrFn):
	f.blocks[0].insts.any(.op == irParam and .regArgs and f.classes[.dst] != irInt)

# a call's arguments in registers (onStack false) or on the stack, in order: by Zap's convention
# those past their class's registers on the stack (irArgPlaces), else all of them there
fn irCallArgs(f IrFn, call IrInst, onStack bool) i64[]:
	if not call.regArgs: return call.args.copy() if onStack else []

	places = irArgPlaces(call.args.map(f.classes[it]))
	(0..call.args.len).filter((places[it] < 0) == onStack).map(call.args[it])

# the irCallOut instructions right after the call at insts[ii]

fn irCallOutsAt(insts IrInst[], ii i64):
	k = ii + 1
	while k < insts.len and insts[k].op == irCallOut:
		k += 1
	insts[ii + 1..k].copy()

# The parameters read before anything else runs (the frame's zeroing, a spilled value's scratch
# would write over the registers they come in): those of Zap's convention numbered among their
# class's registers in order, those past them (irArgPlaces) on the stack, each a word as the
# register holds it, after the others
fn irParamsFirst(mut f IrFn):
	insts = move f.blocks[0].insts
	params = insts.filter(.op == irParam)
	at = (0..params.len).filter(params[it].regArgs)
	places = irArgPlaces(at.map(f.classes[params[it].dst]))
	stacked = places.count(it < 0)
	for k, i in at:
		params[i].imm = places[k]
		if places[k] < 0:
			stacked -= 1
			params[i].regArgs = false
			params[i].imm = stacked   # the words pushed after it
			params[i].size = 8
	f.blocks[0].insts = params.filter(.regArgs)
	f.blocks[0].insts.extend(params.filter(not .regArgs))
	f.blocks[0].insts.extend(insts.filter(.op != irParam))

fn irBlock(mut f IrFn):
	f.blocks.push(IrBlock(insts = []))
	f.blocks.len - 1

fn irAppend(mut f IrFn, move inst IrInst):
	f.blocks[f.cur].insts.push(inst)

fn isTerminator(op i64):
	op in [irJmp, irBranch, irBranchBit, irSwitch, irRet, irDiscard]

# whether the block being filled already ends (what follows is unreachable)
fn irEnded(f IrFn):
	insts = f.blocks[f.cur].insts
	not insts.isEmpty and isTerminator(insts[len - 1].op)

# filling continues in block b
fn irEnter(mut f IrFn, b i64):
	f.cur = b

fn irJumpTo(mut f IrFn, b i64):
	if not f.irEnded():
		f.irAppend(IrInst(op = irJmp, target = b))

# the block being filled goes on to b, where filling continues
fn irJoin(mut f IrFn, b i64):
	f.irJumpTo(b)
	f.irEnter(b)

# a loop's blocks: the block it starts from, its body, the step continue goes to, the block after it
type IrShell:
	pre i64
	body i64
	cont i64
	end i64

# the blocks of a loop starting from the block being filled
fn irShell(mut f IrFn):
	pre = f.cur
	body = f.irBlock()
	cont = f.irBlock()
	IrShell(pre, body, cont, end = f.irBlock())

# filling continues in the loop's body, a loop's top
fn irEnterBody(mut f IrFn, l IrShell):
	f.blocks[l.body].loopTop = true
	f.irEnter(l.body)

# the blocks of a choice of two ways: yes, no (-1: none, the yes way or end) and where they meet
type IrSplit:
	yes i64
	no i64
	end i64

fn irSplit(mut f IrFn, both bool):
	yes = f.irBlock()
	no = f.irBlock() if both else -1
	IrSplit(yes, no, end = f.irBlock())

# the yes way of s done: filling continues in its no way
fn irElse(mut f IrFn, s IrSplit):
	f.irJumpTo(s.end)
	f.irEnter(s.no)

# the blocks a GPU function's terminator may go to next (it has no switch)
fn irSuccessors(inst IrInst):
	if inst.op == irJmp: return [inst.target]
	if inst.op == irBranch or inst.op == irBranchBit: return [inst.target, inst.other]
	[]

# whether block b ends in no jump: it falls into the block after it
fn irFallsOn(f IrFn, b i64):
	insts = f.blocks[b].insts
	insts.isEmpty or not isTerminator(insts[len - 1].op)

# how many ways block b goes on (a switch's cases and its default, a branch's two, a jump's one,
# the next block's for a block without a terminator); irNextAt gives each, so a walk of the flow
# makes no list
fn irNextCount(f IrFn, b i64):
	if f.irFallsOn(b): return 1 if b + 1 < f.blocks.len else 0
	insts = f.blocks[b].insts
	op = insts[len - 1].op
	1 if op == irJmp
		else 2 if op == irBranch or op == irBranchBit
		else f.switches[insts[len - 1].imm].targets.len + 1 if op == irSwitch
		else 0

# the i-th way on of block b (i below irNextCount): a switch's cases first, its default last
fn irNextAt(f IrFn, b i64, i i64):
	if f.irFallsOn(b): return b + 1
	t = f.blocks[b].insts[len - 1]
	if t.op == irSwitch:
		cases = f.switches[t.imm].targets
		return cases[i] if i < cases.len else t.other
	t.target if i == 0 else t.other

# each block's predecessors, each once, in the blocks' order
fn irPredecessors(f IrFn):
	preds i64[,] = []
	loop f.blocks.len:
		preds.push([])
	for b in 0..f.blocks.len:
		for i in 0..f.irNextCount(b):
			s = f.irNextAt(b, i)
			if preds[s].isEmpty or preds[s][len - 1] != b: preds[s].push(b)
	preds

# the blocks block b may go to next
fn irBlockSuccessors(f IrFn, b i64):
	(0..f.irNextCount(b)).map(f.irNextAt(b, it))

# The vregs an instruction reads, one for each operand that reads one: the one rule of what an
# instruction reads, which every pass and the registers walk (a generator: no list is made).
# A call's b and d are not operands (irReadsBD); a GPU operation's args are, as a call's.
fn irReads(inst IrInst) Seq<i64>:
	for v in inst.args:
		yield v
	if inst.a >= 0: yield inst.a
	if inst.c >= 0: yield inst.c
	if irReadsBD(inst.op):
		if inst.b >= 0: yield inst.b
		if inst.d >= 0: yield inst.d

# whether an operation reads its b and d: all but a call's
fn irReadsBD(op i64):
	op != irCall and op != irCallPtr

# whether inst reads vreg v
fn irReadsVreg(inst IrInst, v i64):
	inst.irReads().any(it == v)

# whether an instruction only computes its dst (dropped when nothing reads it, moved out of a loop)
fn irPure(inst IrInst):
	irPureOp(inst.op) and not inst.trap or inst.op == irCall and inst.pure == 2

# whether an operation only computes its dst, when it does not stop the program on an overflow
fn irPureOp(op i64):
	op != irDiv and op != irRem and op != irCall and op != irCallPtr and op != irMemCopyN and
		op != irMemSet and op != irTlsGet and op != irTlsSet and op != irXadd and
		op != irCmpxchg and op != irStore and op != irUpdate and op != irFailIf and
		op != irMemCopy and op != irDrop and op != irDeepCopy and op != irSetPart and
		op != irStageOut and op != irBarrier and op != irPrefetch and op != irFence and
		op != irPause and op != irCallOut and
		not isTerminator(op) and
		not irIsMarker(op)

# whether an operation only states ownership (irOwn, irOwnEnd): no code, no value
fn irIsMarker(op i64):
	op == irOwn or op == irOwnEnd

# whether the code before insts[at] may go on to it: not past a call that stops the program (the
# form goes on from there as from any call, but a jump there takes no code)
fn irGoesOn(insts IrInst[], at i64):
	k = at - 1
	while k >= 0 and (irIsMarker(insts[k].op) or insts[k].op == irNote):
		k -= 1
	k < 0 or not insts[k].irStops()

# whether inst calls a function that stops the program (fail, exit)
fn irStops(inst IrInst):
	inst.op == irCall and endsProgram(inst.key)

# The panic paths: the blocks that call a function that stops the program, and those every way
# from which leads to one (a test whose ways both fail).
fn irPanicPaths(f IrFn):
	n = f.blocks.len
	panics = (0..n).map(f.blocks[it].insts.any(.irStops()))
	grew = true
	while grew:
		grew = false
		for b in 0..n:
			if not panics[b] and f.irNextCount(b) > 0 and
				(0..f.irNextCount(b)).all(panics[f.irNextAt(b, it)]):
				panics[b] = true
				grew = true
	panics

# The instructions whose results nothing reads, removed until none is left: each vreg's reads
# counted once; a pure assignment of one read nowhere is taken out, which lowers its operands'
# counts, and the assignments of an operand that reaches none are taken out in turn.
fn irPrune(mut f IrFn):
	nv = f.classes.len
	reads = zeros(nv)
	for b in f.blocks:
		for inst in b.insts:
			for v in inst.irReads():
				reads[v] += 1
	# each vreg's pure assignments, by vreg (first[v] to first[v + 1] in sites: block << 32 | index)
	first = zeros(nv + 1)
	nothing = true
	for b in f.blocks:
		for inst in b.insts:
			if inst.dst >= 0 and inst.irPure():
				first[inst.dst + 1] += 1
				if reads[inst.dst] == 0: nothing = false
	if nothing: return
	for v in 0..nv:
		first[v + 1] += first[v]
	next = first.copy()
	sites = zeros(first[nv])
	work = []
	for bi, block in f.blocks:
		for k in 0..block.insts.len:
			dst = block.insts[k].dst
			if dst >= 0 and block.insts[k].irPure():
				sites[next[dst]] = (bi << 32) | k
				next[dst] += 1
				if reads[dst] == 0 and next[dst] == first[dst + 1]: work.push(dst)
	touched = fill(f.blocks.len, false)
	while not work.isEmpty:
		v = work.pop() ?? break
		for i in first[v]..first[v + 1]:
			bi = sites[i] >> 32
			k = sites[i] & 0xFFFF_FFFF
			if f.blocks[bi].insts[k].dst != v: continue   # taken out already
			for u in f.blocks[bi].insts[k].irReads():
				reads[u] -= 1
				if reads[u] == 0 and first[u + 1] > first[u]: work.push(u)
			f.irTakeOut(bi, k)
			touched[bi] = true
	for bi in 0..f.blocks.len:
		if touched[bi]:
			f.irDropTakenOut(bi)
