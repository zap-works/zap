# Advanced SIMD floating-point forms (single and double; half precision arithmetic is Armv8.2):
# three same, by element, two-register miscellaneous, across lanes and scalar pairwise, and the
# fixed-point conversions of shift by immediate. The operation is the instruction's `fop`, its
# format the `size` (0 single, 1 double); a double in a 64-bit vector is unallocated.

# the three-same operation of the U bit, the "a" bit (23) and the opcode (24-31), and whether it
# is pairwise
fn floatSameOperation(u bool, a bool, opcode i64) (FloatOp, bool):
	unallocated = FloatOp.None, false
	match opcode:
		0x18: (.MinNum if a else .MaxNum, u)
		0x19: unallocated if u else (.MulSub if a else .MulAcc, false)
		0x1A:
			if not u: return (.Sub if a else .Add, false)
			(.Abd, false) if a else (.Add, true)
		0x1B: unallocated if a else (.Mul if u else .MulX, false)
		0x1C:
			if not u: return unallocated if a else (.CompareEq, false)
			(.CompareGt if a else .CompareGe, false)
		0x1D: (.AbsGt if a else .AbsGe, false) if u else unallocated
		0x1E: (.Min if a else .Max, u)
		_:
			if not u: return (.RsqrtStep if a else .RecipStep, false)
			unallocated if a else (.Div, false)

# whether the scalar forms have the operation
fn scalarSame(op FloatOp):
	match op:
		MulX, CompareEq, CompareGe, CompareGt, AbsGe, AbsGt, RecipStep, RsqrtStep, Abd: true
		_: false

fn floatSame(w i64, scalar bool):
	op, pair = floatSameOperation(bit(w, 29), bit(w, 23), bits(w, 11, 5))
	q = bit(w, 30) and not scalar
	size = bits(w, 22, 1)
	if op == .None or (scalar and not op.scalarSame()): return Instr()
	if size == 1 and not q and not scalar: return Instr()
	Instr(
		op = .Vector,
		vop = .FloatSame,
		fop = op,
		rd = bits(w, 0, 5),
		rn = bits(w, 5, 5),
		rm = bits(w, 16, 5),
		size,
		q,
		pair,
		scalar
	)

# by element: fmla, fmls, fmul, fmulx; the double's lane number is H alone and its L must be 0
fn floatIndexed(w i64, scalar bool):
	size = bits(w, 22, 1)
	if not bit(w, 23): return Instr()
	h = bits(w, 11, 1)
	l = bits(w, 21, 1)
	q = bit(w, 30) and not scalar
	if size == 1 and (l == 1 or (not q and not scalar)): return Instr()
	u = bit(w, 29)
	op = match bits(w, 12, 4):
		1: FloatOp.None if u else FloatOp.MulAcc
		5: .None if u else .MulSub
		_: .MulX if u else .Mul
	if op == .None: return Instr()
	Instr(
		op = .Vector,
		vop = .FloatIndexed,
		fop = op,
		rd = bits(w, 0, 5),
		rn = bits(w, 5, 5),
		rm = bits(w, 20, 1) << 4 | bits(w, 16, 4),
		size,
		q,
		index = h if size == 1 else h << 1 | l,
		scalar
	)

# the two-register operation of U, a (23) and the opcode (22-31 and the compares), with its `opc`
# (the rounding of a conversion or frint), or None
fn floatUnaryOperation(u bool, a bool, opcode i64) (FloatOp, i64):
	unallocated = FloatOp.None, 0
	match opcode:
		0x0C: (.CompareGe if u else .CompareGt, 0) if a else unallocated
		0x0D: (.CompareLe if u else .CompareEq, 0) if a else unallocated
		0x0E: (.CompareLt, 0) if a and not u else unallocated
		0x16: unallocated if a else (.NarrowOdd if u else .Narrow, 0)
		0x17: unallocated if a or u else (.Widen, 0)
		0x18:
			if u: return unallocated if a else (.Round, 4)
			(.Round, 1 if a else 0)
		0x19:
			if u: return (.Round, 6 if a else 5)
			(.Round, 3 if a else 2)
		0x1A: (.ToInt, 1 if a else 0)
		0x1B: (.ToInt, 3 if a else 2)
		0x1C:
			if a: return (.UnsignedRsqrtEstimate if u else .UnsignedRecipEstimate, 0)
			(.ToInt, 4)
		0x1D:
			if not a: return (.FromInt, 0)
			(.RsqrtEstimate if u else .RecipEstimate, 0)
		0x1F: unallocated if not a else (.Sqrt if u else .RecipExponent, 0)
		_: unallocated

# whether the scalar forms have the operation
fn scalarUnary(op FloatOp):
	match op:
		Narrow, Widen, Round, Sqrt, UnsignedRecipEstimate, UnsignedRsqrtEstimate: false
		_: true

# whether the operation changes the lanes' width
fn changesWidth(op FloatOp):
	match op:
		Narrow, Widen, NarrowOdd: true
		_: false

fn floatUnary(w i64, scalar bool):
	op, opc = floatUnaryOperation(bit(w, 29), bit(w, 23), bits(w, 12, 5))
	q = bit(w, 30) and not scalar
	size = bits(w, 22, 1)
	if op == .None or (scalar and not op.scalarUnary()): return Instr()
	if not scalar and op == .RecipExponent: return Instr()
	if op == .NarrowOdd and size == 0: return Instr()
	if (op == .UnsignedRecipEstimate or op == .UnsignedRsqrtEstimate) and size == 1: return Instr()
	if size == 1 and not q and not scalar and not op.changesWidth(): return Instr()
	Instr(
		op = .Vector,
		vop = .FloatUnary,
		fop = op,
		rd = bits(w, 0, 5),
		rn = bits(w, 5, 5),
		size,
		q,
		opc,
		signed = not bit(w, 29),
		scalar
	)

# across lanes (fmaxnmv, fminnmv, fmaxv, fminv: four singles) or scalar pairwise (faddp, fmaxnmp,
# fminnmp, fmaxp, fminp: two lanes)
fn floatAcross(w i64, scalar bool):
	opcode = bits(w, 12, 5)
	a = bit(w, 23)
	size = bits(w, 22, 1)
	q = bit(w, 30) and not scalar
	op = match opcode:
		0x0C: FloatOp.MinNum if a else FloatOp.MaxNum
		0x0D: .None if a else .Add
		_: .Min if a else .Max
	if not bit(w, 29) or op == .None: return Instr()
	if not scalar and (opcode == 0x0D or size == 1 or not q): return Instr()
	Instr(
		op = .Vector,
		vop = .FloatAcross,
		fop = op,
		rd = bits(w, 0, 5),
		rn = bits(w, 5, 5),
		size,
		q,
		scalar
	)

# scvtf and ucvtf (opcode 0x1C), fcvtzs and fcvtzu (0x1F) by fixed point: `fbits` the fraction
# bits, `size` the lane's log2 width less 3 as the immh gives it (2 single, 3 double)
fn floatFixed(w i64, scalar bool, size i64, fbits i64):
	q = bit(w, 30) and not scalar
	if size < 2 or (size == 3 and not q and not scalar): return Instr()
	Instr(
		op = .Vector,
		vop = .FloatUnary,
		fop = .FromInt if bits(w, 11, 5) == 0x1C else .ToInt,
		rd = bits(w, 0, 5),
		rn = bits(w, 5, 5),
		size = size - 2,
		q,
		opc = 3,
		signed = not bit(w, 29),
		amount = fbits,
		scalar
	)
