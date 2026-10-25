# The vector types next to Simd<4, f64> and Simd<16, u8> (kinds of their own), from one table:
# each is lanes of one element type in 256 bits, written Simd<N, T> (Simd<8, f32>, Simd<8, i32>,
# Simd<4, i64>, Simd<32, u8>), with one vocabulary where the counts are the lane counts:
#   Simd<N>(a, b, ...) / Simd<N>(x)    the lanes, or one value in every lane (x.splatN() inside)
#   xs.loadN(i) / xs.storeN(i, v)      N elements of a List at i (bounds checked once)
#   v.lane(i)  v.sum()                 one element, all of them added (wrapping for integers)
#   v.min(w)  v.max(w)                 lane by lane
#   v.eqMask(w) ltMask leMask gtMask geMask   an i64 with bit i set when lane i compares true
#   + - and, by element: * (floats, i32), / (floats), & | ^ (integers)
# Simd<32, u8> compares unsigned in min/max and signed in the masks, as Simd<16, u8> does. Inside,
# the table's rows keep the backend's names (f32x8, ...), and the backend (vecgen.zap) emits
# AVX2 for each from the same rows.

alias nodes = c.nodes
alias tys = c.types

# The vector types: the backend's name, the element's bits and kind (0 signed int, 1 unsigned,
# 2 float), the lanes, and whether this table's rows (vecgen.zap) make it (f64x4 and u8x16 have
# code of their own in irvec.zap).
type VecRow:
	name str
	bits i64
	kind i64
	lanes i64
	tabled bool

vecTable = [
	VecRow("f32x8", 32, 2, 8, true),
	VecRow("i32x8", 32, 0, 8, true),
	VecRow("i64x4", 64, 0, 4, true),
	VecRow("u8x32", 8, 1, 32, true),
	VecRow("f64x4", 64, 2, 4, false),
	VecRow("u8x16", 8, 1, 16, false)]

fn vecRows():
	vecTable.filter(.tabled).map(.name.copy())

fn vecElemOf(c Checker, name str) TypeId?:
	if vecTable.find(.name == name) is r:
		return tyFloat(r.bits) if r.kind == 2 else tyInt(r.bits, r.kind == 0)
	none

fn vecLanesOf(name str):
	(vecTable.find(.name == name) ?? return 0).lanes

# the vector type a name denotes, if any
pub fn vecTypeNamed(mut c Checker, name str) TypeId?:
	if name not in vecRows(): return none
	tyVec(tys, try c.vecElemOf(name), vecLanesOf(name))

# the vector type of `lanes` elements of type elem, or none when the table has none
pub fn vecTypeOf(mut c Checker, elem TypeId, lanes i64) TypeId?:
	if vecRows().any(vecLanesOf(it) == lanes and isSameType(tys, c.vecElemOf(it), elem)):
		return tyVec(tys, elem, lanes)
	none

fn vecIsFloat(c Checker, v TypeId):
	c.tKind(tys[v].inner) == tFloat

# whether the binary operator applies lane by lane to vectors of type v
pub fn vecHasOp(c Checker, v TypeId, op i64) bool:
	elem = innerOf(tys, v)
	if op == binAdd or op == binSub: return true
	if op == binMul: return c.vecIsFloat(v) or (tys[elem].kind == tInt and tys[elem].bits == 32)
	if op == binDiv: return c.vecIsFloat(v)
	if op in [binBand, binBor, binBxor]: return not c.vecIsFloat(v)
	false

fn isMaskMethod(m str):
	m in ["eqMask", "ltMask", "leMask", "gtMask", "geMask"]

# a method of a vector of type v
pub fn checkVecMethod(mut c Checker, e NodeId, v TypeId) TypeId:
	callee = nodes[e].kids[0]
	m = nodes[callee].text.copy()   # its own: the messages outlive checking the arguments
	line = nodes[e].line
	col = nodes[e].col
	name = c.showTy(v)
	if m == "lane":
		if not c.expectArgs(e, m, 1): return tyError
		c.checkIntArg(e, 0, "lane expects an index 0..{tys[v].bits - 1}")
		return innerOf(tys, v)
	if m == "sum":
		c.expectArgs(e, m, 0)
		return innerOf(tys, v)
	if m == "min" or m == "max" or isMaskMethod(m):
		if not c.expectArgs(e, m, 1): return tyError
		at = c.derefIfRef(c.argAt(e, 0), c.checkExpr(c.argAt(e, 0), v))
		if c.tKind(at) != tError and not isSameType(tys, at, v):
			c.errorAt(
				line,
				col,
				compileError("VectorArgument", ["{m}", "{name}", "{c.showTy(at)}"])
			)
		if isMaskMethod(m): return tyInt(64, true)
		return v
	c.errorAt(line, col, compileError("VectorNoMethod", ["{name}", "{m}"]))
	tyError

# xs.loadN(i) / xs.storeN(i, v) on a List whose element and N name a vector type: the type
# (the vector loaded, unit for a store), or none when the call is not one of these
pub fn checkVecListMethod(mut c Checker, e NodeId, obj NodeId, elem TypeId) TypeId?:
	callee = nodes[e].kids[0]
	m = nodes[callee].text.copy()   # its own: the messages outlive checking the arguments
	lanes = -1
	load = m.startsWith("load")
	if load or m.startsWith("store"):
		prefixLen = 5
		if load:
			prefixLen = 4
		lanes = i64.parse(m[prefixLen..]) ?? -1
	if lanes < 0: return none
	v = try c.vecTypeOf(elem, lanes)
	c.checkLoadStore(e, obj, m, v, load)

# xs.<m>(i), loading a vector of type v from the list, or xs.<m>(i, x), storing one into it: the
# call's type (v, or unit for a store)
pub fn checkLoadStore(mut c Checker, e NodeId, obj NodeId, m str, v TypeId, load bool) TypeId:
	line = nodes[e].line
	col = nodes[e].col
	if load:
		if not c.expectArgs(e, m, 1): return tyError
		c.checkIntArg(e, 0, "{m} expects an index")
		return v
	if not c.expectArgs(e, m, 2): return tyError
	c.requireMutRoot(obj, line, col, m)
	c.checkIntArg(e, 0, "{m} expects an index")
	vt = c.derefIfRef(c.argAt(e, 1), c.checkExpr(c.argAt(e, 1), v))
	if c.tKind(vt) != tError and not isSameType(tys, vt, v):
		c.errorAt(
			line,
			col,
			compileError("VectorArgument", ["{m}", "{c.showTy(v)}", "{c.showTy(vt)}"])
		)
	tyUnit

# the element type and lane count of a vector type (f64x4 or one of the table)
fn vecShape(c Checker, v TypeId):
	if c.tKind(v) == tSimd: return (tyFloat(64), 4)
	(innerOf(tys, v), tys[v].bits)

# whether a call to `name` makes a vector from its lanes: f64x4(a, b, c, d), i32x8(...)
pub fn isVecLitName(name str) bool:
	name == "f64x4" or name in vecRows()

# f64x4(a, b, c, d): each argument is a lane of the element type
pub fn checkVecLiteral(mut c Checker, e NodeId, name str) TypeId:
	v = tySimd
	if name != "f64x4":
		v = c.vecTypeNamed(name) ?? tyError
	elem, lanes = c.vecShape(v)
	n = c.argCount(e)
	if n != lanes:
		c.errorAt(
			nodes[e].line,
			nodes[e].col,
			compileError("VectorLanes", ["{name}", "{lanes}", "{n}"])
		)
		return tyError
	for i in 0..n:
		c.setArg(e, i, c.laneValue(c.argAt(e, i), elem))
	nodes[e].flags |= flagVecLit
	c.typed(e, v)

# the expression x as a lane of type elem: an integer literal of a float lane is written as a
# float, a narrower number widens, anything else is an error
fn laneValue(mut c Checker, x NodeId, elem TypeId):
	if nodes[x].kind == nInt and c.tKind(elem) == tFloat:
		nodes[x].kind = nFloat
		nodes[x].text += ".0"
		nodes[x].flags &= ~flagByte
	t = c.derefIfRef(x, c.checkExpr(x, elem))
	if isSameType(tys, t, elem) or c.tKind(t) == tError: return x
	if typeIsNumeric(tys, t) and c.numCommon(t, elem) != none and
		isSameType(tys, c.numCommon(t, elem), elem):
		return c.numWiden(x, elem)
	errorAt(
		c,
		nodes[x].line,
		nodes[x].col,
		compileError("VectorLaneType", ["{c.showTy(elem)}", "{c.showTy(t)}"])
	)
	x

# the number x in every lane of a vector of type v (x * v and v + 1.0 read as lane by lane)
pub fn splatTo(mut c Checker, x NodeId, v TypeId) NodeId:
	elem, lanes = c.vecShape(v)
	lane = c.laneValue(x, elem)
	line = nodes[x].line
	col = nodes[x].col
	f = newNode(nodes, nField, line, col, text = "splat{lanes}")
	nodes[f].flags |= flagInternal
	nodes[f].kids.push(lane)
	call = newNode(nodes, nCall, line, col)
	nodes[call].kids.push(f)
	c.checkExpr(call, v)
	call

# x.splatN() on a number whose type and N name a vector type, or none
pub fn checkVecSplat(mut c Checker, e NodeId, numT TypeId) TypeId?:
	m = c.calleeName(e)
	if not m.startsWith("splat") or not nodes[nodes[e].kids[0]].hasFlag(flagInternal): return none
	lanes = i64.parse(m[5..]) ?? -1
	elem = numT
	if c.tKind(numT) == tInt:
		# an integer takes the width the lane count asks for: 8 lanes of i32, 4 of i64, 32 of u8
		if lanes == 8:
			elem = tyInt(32, true)
		elif lanes == 4:
			elem = tyInt(64, true)
		elif lanes == 32:
			elem = tyInt(8, false)
	recv = nodes[nodes[e].kids[0]].kids[0]
	if c.tKind(numT) == tFloat and lanes == 8 and nodes[recv].kind == nFloat:
		elem = tyFloat(32)   # a float literal takes the width too: 8 lanes of f32
		nodes[recv].ty = elem
	v = try c.vecTypeOf(elem, lanes)
	c.expectArgs(e, m, 0)
	v

# ---------- the written names: Simd<4, f64>, Simd<16, u8>, ... ----------

# whether name is Simd, the vector types' (Simd<4, f64>, Simd<16>(x))
pub fn isSimdName(name str) bool:
	name == "Simd"

# The lane count and element type the Simd type or call n writes (its type arguments: Simd<4, f64>,
# Simd<4>): (lanes, element), the element -1 when it is not written; lanes -1 after the error.
fn simdArgs(mut c Checker, n NodeId) (i64, TypeId?):
	line = nodes[n].line
	col = nodes[n].col
	nargs = nodes[n].types().len
	if nargs < 1 or nargs > 2:
		c.errorAt(line, col, compileError("VectorTypeForm", []))
		return (-1, none)
	count = c.resolveTypeOrNumber(nodes[n].types()[0])
	elem TypeId? = c.resolveType(nodes[n].types()[1]) if nargs == 2 else none
	if c.tKind(count) == tError or c.tKind(elem) == tError: return (-1, none)
	if c.tKind(count) != tNum or tys[count].bits < 0:
		c.errorAt(line, col, compileError("VectorLaneCountFirst", []))
		return (-1, none)
	(tys[count].bits, elem)

# the vector type of `lanes` elements of type elem: f64x4 and u8x16 have kinds of their own,
# the rest come from the table; none when there is none
pub fn simdTypeOf(mut c Checker, elem TypeId, lanes i64) TypeId?:
	if lanes == 4 and isSameType(tys, elem, tyFloat(64)): return tySimd
	if lanes == 16 and isSameType(tys, elem, tyInt(8, false)): return tyBytes
	c.vecTypeOf(elem, lanes)

fn simdKinds():
	"Simd<4, f64>, Simd<8, f32>, Simd<8, i32>, Simd<4, i64>, Simd<16, u8> and Simd<32, u8>"

# The number parameter a Simd type or call's lane count names at its generic's definition, where
# its value is not known (Simd<N, f32> in `fn f<N n64>`), else -1. Such a vector has every lane
# operation there; each instance, its body a copy of its own (regarrays.zap numberInstance),
# checks and makes the vector its N names.
fn openLanes(c Checker, n NodeId) TypeId?:
	if nodes[n].types().isEmpty or nodes[n].types().len > 2: return none
	count = nodes[n].types()[0]
	if nodes[count].kind != nTyName or nodes[count].text not in c.subst.names: return none
	t = try c.substLookup(nodes[count].text)
	t if c.tKind(t) == tNum and tys[t].bits < 0 else none

# a vector of elem whose lane count is the number parameter `lanes` stands for
fn openVector(mut c Checker, elem TypeId, lanes TypeId) TypeId:
	tyVec(tys, elem, -1, lanes)

pub fn isOpenVector(c Checker, maybeT TypeId?) bool:
	t = maybeT ?? return false
	c.tKind(t) == tVec and tys[t].bits < 0

# Simd<N, T> written as a type
pub fn simdTypeNamed(mut c Checker, te NodeId) TypeId:
	line = nodes[te].line
	col = nodes[te].col
	open = c.openLanes(te)
	if open is open:
		if nodes[te].types().len < 2:
			c.errorAt(line, col, compileError("VectorElementMissing", ["{c.showTy(open)}"]))
			return tyError
		elem = c.resolveType(nodes[te].types()[1])
		if c.tKind(elem) == tError: return tyError
		return c.openVector(elem, open)
	lanes, written = c.simdArgs(te)
	if lanes < 0: return tyError
	elem = written ??
		return c.errorTyped(line, col, compileError("VectorElementMissing", ["{lanes}"]))
	t = c.simdTypeOf(elem, lanes) ?? tyError
	if t == tyError:
		errorAt(
			c,
			line,
			col,
			compileError("NoSuchVector", ["{lanes}", "{c.showTy(elem)}", "{simdKinds()}"])
		)
		return tyError
	t

# the element a literal lane takes when nothing names it: the one float or integer type the lane
# count has (4: f64 or i64, 8: f32 or i32, 16 and 32: u8)
fn simdLiteralElem(lanes i64, isFloat bool):
	if isFloat:
		if lanes == 8: return tyFloat(32)
		return tyFloat(64)
	if lanes == 4: return tyInt(64, true)
	if lanes == 8: return tyInt(32, true)
	tyInt(8, false)

# Simd<4>(a, b, c, d) and Simd<4>(x): a vector from its lanes, or one value in every lane. The
# element type is the one written (Simd<16, u8>(15)), else the expected vector's, else the lanes'
# own, a literal taking the width its lane count has. Rewritten to the backend's forms
# (f64x4(...), x.splat4()), marked internal.
pub fn checkSimdCtor(mut c Checker, e NodeId, expected TypeId?) TypeId:
	callee = nodes[e].kids[0]
	line = nodes[e].line
	col = nodes[e].col
	open = c.openLanes(callee)
	if open is open: return c.checkOpenSimdCtor(e, open, expected)
	lanes, written = c.simdArgs(callee)
	if lanes < 0: return tyError
	name = "Simd<{lanes}>"
	n = c.argCount(e)
	if n != 1 and n != lanes:
		errorAt(
			c,
			line,
			col,
			compileError("VectorValueCount", ["{name}", "{lanes}", "{n}"])
		)
		return tyError
	elem = written ?? tyError
	if written == none and c.isSimdType(expected) and expected is simdT:
		expectedElem, expectedLanes = c.simdShape(simdT)
		if expectedLanes == lanes:
			elem = expectedElem
	elif written == none:
		a0 = c.argAt(e, 0)
		k0 = nodes[a0].kind
		if k0 == nFloat or k0 == nInt:
			isFloat = (0..n).any(nodes[c.argAt(e, it)].kind == nFloat)
			elem = simdLiteralElem(lanes, isFloat)
		else:
			elem = c.derefIfRef(a0, c.checkExpr(a0, none))
			if c.tKind(elem) == tError: return tyError
	vt = c.simdTypeOf(elem, lanes) ?? tyError
	if vt == tyError:
		errorAt(
			c,
			line,
			col,
			compileError("NoSuchVector", ["{lanes}", "{c.showTy(elem)}", "{simdKinds()}"])
		)
		return tyError
	if n == 1:
		# one value in every lane: x.splatN()
		arg = c.argAt(e, 0)
		at = c.derefIfRef(arg, c.checkExpr(arg, elem))
		if c.tKind(at) == tError: return tyError
		if not isSameType(tys, at, elem) and nodes[arg].kind != nInt and nodes[arg].kind != nFloat:
			errorAt(
				c,
				line,
				col,
				compileError("VectorRepeatType", ["{lanes}", "{c.showTy(elem)}", "{c.showTy(at)}"])
			)
			return tyError
		f = newNode(nodes, nField, line, col, text = "splat{lanes}")
		nodes[f].kids.push(arg)
		nodes[f].flags |= flagInternal
		nodes[e].kids = [f]
		return c.checkCall(e, vt)
	# one value per lane: the literal the backend builds (f64x4(a, b, c, d), i32x8(...))
	inner = "f64x4"
	if vt != tySimd:
		inner = "{c.showTy(elem)}x{lanes}"
	if not isVecLitName(inner):
		errorAt(
			c,
			line,
			col,
			compileError("VectorOneValue", ["{lanes}", "{c.showTy(elem)}"])
		)
		return tyError
	nodes[callee].nodePart().types = []
	nodes[callee].flags |= flagInternal
	t = c.checkVecLiteral(e, inner)
	nodes[callee].text = inner   # renamed last: checking the lanes reads only them
	t

# Simd<N, T>(x) at the definition of a generic with the number parameter N (lanes): one value in
# every lane, of the element written, else the expected vector's, else the value's own
fn checkOpenSimdCtor(mut c Checker, e NodeId, lanes TypeId, expected TypeId?) TypeId:
	callee = nodes[e].kids[0]
	n = c.argCount(e)
	if n != 1:
		errorAt(
			c,
			nodes[e].line,
			nodes[e].col,
			compileError(
				"VectorValueCount",
				["Simd<{c.showTy(lanes)}>", "{c.showTy(lanes)}", "{n}"]
			)
		)
		return tyError
	written TypeId? = none
	if nodes[callee].types().len == 2:
		written = c.resolveType(nodes[callee].types()[1])
	elif c.isOpenVector(expected):
		written = innerOf(tys, expected)
	elem = written ?? c.derefIfRef(c.argAt(e, 0), c.checkExpr(c.argAt(e, 0), none))
	if c.tKind(elem) == tError: return tyError
	c.setArg(e, 0, c.laneValue(c.argAt(e, 0), elem))
	c.typed(e, c.openVector(elem, lanes))

pub fn isSimdType(c Checker, t TypeId?) bool:
	k = c.tKind(t)
	k in [tSimd, tBytes, tVec]

# the element type and lane count of any vector type (u8x16 too)
pub fn simdShape(c Checker, t TypeId) (TypeId, i64):
	if c.tKind(t) == tBytes: return (tyInt(8, false), 16)
	c.vecShape(t)
