# The lowering of operators and conversions: unary and binary operators, overflow checks, narrowing
# (irLowerValues.zap).

alias nodes = g.c.nodes
alias kidIds = g.c.kidIds
alias tys = g.c.types

fn irUnary(mut g Gen, mut lw IrLower, e NodeId, class i64) i64:
	op = nodes[e].ival
	a = g.irExpr(lw, nodes[e].kids(kidIds)[0])
	v = lw.f.irVreg(class)
	if op == unNeg and class != irFloat: return g.irFits(lw, g.irNegated(lw, a, g.ty(e)), g.ty(e))
	if op == unNeg:
		lw.irPut(IrInst(op = irFNeg, dst = v, a))
	elif op == unNot:
		lw.irPut(IrInst(op = irXor, dst = v, a, b = lw.irConstOf(irInt, 1)))
	elif op == unBnot:
		lw.irPut(IrInst(op = irNot, dst = v, a))
	else:
		lw.irFail("unary {op}")
	v if op == unNot else g.irNarrow(lw, v, g.ty(e))

# -a of integer type t, in 64 bits: a signed 64-bit one stops the program on the smallest value
fn irNegated(mut g Gen, mut lw IrLower, a i64, t TypeId) i64:
	lw.irDef(irInt, IrInst(op = irNeg, a, trap = g.irTraps(t)))

# the bits of the float x
fn irFloatBitsOf(mut lw IrLower, x i64) i64:
	lw.irDef(irInt, IrInst(op = irFloatBits, a = x))

fn irBinary(mut g Gen, mut lw IrLower, e NodeId, class i64) i64:
	op = nodes[e].ival
	l = nodes[e].kids(kidIds)[0]
	r = nodes[e].kids(kidIds)[1]
	if op == binCoalesce and g.irIsLeafOption(g.ty(l)):
		return g.irBinaryCoalesce(lw, e, class, l, r)
	if op == binAnd or op == binOr or isCompareOp(op):
		# a bool made by branches: 1 on the way in, 0 when the condition fails
		v = lw.f.irVreg(irInt)
		way = g.irSplitIf(lw, e)
		lw.irPut(IrInst(op = irConst, dst = v, imm = 1))
		lw.f.irElse(way)
		lw.irPut(IrInst(op = irConst, dst = v, imm = 0))
		lw.f.irJoin(way.end)
		return v
	lt = g.ty(l)
	if class < 0 or g.irClassOf(lt) != class or g.irClassOf(g.ty(r)) != class:
		lw.irFail("operator {nodes[e].ival} of {typeStr(tys, lt)}")
		return -1
	a = g.irExpr(lw, l)
	b = g.irExpr(lw, r)
	if op == binPow or (op == binMod and class == irFloat):
		return g.irBinaryPower(lw, e, class, op, a, b, lt)
	g.irBinaryArith(lw, e, class, op, r, a, b, lt)

# a ?? b of a leaf option: the value when there is one, else the right side
fn irBinaryCoalesce(mut g Gen, mut lw IrLower, e NodeId, class i64, l NodeId, r NodeId):
		# the value when there is one, else the right side (read only then)
		o = g.irOptionParts(lw, l)
		if o.len != 2:
			lw.irFail("optional of {typeStr(tys, g.ty(l))}")
			return -1
		v = lw.f.irVreg(class)
		before = lw.owned.copy()
		way = lw.irSplitNZ(o[0])
		lt = g.ty(l)
		owned = g.irIsOwnedWord(tys[lt].inner)
		# a place's map (box) where the right side never gives one: lent as the place's own word is
		lends = owned and g.irNever(r) and g.irNamesPlace(lw, l) and lw.irOwnedWordAt(o[1]) < 0
		if lends:
			lw.irPut(IrInst(op = irCopy, dst = v, a = o[1]))
		elif g.c.isOptionOfRef(lt) and g.tyK(g.ty(e)) != tRef:
			# a reference's target wanted: read through it
			lw.irCopyValue([v], g.irLoadValue(lw, innerOf(tys, tys[lt].inner), o[1], -1, 0))
		elif owned:
			lw.irPut(IrInst(op = irCopy, dst = v, a = g.irWordTaken(lw, innerOf(tys, lt), o[1])))
		else:
			lw.irPut(IrInst(op = irCopy, dst = v, a = o[1]))
		lw.f.irJumpTo(way.end)
		taken = lw.owned.copy()
		lw.f.irEnter(way.no)
		lw.irFallbackEntered(before)
		alt = g.irValue(lw, r)   # a return here leaves the function instead
		if not lw.ok: return -1
		if not lw.f.irEnded() and not g.irNever(r):
			if alt.len != 1:
				lw.irFail("scalar of type {typeStr(tys, g.ty(r))}")
				return -1
			irPut(
				lw,
				IrInst(
					op = irCopy,
					dst = v,
					a = g.irWordTaken(lw, innerOf(tys, lt), alt[0]) if owned else alt[0]
				)
			)
		lw.irFallbackLeft(taken)
		lw.f.irJoin(way.end)
		if lends: return o[1]
		if owned:
			g.irOwnedWord(lw, innerOf(tys, lt), v)
		v

# the runtime's power and a float's remainder
fn irBinaryPower(
	mut g Gen,
	mut lw IrLower,
	e NodeId,
	class i64,
	op i64,
	a i64,
	b i64,
	lt TypeId
) i64:
		# the runtime's: a ** b (a signed one stopping the program when it leaves the type, an
		# unsigned one wrapping), a float's remainder
		name = "remBits" if op == binMod
			else "fpow" if class == irFloat
			else "upow" if g.irUnsigned(lt)
			else "ipow"
		if class != irFloat:
			out = g.irCallRt(lw, name, [a, b])
			if not lw.ok or out.len != 1: return -1
			return g.irFits(lw, out[0], g.ty(e))
		# fpow and remBits take and give a float's bits
		out = g.irCallRt(lw, name, [lw.irFloatBitsOf(a), lw.irFloatBitsOf(b)])
		if not lw.ok or out.len != 1: return -1
		v = lw.irDef(irFloat, IrInst(op = irBitsToFloat, a = out[0]))
		g.irRounded(lw, v, g.ty(e))

# an arithmetic, bit or shift operator on two scalars
fn irBinaryArith(
	mut g Gen,
	mut lw IrLower,
	e NodeId,
	class i64,
	op i64,
	r NodeId,
	a i64,
	b i64,
	lt TypeId
) i64:
	v = lw.f.irVreg(class)
	irOp = irFloatOp(op) if class == irFloat else irIntOp(op)
	if irOp < 0:
		lw.irFail("operator {op}")
		return -1
	if (irOp == irShl or irOp == irShr) and not g.isIntLit(r) and
		not g.c.spanInside(r, 0, tys[g.ty(e)].bits - 1):
		irPut(
			lw,
			IrInst(
				op = irFailIf,
				a = b,
				b = lw.irConstOf(irInt, tys[g.ty(e)].bits),
				cond = irGe,
				uns = true,
				imm = g.failShift
			)
		)
	# the operands' ranges keep it inside its type, or an index's (lengths.zap, checked ahead):
	# no check
	proven = g.c.arithmeticInside(e) or nodes[e].hasFlag(flagInBounds) or e in lw.checked
	# an i32's + - * that may leave it: the operation of 32 bits, its overflow flag the check
	narrow = irOp in [irAdd, irSub, irMul] and g.irStopsOnOverflow(g.ty(e)) and
		tys[g.ty(e)].bits == 32 and g.irStopsOnOverflow(lt) and tys[lt].bits == 32 and
		not nodes[e].hasFlag(flagWrap) and not proven
	# a division's operands' width (imm): a constant divisor's code depends on it
	irPut(
		lw,
		IrInst(
			op = u16(irOp),
			dst = v,
			a,
			b,
			uns = g.irUnsigned(lt),
			imm = tys[lt].bits if g.tyK(lt) == tInt else 64,
			size = 4 if narrow else 8,
			trap = narrow or irOp in [irAdd, irSub, irMul] and g.irTraps(g.ty(e)) and
				not nodes[e].hasFlag(flagWrap) and not proven
		)
	)
	if narrow: return v
	# & | ^ of values within the width stay within it, and so do a logical shift right, an
	# unsigned quotient and any remainder (smaller than its divisor, of the dividend's sign)
	stays = irOp in [irAnd, irOr, irXor, irRem] or (irOp in [irShr, irDiv] and g.irUnsigned(lt))
	if class == irFloat: return g.irRounded(lw, v, g.ty(e))
	if stays: return v
	arithmetic = irOp in [irAdd, irSub, irMul, irDiv] and not nodes[e].hasFlag(flagWrap)
	g.irFits(lw, v, g.ty(e)) if arithmetic and not proven else g.irNarrow(lw, v, g.ty(e))

# whether arithmetic of integer type t stops the program when its result leaves t (a signed
# type: an unsigned one is bits, wrapping) and that type is 64 bits wide (the operation's own
# overflow flag tells; a narrower one is checked by irFits)
fn irTraps(g Gen, t TypeId):
	g.irStopsOnOverflow(t) and tys[t].bits == 64

fn irStopsOnOverflow(g Gen, t TypeId):
	g.tyK(t) == tInt and tys[t].isSigned

# v, the 64-bit result of arithmetic of type t, made t: one leaving a signed type narrower than
# 64 bits stops the program, an unsigned one wraps
fn irFits(mut g Gen, mut lw IrLower, v i64, t TypeId):
	w = g.irNarrow(lw, v, t)
	if w != v and g.irStopsOnOverflow(t):
		lw.irPut(IrInst(op = irFailIf, a = w, b = v, cond = irNe, imm = g.failOverflow))
	w

# v of integer type from converted to integer type to: wrapped when asked (`u8.wrap(x)`) or when
# to is no narrower (a sign change keeps the bits), else the program stops when v does not fit;
# into a range type, it stops when v lies outside the range
fn irConverted(mut g Gen, mut lw IrLower, v i64, from TypeId, to TypeId, wrap bool):
	w = g.irNarrow(lw, v, to)
	if wrap: return w
	if tys[to].bits < tys[from].bits:
		lw.irPut(IrInst(op = irFailIf, a = w, b = v, cond = irNe, imm = g.failConversion))
		if tys[from].bits == 64 and not tys[from].isSigned and tys[to].isSigned:
			g.irConversionFails(lw, v, irLt, 0)   # a u64 past 2^63 reads as a negative word
	if tys[to].ranged:
		lo, hi = intBounds(tys, from)
		if lo < tys[to].lo or not tys[from].isSigned and tys[to].lo > 0:
			g.irConversionFails(lw, w, irLt, tys[to].lo)
		# (none past the largest of its width: w, narrowed to it, never is)
		if hi > tys[to].hi and tys[to].hi < intMax(tys[to].bits, true):
			g.irConversionFails(lw, w, irGt, tys[to].hi)
	w

# a conversion's check: the program stops when v cond k
fn irConversionFails(mut g Gen, mut lw IrLower, v i64, cond i64, k i64):
	irPut(
		lw,
		IrInst(
			op = irFailIf,
			a = v,
			b = lw.irConstOf(irInt, k),
			cond = u8(cond),
			imm = g.failConversion
		)
	)

# v wrapped to the width of integer type t when it is narrower than 64 bits
fn irNarrow(mut g Gen, mut lw IrLower, v i64, t TypeId) i64:
	if g.tyK(t) != tInt or tys[t].bits == 64: return v
	lw.irDef(irInt, IrInst(op = irTrunc, a = v, imm = tys[t].bits, uns = not tys[t].isSigned))

fn irIntOp(op i64):
	if op == binAdd: return irAdd
	if op == binSub: return irSub
	if op == binMul: return irMul
	if op == binDiv: return irDiv
	if op == binMod: return irRem
	if op == binBand: return irAnd
	if op == binBor: return irOr
	if op == binBxor: return irXor
	if op == binShl: return irShl
	if op == binShr: return irShr
	-1

fn irFloatOp(op i64):
	if op == binAdd: return irFAdd
	if op == binSub: return irFSub
	if op == binMul: return irFMul
	if op == binDiv: return irFDiv
	-1
