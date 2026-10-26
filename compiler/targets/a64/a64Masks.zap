# The byte masks of 16-byte vectors on AArch64 as nibble masks: NEON has no vpmovmskb, and a bit a
# byte costs a weighed sum (a64EmitVecMask), where `shrn #4; fmov` gives four bits a byte. A mask
# takes that shape when every value of its vregs comes from such masks (or 0) through copy, and,
# or, xor, and every use reads it in a way the shape keeps: a test against 0, trailingZeros (>> 2,
# where a test proved it not 0), bitCount, and `m & (m - 1)`. A web that clears its lowest lane so
# keeps one bit a byte (the nibble's lowest, so `m - 1` never overflows: irVecMask cond 2), the
# others all four (cond 1).

# the kinds of a vreg: a mask, a mask less one (only ever and-ed with a mask)
a64NotMask = 0
a64Mask = 1
a64MaskLess = 2

# the masks of f in nibble shape where they can be (above)
fn a64NibbleMasks(mut f IrFn):
	if not f.blocks.any(.insts.any(.op == irVecMask and .imm == 2 and .size == 16)): return
	nv = f.classes.len
	facts = f.irFacts()
	consts = facts.consts
	defs i64[,] = []
	uses i64[,] = []
	loop nv:
		defs.push([])
		uses.push([])
	for b in 0..f.blocks.len:
		for k in 0..f.blocks[b].insts.len:
			s = b << 32 | k
			inst = f.blocks[b].insts[k]
			if inst.dst >= 0: defs[inst.dst].push(s)
			for v in inst.irReads():
				if uses[v].isEmpty or uses[v][uses[v].len - 1] != s: uses[v].push(s)
	kind = fill(nv, a64NotMask)
	for v in 0..nv:
		if f.classes[v] != irInt or defs[v].isEmpty: continue
		kind[v] = a64Mask
		if defs[v].all(s: f.a64At(s).op == irSub): kind[v] = a64MaskLess
	nonZero = f.a64NonZeroUses(facts)
	changed = true
	while changed:
		changed = false
		for v in 0..nv:
			if kind[v] == a64NotMask: continue
			if defs[v].all(s: f.a64MaskDef(kind, consts, f.a64At(s))) and
				uses[v].all(s: f.a64MaskUse(kind, consts, nonZero, s, v)):
				continue
			kind[v] = a64NotMask
			changed = true
	f.a64NibbleRewrite(kind, defs)

# the instruction at site s (block << 32 | index)
fn a64At(f IrFn, s i64) ref IrInst:
	f.blocks[s >> 32].insts[s & 0xFFFF_FFFF]

# whether inst gives its dst a value of its kind
fn a64MaskDef(f IrFn, kind i64[], consts i64?[], inst IrInst) bool:
	if inst.size == 4: return false
	op = inst.op
	if kind[inst.dst] == a64MaskLess:
		return op == irSub and kind[inst.a] == a64Mask and consts[inst.b] == 1
	if op == irVecMask: return inst.imm == 2 and inst.size == 16 and f.a64ComparedBytes(inst.a)
	if op == irConst: return inst.imm == 0
	if op == irCopy: return kind[inst.a] == a64Mask
	if op == irOr or op == irXor: return kind[inst.a] == a64Mask and kind[inst.b] == a64Mask
	op == irAnd and kind[inst.a] != a64NotMask and kind[inst.b] != a64NotMask and
		kind[inst.a] + kind[inst.b] < 2 * a64MaskLess

# whether every value of vector vreg v is a byte comparison's (each byte 0 or 0xFF: pcmpeqb, pcmpgtb)
fn a64ComparedBytes(f IrFn, v i64):
	for b in f.blocks:
		for inst in b.insts:
			if inst.dst == v and not (inst.op == irVecOp and inst.cond == 0 and inst.b >= 0 and
					inst.imm in [0x7405, 0x6405]):
				return false
	true

# whether the instruction at site s reads v, a vreg of its kind, in a way the nibble shape keeps
fn a64MaskUse(f IrFn, kind i64[], consts i64?[], nonZero i64[], s i64, v i64) bool:
	inst = f.a64At(s)
	op = inst.op
	if kind[v] == a64MaskLess: return op == irAnd and kind[inst.dst] == a64Mask
	if op in [irCopy, irOr, irXor, irAnd]: return kind[inst.dst] == a64Mask
	if op == irSub: return kind[inst.dst] == a64MaskLess and inst.b != v
	if op in [irBranch, irSet, irSelect]:
		return (inst.cond == irEq or inst.cond == irNe) and inst.c != v and inst.d != v and
			(inst.a == v and consts[inst.b] == 0 or inst.b == v and consts[inst.a] == 0)
	op == irTzcnt and (inst.imm == 1 or inst.imm == 0 and s in nonZero)

# the sites of the trailingZeros of a vreg known not 0 there: a branch tested it (or the vreg it is a
# copy of, assigned once) against 0 on every way there, and nothing assigned it since
fn a64NonZeroUses(f IrFn, facts IrFacts) i64[]:
	nv = f.classes.len
	known bool[,] = []
	seen = fill(f.blocks.len, false)
	loop f.blocks.len:
		known.push(fill(nv, false))
	seen[0] = true
	sites i64[] = []
	changed = true
	while changed:
		changed = false
		sites = []
		for b in 0..f.blocks.len:
			if not seen[b]: continue
			state = known[b].copy()
			insts = f.blocks[b].insts
			for k in 0..insts.len:
				inst = insts[k]
				if inst.op == irTzcnt and inst.imm == 0 and state.a64Known(facts, inst.a):
					sites.push(b << 32 | k)
				if inst.dst >= 0:
					state[inst.dst] = inst.op == irCopy and state.a64Known(facts, inst.a)
			for t in f.irBlockSuccessors(b):
				way = state.copy()
				if f.a64TestedOn(facts.consts, b, t) is v:
					way[v] = true
					way[facts.roots[v]] = true
				if not seen[t]:
					seen[t] = true
					known[t] = way
					changed = true
				else:
					for v in 0..nv:
						if known[t][v] and not way[v]:
							known[t][v] = false
							changed = true
	sites

# whether vreg v is known not 0 in state
fn a64Known(state bool[], facts IrFacts, v i64):
	state[v] or state[facts.roots[v]]

# the vreg block b's branch to block t proves not 0, if any
fn a64TestedOn(f IrFn, consts i64?[], b i64, t i64) i64?:
	insts = f.blocks[b].insts
	if insts.isEmpty: return none
	x = insts[len - 1]
	if x.op != irBranch or x.target == x.other: return none
	if not (x.cond == irNe and x.target == t or x.cond == irEq and x.other == t): return none
	if consts[x.b] == 0: return x.a
	if consts[x.a] == 0: return x.b
	none

# the masks made nibble masks: each irVecMask's shape by its web's, trailingZeros shifted down two,
# bitCount of four bits a byte too
fn a64NibbleRewrite(mut f IrFn, kind i64[], defs i64[,]):
	web = (0..f.classes.len).map(it)
	for v in 0..kind.len:
		if kind[v] == a64NotMask: continue
		for s in defs[v]:
			inst = f.a64At(s)
			for w in inst.irReads():
				if kind[w] != a64NotMask: web.a64Join(v, w)
	single = fill(kind.len, false)
	for v in 0..kind.len:
		if kind[v] == a64MaskLess: single[web.a64Root(v)] = true
	for b in 0..f.blocks.len:
		out IrInst[] = []
		for inst in f.blocks[b].insts:
			if inst.op == irVecMask and kind[inst.dst] == a64Mask:
				x = inst.copy()
				x.cond = 2 if single[web.a64Root(inst.dst)] else 1
				out.push(x)
			elif inst.op == irTzcnt and kind[inst.a] == a64Mask and
				(inst.imm == 0 or not single[web.a64Root(inst.a)]):
				counted = f.irVreg(irInt)
				two = f.irVreg(irInt)
				x = inst.copy()
				x.dst = counted
				out.push(x)
				out.push(IrInst(op = irConst, dst = two, imm = 2))
				out.push(
					IrInst(op = irShr, dst = inst.dst, a = counted, b = two, imm = 64, uns = true)
				)
			else:
				out.push(inst.copy())
		f.blocks[b].insts = out

# the web vreg v is in (union-find)
fn a64Root(web i64[], v i64) i64:
	r = v
	while web[r] != r:
		r = web[r]
	r

fn a64Join(mut web i64[], v i64, w i64):
	web[web.a64Root(v)] = web.a64Root(w)
