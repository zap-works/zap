# The lowering of the intrinsics and of one-operand methods (irLower.zap).

alias nodes = g.c.nodes
alias kidIds = g.c.kidIds
alias tys = g.c.types

fn irListType(mut g Gen, e NodeId):
	t = g.ty(e)
	innerOf(tys, t) if g.tyK(t) == tRef else t

# an address the runtime reads or writes raw (`__ld64(p + 8)`): its sums unchecked, since one that
# overflowed would leave the address space and fault at the access all the same
fn irAddressExpr(mut g Gen, mut lw IrLower, e NodeId) i64:
	g.irWrapSums(e)
	g.irExpr(lw, e)

# the + and - at the top of e (not inside a product or a call) marked as wrapping
fn irWrapSums(mut g Gen, e NodeId):
	if nodes[e].kind != nBinary or (nodes[e].ival != binAdd and nodes[e].ival != binSub): return
	nodes[e].flags |= flagWrap
	g.irWrapSums(nodes[e].kids(kidIds)[0])
	if nodes[e].ival == binAdd:
		g.irWrapSums(nodes[e].kids(kidIds)[1])

# The runtime's intrinsics the form knows: loads and stores of 1, 2, 4, 8 bytes, a list's
# address, an element read or written unchecked, an element type's zero and stride.
# an intrinsic or a method that is one instruction on its operands' values (a method's receiver
# first): the operation, its result's class (-1: none) and imm, what its operands must be
type IrOneOp:
	name str
	op i64
	operands i64
	class i64
	imm i64 = 0
	on i64 = irOnAny

irOnAny = 0
irOnFloat = 1   # a float

irOneOps = [
	IrOneOp(name = "__tlsGet", op = irTlsGet, operands = 1, class = irInt),
	IrOneOp(name = "__tlsSet", op = irTlsSet, operands = 2, class = -1),
	IrOneOp(name = "__returnAddress", op = irReturnAddress, operands = 0, class = irInt),
	IrOneOp(name = "__bswap", op = irBswap, operands = 1, class = irInt),
	IrOneOp(name = "__ftoi", op = irFloatToInt, operands = 1, class = irInt, on = irOnFloat),
	IrOneOp(name = "floor", op = irFRoundTo, operands = 1, class = irFloat, imm = 1, on = irOnFloat),
	IrOneOp(name = "ceil", op = irFRoundTo, operands = 1, class = irFloat, imm = 2, on = irOnFloat),
	IrOneOp(name = "trunc", op = irFRoundTo, operands = 1, class = irFloat, imm = 3, on = irOnFloat)
]

# An integer x of w bits counted or turned (intBitMethods but bitCount): trailingZeros (a bit set
# just past the width gives it for 0), leadingZeros (the 64-bit count less the bits above the
# width), rotateLeft and rotateRight by args[0], byteSwap, mulHigh by args[0] (below 64 bits: the
# zero-extended operands' 64-bit product shifted down).
fn irBitMethod(mut g Gen, mut lw IrLower, m str, x i64, w i64, args NodeId[]):
	if m == "trailingZeros":
		a = lw.irDef(irInt, IrInst(op = irOr, a = x, b = lw.irConstOf(irInt, 1 << w))) if w < 64
			else x
		return [lw.irDef(irInt, IrInst(op = irTzcnt, a))]
	if m == "leadingZeros":
		n = lw.irDef(irInt, IrInst(op = irTzcnt, a = x, imm = 2))
		if w == 64: return [n]
		return [lw.irDef(irInt, IrInst(op = irSub, a = n, b = lw.irConstOf(irInt, 64 - w)))]
	if m == "byteSwap":
		if w == 8: return [x]
		return [lw.irDef(irInt, IrInst(op = irBswap, a = x, imm = w))]
	if m == "mulHigh":
		y = g.irExpr(lw, args[0])
		if w == 64: return [lw.irDef(irInt, IrInst(op = irMulHigh, a = x, b = y))]
		p = lw.irDef(irInt, IrInst(op = irMul, a = x, b = y))
		return [lw.irDef(irInt, IrInst(op = irShr, a = p, b = lw.irConstOf(irInt, w), uns = true))]
	count = g.irExpr(lw, args[0])
	[
		lw.irDef(
			irInt,
			IrInst(op = irRotate, a = x, b = count, imm = w, cond = 0 if m == "rotateLeft" else 1)
		)
	]

# bitFieldMethods on x of integer type t: its count bits from bit `from` are (x >> from) & mask,
# a logical shift (a signed x's sign bits lie past the width the bits stay inside), and set they
# are x & ~(mask << from) | (v & mask) << from. A position or count the checker did not see as a
# constant stops the program when the bits leave the width; the result is wrapped to a narrow
# signed t, whose top bit a count of its whole width or a set bit may hold. A place written
# (`s.n = v`, `x.bit(n) = v`, flagInternal) computes v before it reads the place.
fn irBitField(
	mut g Gen,
	mut lw IrLower,
	e NodeId,
	m str,
	obj NodeId,
	t TypeId,
	args NodeId[]
):
	early = m.startsWith("with") and nodes[e].hasFlag(flagInternal)
	v = g.irExpr(lw, args[len - 1]) if early else -1
	x = g.irExpr(lw, obj)
	w = tys[t].bits
	single = m == "bit" or m == "withBit"
	from = g.irExpr(lw, args[0])
	count = lw.irConstOf(irInt, 1) if single else g.irExpr(lw, args[1])
	known = g.isIntLit(args[0]) and (single or g.isIntLit(args[1]))
	if not known:
		g.irBitsInside(lw, from, count, w)
	mask = lw.irConstOf(irInt, 1)
	if not single and g.isIntLit(args[1]):
		n = g.intLitValue(args[1])
		mask = lw.irConstOf(irInt, -1 if n >= 64 else i64(u64.wrap(-1) >> (64 - n)))
	elif not single:
		left = lw.irDef(irInt, IrInst(op = irSub, a = lw.irConstOf(irInt, 64), b = count))
		mask = lw.irDef(
			irInt,
			IrInst(op = irShr, a = lw.irConstOf(irInt, -1), b = left, uns = true)
		)
	if not m.startsWith("with"):
		down = lw.irDef(irInt, IrInst(op = irShr, a = x, b = from, uns = true))
		r = lw.irDef(irInt, IrInst(op = irAnd, a = down, b = mask))
		return [r if m == "bit" else g.irSignedNarrow(lw, r, t)]
	if not early:
		v = g.irExpr(lw, args[len - 1])
	if not single:
		v = lw.irDef(irInt, IrInst(op = irAnd, a = v, b = mask))
	placed = lw.irDef(irInt, IrInst(op = irShl, a = mask, b = from))
	cleared = lw.irDef(
		irInt,
		IrInst(op = irAnd, a = x, b = lw.irDef(irInt, IrInst(op = irNot, a = placed)))
	)
	moved = lw.irDef(irInt, IrInst(op = irShl, a = v, b = from))
	[g.irSignedNarrow(lw, lw.irDef(irInt, IrInst(op = irOr, a = cleared, b = moved)), t)]

# v, within the width of integer type t, wrapped to t when t is signed (an unsigned one holds it)
fn irSignedNarrow(mut g Gen, mut lw IrLower, v i64, t TypeId) i64:
	g.irNarrow(lw, v, t) if tys[t].isSigned else v

# the program stopped (as a shift past the width) unless 0 <= from, 1 <= count and from + count
# <= w, each compared unsigned so a negative one is past them too
fn irBitsInside(mut g Gen, mut lw IrLower, from i64, count i64, w i64):
	less = lw.irDef(irInt, IrInst(op = irSub, a = count, b = lw.irConstOf(irInt, 1)))
	end = lw.irDef(irInt, IrInst(op = irAdd, a = from, b = count))
	g.irFailPast(lw, from, w - 1)
	g.irFailPast(lw, less, w - 1)
	g.irFailPast(lw, end, w)

fn irFailPast(mut g Gen, mut lw IrLower, v i64, most i64):
	lw.irPut(
		IrInst(
			op = irFailIf,
			a = v,
			b = lw.irConstOf(irInt, most),
			cond = irGt,
			uns = true,
			imm = g.failShift
		)
	)

# whether the operands' types are what op takes
fn irOneOpTakes(mut g Gen, op IrOneOp, types TypeId[]):
	if op.on == irOnFloat: return g.irClassOf(types[0]) == irFloat
	true

# op on the values of operands, in order; a float result rounded to t
fn irOneOpOf(mut g Gen, mut lw IrLower, op IrOneOp, operands NodeId[], t TypeId):
	vs = operands.map(g.irExpr(lw, it))
	inst = IrInst(
		op = op.op,
		a = vs[0] if not vs.isEmpty else -1,
		b = vs[1] if vs.len > 1 else -1,
		imm = op.imm
	)
	if op.class < 0:
		lw.irPut(inst)
		return []
	v = lw.irDef(op.class, inst)
	[g.irRounded(lw, v, t)] if op.class == irFloat else [v]

# __bytesAt(b, at, n), b a u8[] or a u8[N] and n a literal: the address of b's n bytes from at,
# checked to lie inside: at + n does not pass the end, nor wrap (at below 2^64 - n, which the
# proofs drop for an index never negative)
fn irBytesAt(mut g Gen, mut lw IrLower, args NodeId[]):
	bt = g.ty(args[0])
	array = g.tyK(bt) == tArray
	b = g.irListAddr(lw, args[0])
	at = g.irExpr(lw, args[1])
	n = g.intLitValue(args[2])
	if not lw.ok: return []
	length = lw.irConstOf(irInt, tys[bt].bits) if array else lw.irHeader(b, 8)
	lw.irPut(
		IrInst(
			op = irFailIf,
			a = at,
			b = lw.irConstOf(irInt, -1 - n),
			cond = irGt,
			uns = true,
			imm = g.failBounds
		)
	)
	end = lw.irDef(irInt, IrInst(op = irAdd, a = at, b = lw.irConstOf(irInt, n)))
	lw.irPut(
		IrInst(op = irFailIf, a = end, b = length, cond = irGt, uns = true, imm = g.failBounds)
	)
	items = b if array else lw.irHeader(b, 0)
	[lw.irDef(irInt, IrInst(op = irAdd, a = items, b = at))]

fn irIntrinsic(mut g Gen, mut lw IrLower, e NodeId, name str, args NodeId[]):
	if g.irIntrinsicAddress(lw, e, name, args) is v: return v
	if g.irIntrinsicElement(lw, e, name, args) is v: return v
	if g.irIntrinsicRaw(lw, e, name, args) is v: return v
	if g.irIntrinsicOps(lw, e, name, args) is v: return v
	lw.irFail("call of {name}")
	[]

# loads, stores, addresses and the list element accessors, or none
fn irIntrinsicAddress(mut g Gen, mut lw IrLower, e NodeId, name str, args NodeId[]) i64[]?:
	sizes = ["8", "16", "32", "64"]
	if (name.startsWith("__ld") or name.startsWith("__st")) and name[4..] in sizes:
		size = (i64.parse(name[4..]) ?? 64) / 8
		a = g.irAddressExpr(lw, args[0])
		if name.startsWith("__ld"):
			v = lw.irDef(irInt, IrInst(op = irLoad, a, size, uns = true))
			return [v]
		# a raw store may write a list's header (the runtime's own lists): counted as one, so no
		# header read is kept across it
		lw.irPut(IrInst(op = irStore, a, c = g.irExpr(lw, args[1]), size, header = true))
		return irNoLeaves()
	if name == "__addr" and g.irByAddress(g.ty(args[0])): return [g.irListAddr(lw, args[0])]
	if name == "__bytesAt": return g.irBytesAt(lw, args)
	if (name == "__at" or name == "__setAt") and g.irIsList(g.ty(args[0])) and
		g.irByAddress(tys[g.ty(args[0])].inner):
		elem = innerOf(tys, g.ty(args[0]))
		list = g.irListAddr(lw, args[0])
		idx = g.irExpr(lw, args[1])
		at = lw.irElementAddr(lw.irHeader(list, 0), idx, g.c.elemStride(elem), 0)
		if name == "__at":
			# the element's bytes, copied as they are: a raw value the runtime moves
			# by hand, so it owns nothing here and goes where it is put bitwise
			slot = lw.irNewSlot(g.sizeOf(elem))
			lw.irPut(IrInst(op = irMemCopy, a = slot, b = at, imm = g.sizeOf(elem)))
			lw.literals.push(slot)
			return [slot]
		if g.irOwnedByAddress(elem):
			v = g.irValue(lw, args[2])
			if not lw.ok or v.len != 1: return irNoLeaves()
			lw.irPut(IrInst(op = irMemCopy, a = at, b = v[0], imm = g.sizeOf(elem)))   # raw: the bytes, no drop
			if lw.owned.findIndex(.slot == v[0]) is ti:
				# the value is the element's now: a temporary's entry goes, a local's (a moved-in
				# parameter's) bytes are zeroed so its drop frees nothing
				if lw.owned[ti].name < 0:
					lw.irConsumed(v[0], ownMovedAsIs)
					lw.owned.remove(ti)
				else:
					g.irZeroSlot(lw, v[0], elem)
			return irNoLeaves()
		g.irPutValue(lw, at, elem, g.irValue(lw, args[2]))
		return irNoLeaves()
	if (name == "__at" or name == "__setAt") and g.irIsList(g.ty(args[0])) and
		g.irTakes(tys[g.ty(args[0])].inner):
		elem = innerOf(tys, g.ty(args[0]))
		list = g.irListAddr(lw, args[0])
		idx = g.irExpr(lw, args[1])
		items = lw.irHeader(list, 0)
		stride = g.c.elemStride(elem)
		if name == "__at":
			v = g.irLoadValue(lw, elem, items, idx, stride)
			if g.irIsOwnedWord(elem):
				lw.raw.extend(v)
			return v
		g.irStoreValue(lw, elem, items, idx, stride, g.irValue(lw, args[2]))
		return irNoLeaves()
	none

# zero elements and the type facts (stride, sizeof, cast...), or none
fn irIntrinsicElement(mut g Gen, mut lw IrLower, e NodeId, name str, args NodeId[]) i64[]?:
	if name == "__zeroElem" and g.irIsList(g.ty(args[0])) and
		g.irTakes(tys[g.ty(args[0])].inner):
		return g.irLeafTypes(innerOf(tys, g.ty(args[0]))).map(t:
			lw.irConstOf(g.irClassOf(t), 0)
		)
	if name == "__zeroElem" and g.irIsList(g.ty(args[0])) and
		g.irByAddress(tys[g.ty(args[0])].inner):
		# an element by address (a str, a tuple): a zeroed slot that owns nothing (an empty value)
		et = innerOf(tys, g.ty(args[0]))
		slot = lw.irNewSlot(g.sizeOf(et).alignUp(8))
		g.irZeroSlot(lw, slot, et)
		lw.literals.push(slot)
		return [slot]
	if name == "__stride": return [lw.irConstOf(irInt, g.c.elemStride(g.ty(args[0])))]
	if name == "__sizeof": return [lw.irConstOf(irInt, g.sizeOf(g.ty(args[0])))]
	if name == "__tykind": return [lw.irConstOf(irInt, g.tyK(g.ty(args[0])))]
	if name == "__tylo" or name == "__tyhi":
		lo, hi = intBounds(tys, g.ty(args[0]))
		return [lw.irConstOf(irInt, lo if name == "__tylo" else hi)]
	if name == "__window": return [lw.irConstOf(irInt, 1 if g.isTextWindow(g.ty(args[0])) else 0)]
	if name == "__owning": return [lw.irConstOf(irInt, g.constIntValue(e))]
	if name == "__globals":
		at = lw.irDef(irInt, IrInst(op = irDataAddr, imm = g.globalsOff))
		return [at]
	if name == "__cast" and g.irClassOf(g.ty(e)) == irInt and
		g.irClassOf(g.ty(args[0])) == irInt:
		v = g.irExpr(lw, args[0])
		if g.irIsOwnedWord(g.ty(e)):
			w = lw.irDef(irInt, IrInst(op = irCopy, a = v))
			g.irOwnedWord(lw, g.ty(e), w)   # a table made here is this code's
			return [w]
		return [v]
	if name == "__drop" and args.len == 1 and not g.isOwningType(g.ty(args[0])):
		g.irValue(lw, args[0])
		return irNoLeaves()
	if name == "__addr" and args.len == 1 and g.irMemPlace(lw, args[0]) is (addr, _):   # a field (a module variable) where it is
		return [addr]
	if name == "__addr" and args.len == 1 and g.irTakes(g.ty(args[0])) and
		not g.irByAddress(g.ty(args[0])):
		return [g.irLentCopy(lw, g.ty(args[0]), g.irValue(lw, args[0]))]   # the leaves in a slot: read through it
	if name == "__alias": return g.irValue(lw, args[0])
	none

# raw memory, threads, closures and forget, or none
fn irIntrinsicRaw(mut g Gen, mut lw IrLower, e NodeId, name str, args NodeId[]) i64[]?:
	if (name == "__memcpy" or name == "__memset") and args.len == 3:
		a = g.irAddressExpr(lw, args[0])
		b = g.irAddressExpr(lw, args[1]) if name == "__memcpy" else g.irExpr(lw, args[1])
		c = g.irExpr(lw, args[2])
		g.irPutSynced(lw, IrInst(op = irMemCopyN if name == "__memcpy" else irMemSet, a, b, c))
		return irNoLeaves()
	if name == "__poke" and args.len == 2:
		vt = g.ty(args[1])
		value = g.irValue(lw, args[1])
		p = g.irExpr(lw, args[0])
		if not lw.ok: return irNoLeaves()
		if g.irTakes(vt):
			g.irStoreLeaves(lw, vt, p, -1, 1, 0, value)
		elif g.irByAddress(vt) and value.len == 1:
			lw.irPut(IrInst(op = irMemCopy, a = p, b = value[0], imm = g.sizeOf(vt)))   # the bytes as they are
			if lw.owned.findIndex(.slot == value[0] and .name < 0) is ti:
				lw.irConsumed(value[0], ownMovedAsIs)
				lw.owned.remove(ti)   # a temporary's value is the place's now
		else:
			lw.irFail("poke of {typeStr(tys, vt)}")
		return irNoLeaves()
	if name == "__peek" and (args.len == 1 or args.len == 2):
		# the value of the type wanted at an address (a second argument only names the type), read raw
		# (it owns nothing here)
		et = g.ty(e)
		at = g.irExpr(lw, args[0])
		if not lw.ok: return irNoLeaves()
		if g.irTakes(et): return g.irLoadValue(lw, et, at, -1, 0)
		slot = lw.irNewSlot(g.sizeOf(et).alignUp(8))
		lw.irPut(IrInst(op = irMemCopy, a = slot, b = at, imm = g.sizeOf(et)))
		lw.literals.push(slot)
		return [slot]
	if name == "__osThreadEntry" or name == "__sigreturn":
		# the address of a thread's entry stub, or of Linux x64's return from a signal's handler
		v = lw.f.irVreg(irInt)
		irPut(
			lw,
			IrInst(
				op = irFnAddr,
				dst = v,
				key = "$osThreadEntry" if name == "__osThreadEntry" else "$sigreturn"
			)
		)
		return [v]
	if name == "__callback" and args.len == 1:
		v = lw.f.irVreg(irInt)
		lw.irPut(
			IrInst(
				op = irFnAddr,
				dst = v,
				imm = g.callbackLabel(nodes[args[0]].text.copy(), g.ty(args[0]))
			)
		)
		return [v]
	if name == "__fence" and args.len == 1:
		# its argument, then a barrier no load or store moves across, the optimizer's moves too (a
		# load after it is not one before it): AArch64's order of loads and stores where the runtime
		# counts on x64's (runtime/sys.zap's fenced)
		v = g.irExpr(lw, args[0])
		lw.irPut(IrInst(op = irFence))
		return [v]
	if name == "__frameAddress":
		# the function's frame record (AArch64's x29), the start of the walk up the calls
		return [lw.irDef(irInt, IrInst(op = irFrameAddr, imm = 0))]
	if name == "__callerSp":
		# the caller's stack pointer once this function returns: past its return address
		return [lw.irDef(irInt, IrInst(op = irFrameAddr, imm = 16))]
	if name == "__callRec" and args.len == 1:
		# the closure whose record is at p (+0 its code, +8 its environment) run
		p = g.irExpr(lw, args[0])
		if not lw.ok: return irNoLeaves()
		g.irPutSynced(lw, IrInst(op = irCallPtr, a = p))
		return irNoLeaves()
	if name == "__forget" and args.len == 1:
		# its bytes are elsewhere now: the local left all zero, so its drop frees nothing
		if nodes[args[0]].kind == nIdent and g.irFind(lw, nodes[args[0]].text.copy()) is v and
			v.len == 1:
			if lw.owned.find((.slot == v[0] or .word == v[0]) and .name >= 0) is o:
				if o.word >= 0:
					lw.irPut(IrInst(op = irStore, a = o.slot, c = lw.irConstOf(irInt, 0)))
				else:
					g.irZeroSlot(lw, o.slot, o.t)
		return irNoLeaves()
	none

# one-operand ops, atomics, strof, fini and drops, or none
fn irIntrinsicOps(mut g Gen, mut lw IrLower, e NodeId, name str, args NodeId[]) i64[]?:
	if irOneOps.find(.name == name and .operands == args.len) is op and
		g.irOneOpTakes(op, args.map(g.ty(it))):
		return g.irOneOpOf(lw, op, args, g.ty(e))
	if name == "__prefetch" and args.len == 1:
		lw.irPut(IrInst(op = irPrefetch, a = g.irExpr(lw, args[0])))
		return irNoLeaves()
	if name == "__pause":
		lw.irPut(IrInst(op = irPause))
		return irNoLeaves()
	if name == "__xadd" and args.len == 2:
		a = g.irExpr(lw, args[0])
		b = g.irExpr(lw, args[1])
		v = lw.f.irVreg(irInt)
		g.irPutSynced(lw, IrInst(op = irXadd, dst = v, a, b))
		return [v]
	if name == "__cmpxchg" and args.len == 3:
		a = g.irExpr(lw, args[0])
		b = g.irExpr(lw, args[1])
		c = g.irExpr(lw, args[2])
		v = lw.f.irVreg(irInt)
		g.irPutSynced(lw, IrInst(op = irCmpxchg, dst = v, a, b, c))
		return [v]
	if name == "__strof" and args.len == 3:
		# a str of the bytes at p, length long, room cap: it owns the bytes when cap is not 0
		slot = g.irTemporary(lw, tyStr)
		for i in 0..3:
			lw.irPut(IrInst(op = irStore, a = slot, c = g.irExpr(lw, args[i]), imm = 8 * i))
		return [slot]
	if name == "__fini":
		g.irPutSynced(lw, IrInst(op = irCall, key = "$fini"))
		return irNoLeaves()
	if name == "__drop" and args.len == 1 and nodes[args[0]].kind == nCall and
		nodes[nodes[args[0]].kids(kidIds)[0]].kind == nIdent and
		nodes[nodes[args[0]].kids(kidIds)[0]].text == "__at" and g.irOwnedByAddress(g.ty(args[0])):
		# the element dropped where it is
		inner = nodes[args[0]].kids(kidIds)[1..nodes[args[0]].kids(kidIds).len].copy()
		elem = g.ty(args[0])
		list = g.irListAddr(lw, inner[0])
		idx = g.irExpr(lw, inner[1])
		irPut(
			lw,
			IrInst(
				op = irDrop,
				a = lw.irElementAddr(lw.irHeader(list, 0), idx, g.c.elemStride(elem), 0),
				ty = elem
			)
		)
		return irNoLeaves()
	if name == "__drop" and args.len == 1 and g.irByAddress(g.ty(args[0])):
		lw.irPut(IrInst(op = irDrop, a = g.irAddressOf(lw, args[0]), ty = g.ty(args[0])))
		return irNoLeaves()
	none
