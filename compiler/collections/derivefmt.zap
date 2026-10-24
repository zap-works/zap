# The derived formatting and JSON of a type (derive.zap).

alias nodes = c.nodes
alias tys = c.types

fn writeFmt(mut c Checker, i i64, mut src str[]):
	t = c.deriveTypes[i]
	k = tys[t].kind
	src.push("fn $fmt{i}(v {tyName(i)}, mut out u8[]):")
	if k == tInt and tys[t].isSigned:
		src.push("\toutInt(out, i64(v))")
	elif k == tInt:
		src.push("\toutUint(out, u64(v))")
	elif k == tFloat and tys[t].bits < 64:
		src.push("\tpushFloat(out, i64(f64(v).toBits()), {tys[t].bits})")
	elif k == tFloat:
		src.push("\toutFloat(out, v)")
	elif k == tBool:
		src.push("\toutBool(out, v)")
	elif k == tStr:
		src.push("\toutQuoted(out, v)")
	elif k == tSimd:
		src.push("\toutStr(out, \"[\")")
		for lane in 0..4:
			if lane > 0:
				src.push("\toutStr(out, \", \")")
			src.push("\toutFloat(out, v.lane({lane}))")
		src.push("\toutStr(out, \"]\")")
	elif k == tBytes:
		src.push("\toutStr(out, \"[\")")
		for lane in 0..16:
			if lane > 0:
				src.push("\toutStr(out, \", \")")
			src.push("\toutInt(out, i64(v.lane({lane})))")
		src.push("\toutStr(out, \"]\")")
	elif k == tVec:
		src.push("\toutStr(out, \"[\")")
		for lane in 0..c.types[t].bits:
			if lane > 0:
				src.push("\toutStr(out, \", \")")
			src.push("\t{c.callFor("fmt", deriveFmt, innerOf(tys, t), "v.lane({lane})")}")
		src.push("\toutStr(out, \"]\")")
	elif k == tList or k == tArray:
		elem = innerOf(tys, t)
		src.push("\tout.push(91)")
		src.push("\tfor k in 0..v.len:")
		src.push("\t\tif k > 0:")
		src.push("\t\t\toutStr(out, \", \")")
		src.push("\t\t{c.callFor("fmt", deriveFmt, elem, "v[k]")}")
		src.push("\tout.push(93)")
	elif k == tMap:
		src.push("\tout.push(123)")
		src.push("\tfirst = true")
		src.push(c.mapWalk(t))
		src.push("\t\tif mapEntryAlive(v, k):")
		src.push("\t\t\tif not first:")
		src.push("\t\t\t\toutStr(out, \", \")")
		src.push("\t\t\tfirst = false")
		src.push("\t\t\t{c.callFor("fmt", deriveFmt, innerOf(tys, t), c.mapKeyRead(t))}")
		src.push("\t\t\toutStr(out, \": \")")
		src.push("\t\t\t{c.callFor("fmt", deriveFmt, valOf(tys, t), "mapValAt(v, k)")}")
		src.push("\tout.push(125)")
	elif k == tOption:
		src.push("\tmatch v:")
		src.push("\t\tx:")
		src.push("\t\t\toutStr(out, \"some(\")")
		src.push("\t\t\t{c.callFor("fmt", deriveFmt, innerOf(tys, t), "x")}")
		src.push("\t\t\tout.push(41)")
		src.push("\t\tnone: outStr(out, \"none\")")
	elif k == tResult:
		src.push("\tmatch v:")
		src.push("\t\tx:")
		src.push("\t\t\toutStr(out, \"ok(\")")
		src.push("\t\t\t{c.callFor("fmt", deriveFmt, innerOf(tys, t), "x")}")
		src.push("\t\t\tout.push(41)")
		src.push("\t\terror:")
		src.push("\t\t\toutStr(out, \"err(\")")
		src.push("\t\t\t{c.callFor("fmt", deriveFmt, errOf(tys, t), "error")}")
		src.push("\t\t\tout.push(41)")
	elif k == tBox:
		src.push("\t{c.callFor("fmt", deriveFmt, innerOf(tys, t), "v")}")
	elif k == tStruct:
		d = declOf(tys, t)
		fts = c.fieldTypes(d)
		# as it is written: Point(x = 1, y = 2), a tuple (1, "a")
		tuple = tupleShown(c.shownName(d)) != c.shownName(d)
		opening = "(" if tuple else "{c.shownName(d)}("
		src.push("\toutStr(out, \"{opening}\")")
		for f, ft in fts:
			sep = ", " if f > 0 else ""
			named = "" if tuple else "{c.fieldName(d, f)} = "
			src.push("\toutStr(out, \"{sep}{named}\")")
			src.push("\t{c.callFor("fmt", deriveFmt, ft, "v.{c.fieldName(d, f)}")}")
		src.push("\tout.push(41)")
	elif k == tEnum:
		writeVariants(
			c,
			declOf(tys, t),
			"fmt",
			deriveFmt,
			(_, name, fields): "outStr(out, \"{name}(\")" if fields else "outStr(out, \"{name}\")",
			(f, _): "outStr(out, \", \")" if f > 0 else "", "out.push(41)", src)
	else:
		src.push("\toutStr(out, \"{c.fixedForm(t)}\")")
	writeWrapper(i, "$str", "$fmt", "str", "str(move out)", src)

# ---------- JSON ----------

fn writeJson(mut c Checker, i i64, mut src str[]):
	t = c.deriveTypes[i]
	k = tys[t].kind
	src.push("fn $json{i}(v {tyName(i)}, mut out u8[]):")
	if k == tInt and tys[t].isSigned:
		src.push("\toutInt(out, i64(v))")
	elif k == tInt:
		src.push("\toutUint(out, u64(v))")
	elif k == tFloat:
		src.push("\toutJsonFloat(out, f64(v))")
	elif k == tBool:
		src.push("\toutBool(out, v)")
	elif k == tStr:
		src.push("\toutQuoted(out, v)")
	elif k == tList:
		src.push("\tout.push(91)")
		src.push("\tfor k in 0..v.len:")
		src.push("\t\tif k > 0:")
		src.push("\t\t\tout.push(44)")
		src.push("\t\t{c.callFor("json", deriveJson, innerOf(tys, t), "v[k]")}")
		src.push("\tout.push(93)")
	elif k == tMap:
		kt = innerOf(tys, t)
		src.push("\tout.push(123)")
		src.push("\tfirst = true")
		src.push(c.mapWalk(t))
		src.push("\t\tif mapEntryAlive(v, k):")
		src.push("\t\t\tif not first:")
		src.push("\t\t\t\tout.push(44)")
		src.push("\t\t\tfirst = false")
		if tys[kt].kind == tStr:
			src.push("\t\t\toutQuoted(out, {c.mapKeyRead(t)})")
		else:
			src.push("\t\t\tout.push(34)")
			src.push("\t\t\toutInt(out, i64({c.mapKeyRead(t)}))")
			src.push("\t\t\tout.push(34)")
		src.push("\t\t\tout.push(58)")
		src.push("\t\t\t{c.callFor("json", deriveJson, valOf(tys, t), "mapValAt(v, k)")}")
		src.push("\tout.push(125)")
	elif k == tOption:
		src.push("\tmatch v:")
		src.push("\t\tx: {c.callFor("json", deriveJson, innerOf(tys, t), "x")}")
		src.push("\t\tnone: outStr(out, \"null\")")
	elif k == tBox:
		src.push("\t{c.callFor("json", deriveJson, innerOf(tys, t), "v")}")
	elif k == tStruct:
		d = declOf(tys, t)
		fts = c.fieldTypes(d)
		src.push("\tout.push(123)")
		for f, ft in fts:
			sep = ""
			if f > 0:
				sep = ","
			src.push("\toutStr(out, \"{sep}\\\"{c.fieldName(d, f)}\\\":\")")
			src.push("\t{c.callFor("json", deriveJson, ft, "v.{c.fieldName(d, f)}")}")
		src.push("\tout.push(125)")
	elif k == tEnum:
		# {"$tag":"Name"} then each field as ,"name":value
		writeVariants(
			c,
			declOf(tys, t),
			"json",
			deriveJson,
			(_, name, fields): "outStr(out, \"\\\{\\\"$tag\\\":\\\"{name}\\\"\")" if fields else "outStr(out, \"\\\{\\\"$tag\\\":\\\"{name}\\\"}\")",
			(_, field): "outStr(out, \",\\\"{field}\\\":\")",
			"out.push(125)",
			src
		)
	else:
		src.push("\toutStr(out, \"null\")")
	writeWrapper(i, "$tojson", "$json", "str", "str(move out)", src)

# $tojsonindentN(v, indent): the JSON of v spread out (v.toJson(2))
fn writeJsonIndent(c Checker, i i64, mut src str[]):
	src.push("fn $tojsonindent{i}(v {tyName(i)}, indent i64) str:")
	src.push("\tjsonIndented($tojson{i}(v), indent)")

# a range type's value read as v: none when it lies outside the range, so what follows reads v
# as inside it (a check just made)
# the lines returning none when the integer v lies outside integer type t's values (none for an
# i64 or a u64, whose bounds every i64 or u64 meets)
fn boundsChecked(c Checker, t TypeId, v str, indent str, mut src str[]):
	if tys[t].bits == 64 and not tys[t].ranged: return
	lo, hi = intBounds(tys, t)
	src.push("{indent}if {v} < {lo} or {v} > {hi}:")
	src.push("{indent}\treturn none")

# whether integer type t is a u64 (or a type of its own over one): JSON reads it apart, since
# its values above the largest i64 are no i64
fn isU64(c Checker, t TypeId):
	tys[t].bits == 64 and not tys[t].isSigned and not tys[t].ranged

# the lines making v, of integer type t, from n, an i64 (a u64 for a u64) read from JSON: none
# when it lies outside t's values
fn writeIntFrom(c Checker, t TypeId, n str, v str, indent str, mut src str[]):
	c.boundsChecked(t, n, indent, src)
	b = tys[t].bits
	conv = "i{b}" if tys[t].isSigned else "u{b}"
	src.push("{indent}{v} = {c.definedOf(t, "{conv}({n})")}")

# value, an expression of t's base, made t when t is a defined type (`$Ty3(u8(n))`)
fn definedOf(c Checker, t TypeId, move value str):
	if not isDefined(tys, t): return value
	"{tyName(c.deriveIndex(t))}({value})"

# The `"name": value` pairs of a JSON object up to its closing brace, the opening brace (and,
# for a variant, the tag) already read: each named field goes to its variable f0, f1... (see
# writeFieldVars), an unknown name is passed over. d is the declaration (or variant) whose fields
# these are.
fn writeJsonFields(mut c Checker, d NodeId, fts TypeId[], indent str, mut src str[]):
	src.push("{indent}more = true")
	src.push("{indent}next = 0")   # where in names the key expected next starts
	src.push("{indent}while more:")
	names = (0..fts.len).map("{c.fieldName(d, it)}\\\"").join("")
	src.push("{indent}	key = jsonField(s, cur, \"{names}\", next)")
	at = 0
	for f, ft in fts:
		after = at + c.fieldName(d, f).len + 1
		src.push("{indent}	{"if" if f == 0 else "elif"} key == {at}:")
		src.push("{indent}		f{f} = try {c.unjsonCall(ft)}")
		if c.zeroFor(fts, f) != "":
			src.push("{indent}		seen |= {1 << f}")
		src.push("{indent}		next = {after if f + 1 < fts.len else 0}")
		at = after
	src.push("{indent}	{"if" if fts.isEmpty else "elif"} key == -2 or not jsonSkip(s, cur):")
	src.push("{indent}		return none")
	src.push("{indent}	more = jsonChar(s, cur, 44)")

# the literal a field variable of plain type (a number, a bool, a str, a list) starts as, its
# bit in `seen` saying it was read, or "" for a field held as an option until read
fn zeroFor(c Checker, fts TypeId[], f i64):
	t = fts[f]
	k = tys[t].kind
	if f >= 62: return ""
	if k == tInt and not tys[t].ranged: return "0"
	if k == tFloat: return "0.0"
	if k == tBool: return "false"
	if k == tStr: return "\"\""
	if k == tList: return "[]"
	""

# the declarations of the field variables f0, f1...: a plain one starts as its zero (zeroFor), the
# others none until read (an optional field's variable has the field's own type, so a missing one
# is simply none)
fn writeFieldVars(mut c Checker, fts TypeId[], indent str, mut src str[]):
	src.push("{indent}seen = 0")
	for f in 0..fts.len:
		j = c.noteDerive(fts[f], 0)
		zero = c.zeroFor(fts, f)
		if zero != "":
			src.push("{indent}f{f} {tyName(j)} = {zero}")
		elif tys[fts[f]].kind == tOption:
			src.push("{indent}f{f} {tyName(j)} = none")
		else:
			src.push("{indent}f{f} {tyName(j)}? = none")

# the values g0, g1... of the fields: any missing field but an optional one fails the decoding.
# A field's value is taken out of its variable, so the literal built from the g's owns it (`g =
# f` would only borrow f).
fn writeFieldValues(mut c Checker, fts TypeId[], indent str, mut src str[]):
	plain = 0
	for f in 0..fts.len:
		if c.zeroFor(fts, f) != "":
			plain |= 1 << f
	src.push("{indent}if seen != {plain}:")
	src.push("{indent}	return none")
	for f in 0..fts.len:
		if c.zeroFor(fts, f) != "" or tys[fts[f]].kind == tOption:
			src.push("{indent}g{f} = move f{f}")
		elif tys[fts[f]].kind in [tMap, tBox]:
			src.push("{indent}g{f} = try f{f}")
		else:
			src.push("{indent}g{f} = try move f{f}")

# the runtime's function that reads a value of type t as it is, or "" when t's own $unjson
# function checks or converts what it reads
fn jsonReader(c Checker, t TypeId):
	k = tys[t].kind
	if k == tInt and typeStr(tys, t) == "i64": return "jsonInt"
	if k == tFloat and tys[t].bits == 64: return "jsonFloat"
	if k == tBool: return "jsonBool"
	if k == tStr: return "jsonText"
	""

# how the code written reads a value of type t at the cursor
fn unjsonCall(mut c Checker, t TypeId) str:
	reader = c.jsonReader(t)
	if reader != "": return "{reader}(s, cur)"
	c.readFor("unjson", deriveUnjson, t, "s")

fn writeUnjson(mut c Checker, i i64, mut src str[]):
	t = c.deriveTypes[i]
	k = tys[t].kind
	src.push("fn $unjson{i}(s str, mut cur Cursor) {tyName(i)}?:")
	if c.jsonReader(t) != "":
		src.push("\treturn {c.jsonReader(t)}(s, cur)")
	elif k == tInt:
		reader = "jsonU64" if c.isU64(t) else "jsonInt"
		src.push("\tn = try {reader}(s, cur)")
		c.writeIntFrom(t, "n", "v", "\t", src)
		src.push("\treturn v")
	elif k == tFloat and tys[t].bits < 64:
		src.push("\tx = try jsonFloat(s, cur)")
		src.push("\treturn {typeStr(tys, t)}(x)")
	elif k == tList:
		src.push("\tif not jsonChar(s, cur, 91):")
		src.push("\t\treturn none")
		src.push("\titems {tyName(i)} = []")
		src.push("\tif jsonChar(s, cur, 93):")
		src.push("\t\treturn items")
		src.push("\tmore = true")
		src.push("\twhile more:")
		src.push("\t\tx = try {c.unjsonCall(innerOf(tys, t))}")
		src.push("\t\titems.push(x)")
		src.push("\t\tmore = jsonChar(s, cur, 44)")
		src.push("\tif not jsonChar(s, cur, 93):")
		src.push("\t\treturn none")
		src.push("\treturn items")
	elif k == tMap:
		c.writeUnjsonMap(i, t, src)
	elif k == tOption:
		src.push("\tif jsonNull(s, cur):")
		src.push("\t\tnothing {tyName(i)} = none")
		src.push("\t\treturn nothing")
		src.push("\tx = try {c.unjsonCall(innerOf(tys, t))}")
		src.push("\tpresent {tyName(i)} = x")
		src.push("\treturn present")
	elif k == tBox:
		src.push("\tx = try {c.unjsonCall(innerOf(tys, t))}")
		src.push("\treturn Box(x)")
	elif k == tStruct:
		c.writeUnjsonStruct(i, t, src)
	elif k == tEnum:
		c.writeUnjsonEnum(i, t, src)
	else:
		src.push("\treturn none")
	src.push("fn $fromjson{i}(s str) {tyName(i)}?:")
	src.push("\tcur = Cursor(at = 0)")
	src.push("\tv = try $unjson{i}(s, cur)")
	src.push("\tif not jsonEnd(s, cur):")
	src.push("\t\treturn none")
	src.push("\treturn v")

fn writeUnjsonMap(mut c Checker, i i64, t TypeId, mut src str[]):
	kt = innerOf(tys, t)
	src.push("\tif not jsonChar(s, cur, 123):")
	src.push("\t\treturn none")
	src.push("\tm {tyName(i)} = \{}")
	src.push("\tif jsonChar(s, cur, 125):")
	src.push("\t\treturn m")
	src.push("\tmore = true")
	src.push("\twhile more:")
	if tys[kt].kind == tStr:
		src.push("\t\tk = try jsonText(s, cur)")   # owned: the map keeps it
	else:
		src.push("\t\tkey = try jsonText(s, cur)")
		parsed = "u64" if c.isU64(kt) else "i64"
		src.push("\t\tn = try {parsed}.parse(key)")
		c.writeIntFrom(kt, "n", "k", "\t\t", src)
	src.push("\t\tif not jsonChar(s, cur, 58):")
	src.push("\t\t\treturn none")
	src.push("\t\tx = try {c.unjsonCall(valOf(tys, t))}")
	src.push("\t\tm[k] = x")
	src.push("\t\tmore = jsonChar(s, cur, 44)")
	src.push("\tif not jsonChar(s, cur, 125):")
	src.push("\t\treturn none")
	src.push("\treturn m")

fn writeUnjsonStruct(mut c Checker, i i64, t TypeId, mut src str[]):
	d = declOf(tys, t)
	fts = c.fieldTypes(d)
	c.writeFieldVars(fts, "\t", src)
	src.push("\tif not jsonChar(s, cur, 123):")
	src.push("\t\treturn none")
	src.push("\tif not jsonChar(s, cur, 125):")
	c.writeJsonFields(d, fts, "\t\t", src)
	src.push("\t\tif not jsonChar(s, cur, 125):")
	src.push("\t\t\treturn none")
	c.writeFieldValues(fts, "\t", src)
	c.gridChecked(t, src)
	src.push("\treturn {c.structMade(i, t, d, fts.len)}")

fn writeUnjsonEnum(mut c Checker, i i64, t TypeId, mut src str[]):
	d = declOf(tys, t)
	src.push("\tif not jsonChar(s, cur, 123):")
	src.push("\t\treturn none")
	src.push("\ttagKey = try jsonText(s, cur)")
	src.push("\tif tagKey != \"$tag\" or not jsonChar(s, cur, 58):")
	src.push("\t\treturn none")
	src.push("\ttag = try jsonText(s, cur)")
	for vn in nodes[d].kids:
		fts = c.fieldTypes(vn)
		vname = nodes[vn].text
		# the value it returns, written while vname is at hand (noting types changes c)
		made = "{tyName(i)}.{vname}"
		if not fts.isEmpty:
			made = "{made}({(0..fts.len).map("g{it}").join(", ")})"
		src.push("\tif tag == \"{vname}\":")
		c.writeFieldVars(fts, "\t\t", src)
		src.push("\t\tif jsonChar(s, cur, 44):")
		c.writeJsonFields(vn, fts, "\t\t\t", src)
		src.push("\t\tif not jsonChar(s, cur, 125):")
		src.push("\t\t\treturn none")
		c.writeFieldValues(fts, "\t\t", src)
		src.push("\t\treturn {made}")
	src.push("\treturn none")

# ---------- binary ----------
# Integers, floats and bools are their bytes (little-endian); a str is a u32 length and its
# bytes; a list is a u32 count and its elements; a map is a u32 count and key, value pairs; an
# option is one byte (0 none, 1 some) and the value; a struct is its fields in order; an enum is
# a u32 tag and the fields of that variant. No names, no padding: both sides share the type.
