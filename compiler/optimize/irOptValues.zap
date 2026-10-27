# The optimizer's constant folding, copy forwarding and dead code (irOpt.zap).

# operations of constants made constants; true when one was
import fold

fn irFold(mut f IrFn, facts IrFacts, visit bool[]):
	consts = facts.consts
	changed = false
	shifts i64[] = []   # the block's products made shifts: their indexes, then their counts' vregs
	for bi in 0..f.blocks.len:
		if not visit[bi]: continue
		shifts.clear()
		for ii in 0..f.blocks[bi].insts.len:
			inst = f.blocks[bi].insts[ii]
			if inst.op == irConst or inst.dst < 0: continue
			a = consts[inst.a] if inst.a >= 0 else none
			b = consts[inst.b] if inst.b >= 0 else none
			if inst.irFolded(a, b) is value:
				f.blocks[bi].insts[ii] = IrInst(
					op = irConst,
					dst = inst.dst,
					imm = value,
					line = inst.line,
					col = inst.col
				)
				changed = true
			elif (inst.op == irSelect or inst.op == irSet) and a is ca and b is cb and
				f.classes[inst.a] == irInt:
				holds = irIntHolds(inst.cond, inst.uns, ca, cb)
				f.blocks[bi].insts[ii] = IrInst(
					op = irCopy if inst.op == irSelect else irConst,
					dst = inst.dst,
					a = (inst.c if holds else inst.d) if inst.op == irSelect else -1,
					imm = 1 if holds else 0,
					line = inst.line,
					col = inst.col
				)
				changed = true
			elif inst.op == irMul and not inst.trap and
				(irPowerOfTwo(b) >= 1 or irPowerOfTwo(a) >= 1) and
				(inst.size == 8 or irPowerOfTwo(b).max(irPowerOfTwo(a)) < 32):
				# x * 2^k is x << k, k a constant put before it once the block is walked
				k = irPowerOfTwo(b) if irPowerOfTwo(b) >= 1 else irPowerOfTwo(a)
				x = inst.a if irPowerOfTwo(b) >= 1 else inst.b
				kv = f.irVreg(irInt)
				f.blocks[bi].insts[ii] = IrInst(
					op = irShl,
					dst = inst.dst,
					a = x,
					b = kv,
					size = inst.size,
					line = inst.line,
					col = inst.col
				)
				shifts.push(ii)
				shifts.push(kv)
				shifts.push(k)
				changed = true
			elif b is y and irIdentity(inst.op, y) and not inst.irIs32():
				f.blocks[bi].insts[ii] = IrInst(
					op = irCopy,
					dst = inst.dst,
					a = inst.a,
					line = inst.line,
					col = inst.col
				)
				changed = true
		if not shifts.isEmpty:
			out = []
			s = 0
			for ii in 0..f.blocks[bi].insts.len:
				if s < shifts.len and shifts[s] == ii:
					out.push(IrInst(op = irConst, dst = shifts[s + 1], imm = shifts[s + 2]))
					s += 3
				out.push(f.blocks[bi].insts[ii].copy())
			f.blocks[bi].insts = move out
	changed

# k when the constant c is 2^k, else -1
fn irPowerOfTwo(c i64?):
	if c is x and x > 0 and x & (x - 1) == 0: return x.trailingZeros()
	-1

# whether an integer operation with the constant y on its right gives its left operand
fn irIdentity(op i64, y i64):
	(y == 0 and (op in [irAdd, irSub, irOr, irXor, irShl, irShr])) or (y == 1 and op == irMul)

# the constant an operation gives on constant operands, none when it is not one the fold knows
fn irFolded(inst IrInst, a i64?, b i64?) i64?:
	if inst.irIs32():
		wide = inst.copy()
		wide.size = 8
		folded = try wide.irFolded(a, b)
		return folded & 0xFFFF_FFFF
	op = inst.op
	if inst.trap and inst.size == 4 and (op in [irAdd, irSub, irMul]):
		wide = inst.copy()
		wide.size = 8
		folded = try wide.irFolded(a, b)
		return folded if folded >= -2_147_483_648 and folded <= 2_147_483_647 else none
	if a is x:
		if op == irCopy: return x
		if op == irNeg: return none if inst.trap and x == fold.minI64 else i64(0 - u64(x))
		if op == irNot: return ~x
		if op == irFNeg: return x ^ (1 << 63)
		if op == irIntToFloat: return i64(f64(x).toBits())
		if op == irTrunc:
			bits = inst.imm
			low = x & ((1 << bits) - 1)
			return low if inst.uns else (low << (64 - bits)) >> (64 - bits)
		if b is y:
			if op in [irAdd, irSub, irMul]:
				return fold.intChecked(op - irAdd, x, y) if inst.trap
					else fold.intWrapped(op - irAdd, x, y)
			if op == irAnd: return x & y
			if op == irOr: return x | y
			if op == irXor: return x ^ y
			if (op == irShl or op == irShr) and y >= 0 and y < 64:
				return x << y if op == irShl else i64(u64(x) >> y) if inst.uns else x >> y
			if (op == irDiv or op == irRem) and y > 0:
				# (a divisor that may fail, 0 or -1, stays)
				if inst.uns: return i64(u64(x) / u64(y)) if op == irDiv else i64(u64(x) % u64(y))
				return x / y if op == irDiv else x % y
			fx = f64.fromBits(u64(x))
			fy = f64.fromBits(u64(y))
			if op == irFAdd: return i64((fx + fy).toBits())
			if op == irFSub: return i64((fx - fy).toBits())
			if op == irFMul: return i64((fx * fy).toBits())
			if op == irFDiv: return i64((fx / fy).toBits())
	none

# a copy of a vreg assigned once into one assigned once (an inlined body's parameter, its
# result): the two made one vreg, every read of the copy reading the source. True when one was.
fn irForwardCopies(mut f IrFn, facts IrFacts, visit bool[]):
	to = facts.roots
	changed = false
	for bi in 0..f.blocks.len:
		if not visit[bi]: continue
		for ii in 0..f.blocks[bi].insts.len:
			alias inst = f.blocks[bi].insts[ii]
			if inst.op == irCopy and to[inst.dst] != inst.dst: continue   # nothing reads it now
			bd = irReadsBD(inst.op)
			if inst.a >= 0 and to[inst.a] != inst.a:
				inst.a = to[inst.a]
				changed = true
			if inst.b >= 0 and bd and to[inst.b] != inst.b:
				inst.b = to[inst.b]
				changed = true
			if inst.c >= 0 and to[inst.c] != inst.c:
				inst.c = to[inst.c]
				changed = true
			if inst.d >= 0 and bd and to[inst.d] != inst.d:
				inst.d = to[inst.d]
				changed = true
			for ai in 0..inst.args().len:
				v = inst.args()[ai]
				if to[v] != v:
					inst.instPart().args[ai] = to[v]
					changed = true
	changed

# In each block, a read of x after `x = y` (of one class), neither assigned since, reads y (the
# copy then often reads nowhere and goes); an ownership marker keeps its vreg. True when a read
# was changed.
fn irLocalCopies(mut f IrFn, visit bool[]):
	nv = f.classes.len
	from = fill(nv, -1)   # the vreg a vreg was copied from, while both hold
	fromAt = zeros(nv)   # how many times that one was assigned when the copy was made
	assigned = zeros(nv)
	copies i64[] = []   # the vregs given a source in the block
	changed = false
	for bi in 0..f.blocks.len:
		if not visit[bi]: continue   # the counts of assignments are only compared within a block
		for x in copies:
			from[x] = -1
		copies.clear()
		for k in 0..f.blocks[bi].insts.len:
			alias inst = f.blocks[bi].insts[k]
			if not irIsMarker(inst.op):
				bd = irReadsBD(inst.op)
				if inst.a >= 0 and from[inst.a] >= 0 and assigned[from[inst.a]] == fromAt[inst.a]:
					inst.a = from[inst.a]
					changed = true
				if inst.c >= 0 and from[inst.c] >= 0 and assigned[from[inst.c]] == fromAt[inst.c]:
					inst.c = from[inst.c]
					changed = true
				if bd and inst.b >= 0 and from[inst.b] >= 0 and
					assigned[from[inst.b]] == fromAt[inst.b]:
					inst.b = from[inst.b]
					changed = true
				if bd and inst.d >= 0 and from[inst.d] >= 0 and
					assigned[from[inst.d]] == fromAt[inst.d]:
					inst.d = from[inst.d]
					changed = true
				for ai in 0..inst.args().len:
					v = inst.args()[ai]
					if from[v] >= 0 and assigned[from[v]] == fromAt[v]:
						inst.instPart().args[ai] = from[v]
						changed = true
			dst = inst.dst
			if dst >= 0:
				assigned[dst] += 1
				from[dst] = -1
				if inst.op == irCopy and inst.a != dst and f.classes[inst.a] == f.classes[dst]:
					from[dst] = inst.a
					fromAt[dst] = assigned[inst.a]
					copies.push(dst)
	changed

# the pure instructions whose result is not read before it is assigned again or the function
# ends, by the liveness of each block's way out
fn irDropDead(mut f IrFn):
	order = f.irLayout()
	live = f.irLiveness(order, false)
	walk = live.irWalkFor(f.classes.len)
	for b in order:
		walk.irWalkFrom(live, b)
		any = false
		i = f.blocks[b].insts.len - 1
		while i >= 0:
			alias inst = f.blocks[b].insts[i]
			if inst.irPure() and inst.dst >= 0 and not walk.irWalkHas(live, inst.dst):
				f.irTakeOut(b, i)
				any = true
			else:
				if inst.dst >= 0:
					walk.irWalkKill(live, inst.dst)
				for v in inst.irReads():
					walk.irWalkGen(live, v)
			i -= 1
		if any:
			f.irDropTakenOut(b)

# A branch on whether a comparison's 0 or 1, made earlier in the block of integers not assigned
# since, is 0 or not branches on the comparison itself (no setcc, movzx, test). True when one was.
fn irSetBranches(mut f IrFn, facts IrFacts, visit bool[]):
	changed = false
	for bi in 0..f.blocks.len:
		if not visit[bi] or f.blocks[bi].insts.isEmpty: continue
		last = f.blocks[bi].insts.len - 1
		br = f.blocks[bi].insts[last].copy()
		if br.op != irBranch or br.cond != irNe and br.cond != irEq: continue
		if (facts.consts[br.b] ?? 1) != 0: continue
		k = last - 1
		while k >= 0 and f.blocks[bi].insts[k].dst != br.a:
			k -= 1
		if k < 0: continue
		set = f.blocks[bi].insts[k].copy()
		if set.op != irSet or f.classes[set.a] != irInt or
			(k + 1..last).any(
				f.blocks[bi].insts[it].dst == set.a or f.blocks[bi].insts[it].dst == set.b
			):
			continue
		f.blocks[bi].insts[last] = IrInst(
			op = irBranch,
			a = set.a,
			b = set.b,
			cond = set.cond,
			uns = set.uns,
			target = br.target if br.cond == irNe else br.other,
			other = br.other if br.cond == irNe else br.target,
			line = br.line,
			col = br.col
		)
		changed = true
	changed
