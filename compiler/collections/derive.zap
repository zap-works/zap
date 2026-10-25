# Printing, JSON and binary encoding, written per type. For every type a program prints or
# encodes, the checker notes it (noteDerive) and, once the program is checked, this file writes
# ordinary Zap functions for it, which are parsed into a module of their own (`derive`) and
# checked like any program code, ownership included; the backend only calls them. The names
# carry a `$`, which only this code may use: `$TyN` is the N-th noted type, and for it
#   $fmtN(v, mut out)   appends v as print shows it nested (strings quoted)
#   $strN(v) str        the printed form
#   $jsonN(v, mut out)  appends v as JSON           $tojsonN(v) str
#   $tojsonindentN(v, indent) str  the same spread out
#   $unjsonN(s, mut cur) $TyN?  reads one value at the cursor    $fromjsonN(s) $TyN?
#   $binN(v, mut out)   appends v's bytes           $tobytesN(v) u8[]
#   $unbinN(b, mut cur) $TyN?   reads one value at the cursor    $frombytesN(b) $TyN?
#   $readN(mut r) $TyN  reads one value with a Reader, in its byte order (T.fromBytes(r))
#   $fromcsvN(s, sep) $TyN ? str  rows read from CSV text (Row[].fromCsv)    $tocsvN(rows, sep) str
#   $valueN(v) i64     an enum's variant integer (`Add = 1`)
#   $fromvalueN(n) $TyN?  the variant with that integer (Type.from(n))
#   $readatN(b, at) $TyN?  reads one value from the bytes at a position (T.fromBytesAt(b, at))
#   $eqN(a, b) bool     a == b, part by part        $cmpN(a, b) i64   -1, 0 or 1, in order
#   $hashN(a) i64       a struct's hash, its fields' hashes mixed in order (a map key)
#   $tobitsN(v) u32     a struct of bools and ranges packed, the first field lowest (a u64 past 32 bits)
#   $frombitsN(w) $TyN  its reverse, each field's bits clamped into its range
#   $addN $subN $mulN $divN(a, b)   a struct of numbers field by field
#   $addRN(a, k) .. $divRN(a, k)    every field and a number of the fields' type (a + k)
#   $addLN(k, a) .. $divLN(k, a)    a number and every field (k - a)
#   $fw<m><shape>N(a, ...)          a number's method m field by field, each argument a struct
#                                   (S, its field) or a number (N): $fwclampNN3(v, lo, hi)
# ZAP_RUN=derived prints the functions as they are written.
# The pieces they call (outInt, outQuoted, jsonText, bytesLittleEndian...) are in runtime/core/value.zap,
# pushLe in runtime/core/corebytes.zap.

alias nodes = c.nodes
alias kidIds = c.kidIds
alias tys = c.types

pub deriveFmt = 1
pub deriveJson = 2
pub deriveUnjson = 4
pub deriveBin = 8
pub deriveUnbin = 16
pub deriveEq = 32
pub deriveCmp = 64
pub deriveArith = 128
pub deriveHash = 256
pub deriveBits = 512
pub deriveUnbits = 1024
pub deriveRead = 2048
pub deriveValue = 4096
pub deriveFromValue = 8192
pub deriveReadAt = 16_384
pub deriveFromCsv = 32_768
pub deriveToCsv = 65_536
pub deriveJsonIndent = 131_072

# the index of type t among the noted types (noted now if new), asking for `kinds` of it;
# a reference is noted as the type it refers to
pub fn noteDerive(mut c Checker, t0 TypeId, kinds i64) i64:
	t = t0
	while c.tKind(t) == tRef:
		t = innerOf(tys, t)
	for i, deriveType in c.deriveTypes:
		if isSameType(tys, deriveType, t):
			c.deriveKinds[i] |= kinds
			return i
	c.deriveTypes.push(t)
	c.deriveKinds.push(kinds)
	c.deriveDone.push(0)
	c.deriveTypes.len - 1

# the index of a noted type, or -1
pub fn deriveIndex(c Checker, t0 TypeId) i64:
	t = t0
	while tys[t].kind == tRef:
		t = innerOf(tys, t)
	c.deriveTypes.findIndex(isSameType(tys, it, t)) ?? -1

# the family of the derived function the method call e (named m) runs, or none
pub fn derivedMethod(mut c Checker, e NodeId, m str) str?:
	callee = nodes[e].kids(kidIds)[0]
	obj = nodes[callee].kids(kidIds)[0]
	et = typeOf(nodes, e)
	if (m == "fromJson" or m == "fromBytes") and c.tKind(et) == tOption and
		nodes[obj].kind == nIdent and nodes[obj].ty == none:
		return "frombytes" if m == "fromBytes" else "fromjson"
	if m == "fromCsv" and c.tKind(et) == tResult and nodes[obj].kind == nIdent and
		nodes[obj].ty == none:
		return "fromcsv"
	if m == "from" and c.tKind(et) == tOption and nodes[obj].kind == nIdent and
		nodes[obj].ty == none and
		c.tKind(innerOf(tys, et)) == tEnum and c.enumHasValues(declOf(tys, innerOf(tys, et))):
		return "fromvalue"
	if m == "fromBytesAt" and c.tKind(et) == tOption and nodes[obj].kind == nIdent and
		nodes[obj].ty == none:
		return "readat"
	if m == "fromBits" and c.tKind(et) == tStruct and nodes[obj].kind == nIdent and
		nodes[obj].ty == none:
		return "frombits"
	if m == "fromBytes" and nodes[obj].kind == nIdent and nodes[obj].ty == none and
		nodes[e].kids(kidIds).len == 2 and c.isReader(typeOf(nodes, nodes[e].kids(kidIds)[1])):
		return "read"
	rt = try nodes[obj].ty
	rk = tys[rt].kind
	if nodes[e].hasFlag(flagFieldwise): return nodes[e].text2().copy()
	if m == "value" and rk == tEnum and c.enumHasValues(declOf(tys, rt)) and
		c.findMethod(tys[rt].name, m) == none:
		return "value"
	if m == "toBits" and rk == tStruct and c.findMethod(tys[rt].name, m) == none: return "tobits"
	if m == "hash" and rk == tStruct and c.findMethod(tys[rt].name, m) == none: return "hash"
	if m == "toCsv" and c.tKind(et) == tStr and c.tKind(c.derefType(rt)) == tList: return "tocsv"
	if m == "toJson" and nodes[e].kids(kidIds).len == 2 and c.tKind(et) == tStr and
		not ((rk == tStruct or rk == tEnum) and c.findMethod(tys[rt].name, m) != none):
		return "tojsonindent"
	if ((m == "toJson" and c.tKind(et) == tStr) or (m == "toBytes" and c.tKind(et) == tList)) and
		not ((rk == tStruct or rk == tEnum) and c.findMethod(tys[rt].name, m) != none):
		return "tobytes" if m == "toBytes" else "tojson"
	none

# the derived function the method call e runs (`T.fromBytes(b)`, `v.toJson()`), else none
pub fn derivedCallee(mut c Checker, e NodeId) NodeId?:
	callee = nodes[e].kids(kidIds)[0]
	if nodes[callee].kind != nField or nodes[callee].kids(kidIds).isEmpty: return none
	family = try c.derivedMethod(e, nodes[callee].text)
	t = typeOf(nodes, nodes[callee].kids(kidIds)[0])
	if family in ["fromjson", "frombytes", "fromvalue", "readat", "fromcsv"]:
		t = innerOf(tys, typeOf(nodes, e))
	elif family == "frombits" or family == "read":
		t = typeOf(nodes, e)
	c.derivedFunction(family, t)

# the function derive.zap wrote of family for type t, else none
pub fn derivedFunction(c Checker, family str, t TypeId) NodeId?:
	i = c.deriveIndex(t)
	if i < 0: return none
	c.findFunc("derive__{c.derivedName(family, i)}")

# The name of the function of family written for the i-th noted type (`$fmt4`). An equality or an
# order of a type of the built-in types alone is named by its parts (`$cmp_T2i64_str_` for
# `(i64, str)`), alike in every program: a kept form of the runtime's generics calls it so
# (keptir.zap).
pub fn derivedName(c Checker, family str, i i64) str:
	if family == "eq" or family == "cmp":
		if c.builtName(c.deriveTypes[i]) is name: return "${family}_{name}"
	"${family}{i}"

# t's parts spelled out when it is made of the built-in types alone, none when it holds a type
# declared somewhere (a struct's, an enum's) or a range
fn builtName(c Checker, t TypeId) str?:
	ty = tys[t]
	if ty.ranged: return none
	k = ty.kind
	if k == tInt: return "{"i" if ty.isSigned else "u"}{ty.bits}"
	if k == tFloat: return "f{ty.bits}"
	if k == tStr: return "str"
	if k == tBool: return "bool"
	if k == tList: return "L{try c.builtName(try ty.inner)}_"
	if k == tOption: return "O{try c.builtName(try ty.inner)}_"
	if k != tStruct or not c.isTupleType(t): return none
	d = try ty.decl
	_ = try nodes[d].origin()
	parts = []
	for a in nodes[d].ints():
		parts.push(try c.builtName(a))
	"T{parts.len}{parts.join("_")}_"

# the type `$TyN` names, or none when the name is not one
pub fn derivedTypeNamed(c Checker, name str) TypeId?:
	if not name.startsWith("$Ty"): return none
	match i64.parse(name[3..]):
		n:
			if n >= 0 and n < c.deriveTypes.len: return c.deriveTypes[n]
			return none
		none: return none

# The functions not yet written for the noted types, as one source text ("" when there are
# none). Writing them notes the types they reach, which are written in the same pass.
pub fn deriveSource(mut c Checker) str:
	src = []
	i = 0
	while i < c.deriveTypes.len:
		todo = c.deriveKinds[i] & (~c.deriveDone[i])
		if todo == 0:
			i += 1
			continue
		c.deriveDone[i] |= todo
		if todo & deriveFmt != 0:
			c.writeFmt(i, src)
		if todo & deriveJson != 0:
			c.writeJson(i, src)
		if todo & deriveUnjson != 0:
			c.writeUnjson(i, src)
		if todo & deriveBin != 0:
			c.writeBin(i, src)
		if todo & deriveUnbin != 0:
			c.writeUnbin(i, src)
		if todo & deriveEq != 0:
			c.writeEq(i, src)
		if todo & deriveCmp != 0:
			c.writeCmp(i, src)
		if todo & deriveArith != 0:
			c.writeArith(i, src)
		if todo & deriveHash != 0:
			c.writeHash(i, src)
		if todo & deriveBits != 0:
			c.writeBits(i, src)
		if todo & deriveUnbits != 0:
			c.writeUnbits(i, src)
		if todo & deriveRead != 0:
			c.writeRead(i, src)
		if todo & deriveValue != 0:
			c.writeValue(i, src)
		if todo & deriveFromValue != 0:
			c.writeFromValue(i, src)
		if todo & deriveReadAt != 0:
			c.writeReadAt(i, src)
		if todo & deriveFromCsv != 0:
			c.writeFromCsv(i, src)
		if todo & deriveJsonIndent != 0:
			c.writeJsonIndent(i, src)
		if todo & deriveToCsv != 0:
			c.writeToCsv(i, src)
		i = 0   # what this wrote may ask more of an earlier type
	while c.fieldwiseDone < c.fieldwise.len:
		FieldwiseAsk(ti, m, shape) = c.fieldwise[c.fieldwiseDone].copy()
		c.writeFieldwise(ti, m, shape, src)
		c.fieldwiseDone += 1
	while c.gradDone < c.gradAsks.len:
		c.gradDone += 1
		c.writeGrad(c.gradDone - 1, src)
	c.writeGradHelpers(src)
	src.join("\n")

# $fw<m><shape>N: the method m on every field, an S argument's field or an N argument as it is
fn writeFieldwise(mut c Checker, i i64, m str, shape str, mut src str[]):
	d = declOf(tys, c.deriveTypes[i])
	fts = c.fieldTypes(d)
	if m in vectorMethods:
		c.writeVectorMethod(i, d, m, c.showTy(fts[0]), src)
		return
	params = (0..shape.len)
		.map(", b{it} {tyName(i) if shape[it] == 'S' else c.showTy(fts[0])}")
		.join("")
	fields = (0..fts.len).map(f:
		nm = c.fieldName(d, f)
		args = (0..shape.len).map("b{it}.{nm}" if shape[it] == 'S' else "b{it}").join(", ")
		"{nm} = a.{nm}.{m}({args})"
	).join(", ")
	src.push("fn $fw{m}{shape}{i}(a {tyName(i)}{params}) {tyName(i)}:")
	src.push("\t{tyName(i)}({fields})")

# a struct of floats' vector method (vectorMethods), its fields n of them
fn writeVectorMethod(mut c Checker, i i64, d NodeId, m str, num str, mut src str[]):
	t = tyName(i)
	if m == "dot":
		sum = (0..c.nodes[d].kids(c.kidIds).len)
			.map("a.{c.fieldName(d, it)} * b0.{c.fieldName(d, it)}")
			.join(" + ")
		src.push("fn $fwdotS{i}(a {t}, b0 {t}) {num}:\n\t{sum}")
	elif m == "length":
		src.push("fn $fwlength{i}(a {t}) {num}:\n\t$fwdotS{i}(a, a).sqrt()")
	elif m == "distance":
		src.push("fn $fwdistanceS{i}(a {t}, b0 {t}) {num}:\n\t$fwlength{i}(a - b0)")
	elif m == "normalized":
		src.push(
			"fn $fwnormalized{i}(a {t}) {t}:\n\tn = $fwlength{i}(a)\n\ta if n == 0.0 else a / n"
		)
	else:
		src.push("fn $fwreflectS{i}(a {t}, b0 {t}) {t}:\n\ta - b0 * (2.0 * $fwdotS{i}(b0, a))")

# `match v` over the variants of enum d, each written as `head` (its index, its name, whether it
# has fields) gives, then each field by `family`'s function after the text `before` gives (its
# index and name), then `tail`; a variant without fields is its head alone
fn writeVariants(
	mut c Checker,
	d NodeId,
	family str,
	kind i64,
	head fn(i64, str, bool) str,
	before fn(i64, str) str,
	tail str,
	mut src str[]
):
	src.push("\tmatch v:")
	for vi in 0..c.nodes[d].kids(c.kidIds).len:
		vn = nodes[d].kids(kidIds)[vi]
		fts = c.fieldTypes(vn)
		name = nodes[vn].text.copy()
		if fts.isEmpty:
			src.push("\t\t{name}: {head(vi, name, false)}")
			continue
		src.push("\t\t{name}{patternOf(fts.len, "p")}:")
		src.push("\t\t\t{head(vi, name, true)}")
		for f, ft in fts:
			text = before(f, c.fieldName(vn, f))
			if text != "":
				src.push("\t\t\t{text}")
			src.push("\t\t\t{c.callFor(family, kind, ft, "p{f}")}")
		if tail != "":
			src.push("\t\t\t{tail}")

fn tyName(i i64):
	"$Ty{i}"

# The resolved types of the fields of declaration (or variant) d, its kid nodes. Callers keep
# d rather than a borrow of its kids: resolving and noting types changes the checker.
# The expression that makes the i-th noted type t, a struct of declaration d, from its fields'
# values g0, g1...: its literal, or for a Grid its maker (a literal of one is refused), whose count
# of cells the caller has checked
fn structMade(mut c Checker, i i64, t TypeId, d NodeId, fields i64):
	if c.gridKind(t) == gridWhole:
		return "Grid<{tyName(c.noteDerive(c.gridCell(t), 0))}>(g0, g1, cells = g2)"
	inits = (0..fields).map("{c.fieldName(d, it)} = g{it}")
	"{tyName(i)}({inits.join(", ")})"

# the lines that return none from a reader of a Grid whose cells do not fill its size
fn gridChecked(c Checker, t TypeId, mut src str[]):
	if c.gridKind(t) == gridWhole:
		src.push("\tif g0 < 0 or g1 < 0 or g2.len != g0 * g1:")
		src.push("\t\treturn none")

fn fieldTypes(mut c Checker, d NodeId):
	out = []
	for f in nodes[d].kids(kidIds).copy():
		out.push(c.resolveType(nodes[f].types()[0]))
	out

# the name of field f of declaration (or variant) d
fn fieldName(c Checker, d NodeId, f i64) ref str:
	nodes[nodes[d].kids(kidIds)[f]].text

# what the generated code writes for a value it cannot walk (a unit, a function), or ""
fn fixedForm(c Checker, t TypeId):
	k = tys[t].kind
	if k == tUnit: return "()"
	if k == tFn: return "<fn>"
	""

# the call that appends value `v` (an expression) of type t with the function family `fam`
fn callFor(mut c Checker, fam str, kind i64, t TypeId, v str):
	fixed = c.fixedForm(t)
	if fixed != "": return "outStr(out, \"{fixed}\")"
	j = c.noteDerive(t, kind)
	"${fam}{j}({v}, out)"

# the expression that reads a value of type t with the function family `fam` (a T?)
fn readFor(mut c Checker, fam str, kind i64, t TypeId, cursor str):
	j = c.noteDerive(t, kind)
	"${fam}{j}({cursor}, cur)"

# ---------- printing ----------

# the loop over a map's cells that printing and encoding write: in key order when the keys are
# integers or text (as Go prints and encodes maps), so the text does not follow the hash
fn mapWalk(c Checker, t TypeId):
	kk = tys[innerOf(tys, t)].kind
	"\tfor k in mapSortedCells(v):" if kk == tInt or kk == tStr
		else "\tfor k in 0..mapEntryCount(v):"

# how the code written for map type t reads the key of cell k: a key that is a text window is
# kept packed in one word and made again (textKeyAt)
fn mapKeyRead(mut c Checker, t TypeId):
	"{c.mapKeyReader(t)}(v, k)"

# the runtime's function giving the key of a cell of map type t
fn mapKeyReader(mut c Checker, t TypeId):
	kt = innerOf(tys, t)
	window = tys[kt].kind == tRef and tys[innerOf(tys, kt)].kind == tStr and c.typeSize(kt) == 16
	"textKeyAt" if window else "mapKeyAt"
