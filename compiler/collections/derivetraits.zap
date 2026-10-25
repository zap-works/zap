# The derived equality, ordering, hash and arithmetic of a type (derive.zap).

alias nodes = c.nodes
alias kidIds = c.kidIds
alias tys = c.types

# the expression x == y for values of type t: the operator for what has one, else $eqN
fn eqOf(mut c Checker, t TypeId, x str, y str):
	if c.isEqNative(t): return "({x} == {y})"
	"{c.derivedName("eq", c.noteDerive(t, deriveEq))}({x}, {y})"

# the order of x and y (-1, 0 or 1) for values of type t
fn cmpOf(mut c Checker, t TypeId, x str, y str):
	k = c.tKind(t)
	if k == tRef:
		k = c.tKind(tys[t].inner)   # what the references point to, compared
	if k in [tInt, tFloat, tStr]: return "ordCompare({x}, {y})"
	"{c.derivedName("cmp", c.noteDerive(t, deriveCmp))}({x}, {y})"

# a == b part by part: the fields of a struct or tuple, the elements of a list or array (and
# its length), the value of an optional, the variant and then the values of an enum
fn writeEq(mut c Checker, i i64, mut src str[]):
	t = c.deriveTypes[i]
	k = c.tKind(t)
	src.push("fn {c.derivedName("eq", i)}(a {tyName(i)}, b {tyName(i)}) bool:")
	if k == tStruct:
		d = declOf(tys, t)
		fts = c.fieldTypes(d)
		parts = []
		for f, ft in fts:
			nm = c.fieldName(d, f)
			parts.push(c.eqOf(ft, "a.{nm}", "b.{nm}"))
		if parts.isEmpty:
			parts.push("true")
		src.push("\t{parts.join(" and ")}")
	elif k == tList and (c.tKind(tys[t].inner) == tInt or c.tKind(tys[t].inner) == tBool):
		src.push("\trt.listSameBytes(a, b)")   # no padding, no NaN: equal elements are equal bytes
	elif k == tList or k == tArray:
		elem = innerOf(tys, t)
		src.push("\tif a.len != b.len:")
		src.push("\t\treturn false")
		src.push("\tfor k in 0..a.len:")
		src.push("\t\tif not {c.eqOf(elem, "a[k]", "b[k]")}:")
		src.push("\t\t\treturn false")
		src.push("\ttrue")
	elif k == tOption:
		src.push("\tmatch a:")
		src.push("\t\tx:")
		src.push("\t\t\tmatch b:")
		src.push("\t\t\t\ty: return {c.eqOf(innerOf(tys, t), "x", "y")}")
		src.push("\t\t\t\tnone: return false")
		src.push("\t\tnone: return b == none")
	elif k == tEnum:
		src.push("\tmatch a:")
		for vn in nodes[declOf(tys, t)].kids(kidIds).copy():
			# the conditions first: noting the types they compare changes c, which vname borrows
			fts = c.fieldTypes(vn)
			conds = (0..fts.len).map(c.eqOf(fts[it], "p{it}", "q{it}"))
			if conds.isEmpty:
				conds.push("true")
			vname = nodes[vn].text
			src.push("\t\t{vname}{patternOf(fts.len, "p")}:")
			src.push("\t\t\tmatch b:")
			src.push("\t\t\t\t{vname}{patternOf(fts.len, "q")}: return {conds.join(" and ")}")
			src.push("\t\t\t\t_: return false")

# a struct's hash: each field's hash mixed into the one before (FNV's multiply, then the high
# bits folded down), so equal structs hash alike and fields in another order do not
fn writeHash(mut c Checker, i i64, mut src str[]):
	t = c.deriveTypes[i]
	d = declOf(tys, t)
	fts = c.fieldTypes(d)
	lines = []
	for f, ft in fts:
		lines.push("\th = (h ^ u64({c.hashOf(ft, "a.{c.fieldName(d, f)}")})) * 1099511628211")
		lines.push("\th ^= (h >> 29) & 0x7FFFFFFFF")
	src.push("fn $hash{i}(a {tyName(i)}) i64:")
	src.push("\th u64 = 1469598103934665603")
	for l in lines:
		src.push(l)
	src.push("\ti64(h)")

# the hash of x, of type t (a type isHashKey accepts)
fn hashOf(mut c Checker, t TypeId, x str):
	k = c.tKind(t)
	if k == tBool: return "(1 if {x} else 0)"
	if k == tStruct: return "$hash{c.noteDerive(t, deriveHash | deriveEq)}({x})"
	"{x}.hash()"

# the bindings of a variant's n values: (p0, p1), or nothing
# `name{i}(v)`: the bytes `writer{i}` writes for v into a fresh list, as `result` makes them
# (the list itself, or its text)
fn writeWrapper(i i64, name str, writer str, ret str, result str, mut src str[]):
	src.push("fn {name}{i}(v {tyName(i)}) {ret}:")
	src.push("\tout u8[] = []")
	src.push("\t{writer}{i}(v, out)")
	src.push("\treturn {result}")

fn patternOf(n i64, prefix str):
	if n == 0: return ""
	"({(0..n).map("{prefix}{it}").join(", ")})"

# the order of a and b: a tuple field by field, a list or array element by element and then by
# length (lexicographic)
fn writeCmp(mut c Checker, i i64, mut src str[]):
	t = c.deriveTypes[i]
	k = c.tKind(t)
	src.push("fn {c.derivedName("cmp", i)}(a {tyName(i)}, b {tyName(i)}) i64:")
	if k == tStruct:
		d = declOf(tys, t)
		fts = c.fieldTypes(d)
		for f, ft in fts:
			nm = c.fieldName(d, f)
			src.push("\tc{f} = {c.cmpOf(ft, "a.{nm}", "b.{nm}")}")
			src.push("\tif c{f} != 0:")
			src.push("\t\treturn c{f}")
		src.push("\t0")
	else:
		src.push("\tn = a.len.min(b.len)")
		src.push("\tfor k in 0..n:")
		src.push("\t\tr = {c.cmpOf(innerOf(tys, t), "a[k]", "b[k]")}")
		src.push("\t\tif r != 0:")
		src.push("\t\t\treturn r")
		src.push("\tordCompare(a.len, b.len)")

# The arithmetic of a struct whose fields are all one number type: + - * / field by field, and
# * / by a number of that type.
fn writeArith(mut c Checker, i i64, mut src str[]):
	t = c.deriveTypes[i]
	d = declOf(tys, t)
	fts = c.fieldTypes(d)
	if fts.isEmpty: return
	num = c.showTy(c.numberFieldOf(t, true))
	ops = ["+", "-", "*", "/"]
	families = ["add", "sub", "mul", "div"]
	for o in 0..4:
		writeElementwise(
			c,
			i,
			d,
			fts,
			"${families[o]}{i}",
			"a {tyName(i)}, b {tyName(i)}",
			(nm, at): "a.{nm}{at} {ops[o]} b.{nm}{at}",
			src
		)
		writeElementwise(
			c,
			i,
			d,
			fts,
			"${families[o]}R{i}",
			"a {tyName(i)}, k {num}",
			(nm, at): "a.{nm}{at} {ops[o]} k",
			src
		)
		writeElementwise(
			c,
			i,
			d,
			fts,
			"${families[o]}L{i}",
			"k {num}, a {tyName(i)}",
			(nm, at): "k {ops[o]} a.{nm}{at}",
			src
		)

# the function `name` of `params` giving a $TyI (its fields fts) whose field is `element`
# of the field's name and of the index after it ("" for a number, "[at]" for an array of
# numbers, which a loop fills)
fn writeElementwise(
	mut c Checker,
	i i64,
	d NodeId,
	fts TypeId[],
	name str,
	params str,
	element fn(str, str) str,
	mut src str[]
):
	src.push("fn {name}({params}) {tyName(i)}:")
	fields = []
	for f in 0..fts.len:
		nm = c.fieldName(d, f).copy()
		if c.tKind(fts[f]) == tArray:
			src.push("\tf{f} {c.showTy(fts[f])}")
			src.push("\tfor at in 0..{tys[fts[f]].bits}:")
			src.push("\t\tf{f}[at] = {element(nm, "[at]")}")
			fields.push("{nm} = f{f}")
		else:
			fields.push("{nm} = {element(nm, "")}")
	src.push("\t{tyName(i)}({fields.join(", ")})")
