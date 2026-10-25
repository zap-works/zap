# The derived binary, reader and bit-packed forms of a type (derive.zap).

alias nodes = c.nodes
alias kidIds = c.kidIds
alias tys = c.types

fn writeBin(mut c Checker, i i64, mut src str[]):
	t = c.deriveTypes[i]
	k = tys[t].kind
	src.push("fn $bin{i}(v {tyName(i)}, mut out u8[]):")
	if k == tInt:
		src.push("\tpushLe(out, u64(v), {tys[t].bits / 8})")
	elif k == tFloat and tys[t].bits < 64:
		src.push("\tpushLe(out, u64(v.toBits()), {tys[t].bits / 8})")
	elif k == tFloat:
		src.push("\tpushLe(out, v.toBits(), 8)")
	elif k == tBool:
		src.push("\tif v:")
		src.push("\t\tout.push(1)")
		src.push("\telse:")
		src.push("\t\tout.push(0)")
	elif k == tStr:
		src.push("\tpushLe(out, u64(v.len), 4)")
		src.push("\tout.extend(v.bytes())")
	elif k == tList:
		src.push("\tpushLe(out, u64(v.len), 4)")
		src.push("\tfor k in 0..v.len:")
		src.push("\t\t{c.callFor("bin", deriveBin, innerOf(tys, t), "v[k]")}")
	elif k == tArray:
		src.push("\tfor k in 0..{tys[t].bits}:")
		src.push("\t\t{c.callFor("bin", deriveBin, innerOf(tys, t), "v[k]")}")
	elif k == tMap:
		src.push("\tpushLe(out, u64(v.len), 4)")
		src.push("\tfor k in 0..mapEntryCount(v):")
		src.push("\t\tif mapEntryAlive(v, k):")
		src.push("\t\t\t{c.callFor("bin", deriveBin, innerOf(tys, t), c.mapKeyRead(t))}")
		src.push("\t\t\t{c.callFor("bin", deriveBin, valOf(tys, t), "mapValAt(v, k)")}")
	elif k == tOption:
		src.push("\tmatch v:")
		src.push("\t\tx:")
		src.push("\t\t\tout.push(1)")
		src.push("\t\t\t{c.callFor("bin", deriveBin, innerOf(tys, t), "x")}")
		src.push("\t\tnone: out.push(0)")
	elif k == tBox:
		src.push("\t{c.callFor("bin", deriveBin, innerOf(tys, t), "v")}")
	elif k == tStruct:
		d = declOf(tys, t)
		fts = c.fieldTypes(d)
		for f, ft in fts:
			src.push("\t{c.callFor("bin", deriveBin, ft, "v.{c.fieldName(d, f)}")}")
	elif k == tEnum:
		writeVariants(
			c,
			declOf(tys, t),
			"bin",
			deriveBin,
			(vi, _, _): "pushLe(out, {vi}, 4)",
			(_, _): "",
			"",
			src
		)
	writeWrapper(i, "$tobytes", "$bin", "u8[]", "out", src)

fn writeUnbin(mut c Checker, i i64, mut src str[]):
	t = c.deriveTypes[i]
	k = tys[t].kind
	src.push("fn $unbin{i}(b u8[], mut cur Cursor) {tyName(i)}?:")
	if k == tInt:
		bits = tys[t].bits
		src.push("\tu = try bytesLittleEndian(b, cur, {bits / 8})")
		# the bytes are the bits: a signed value is their wrap (an i32 -1 reads as 0xFFFFFFFF)
		conv = "i{bits}.wrap" if tys[t].isSigned else "u{bits}"
		src.push("\tv = {c.definedOf(t, "{conv}(u)")}")
		if tys[t].ranged:
			c.boundsChecked(t, "v", "\t", src)
		src.push("\treturn v")
	elif k == tFloat and tys[t].bits < 64:
		src.push("\tu = try bytesLittleEndian(b, cur, {tys[t].bits / 8})")
		src.push("\treturn {typeStr(tys, t)}.fromBits(u{tys[t].bits}(u))")
	elif k == tFloat:
		src.push("\tu = try bytesLittleEndian(b, cur, 8)")
		src.push("\treturn f64.fromBits(u)")
	elif k == tBool:
		src.push("\tu = try bytesLittleEndian(b, cur, 1)")
		src.push("\treturn u != 0")
	elif k == tStr:
		src.push("\tn = try bytesLittleEndian(b, cur, 4)")
		src.push("\treturn bytesText(b, cur, i64(n))")
	elif k == tList:
		src.push("\tn = try bytesLittleEndian(b, cur, 4)")
		src.push("\titems {tyName(i)} = []")
		src.push("\tloop i64(n):")
		src.push("\t\tx = try {c.readFor("unbin", deriveUnbin, innerOf(tys, t), "b")}")
		src.push("\t\titems.push(x)")
		src.push("\treturn items")
	elif k == tArray:
		src.push("\titems {tyName(c.noteDerive(innerOf(tys, t), 0))}[{tys[t].bits}]")
		src.push("\tfor k in 0..{tys[t].bits}:")
		src.push("\t\titems[k] = try {c.readFor("unbin", deriveUnbin, innerOf(tys, t), "b")}")
		src.push("\treturn items")
	elif k == tMap:
		src.push("\tn = try bytesLittleEndian(b, cur, 4)")
		src.push("\tm {tyName(i)} = \{}")
		src.push("\tloop i64(n):")
		src.push("\t\tk = try {c.readFor("unbin", deriveUnbin, innerOf(tys, t), "b")}")
		src.push("\t\tx = try {c.readFor("unbin", deriveUnbin, valOf(tys, t), "b")}")
		src.push("\t\tm[k] = x")
		src.push("\treturn m")
	elif k == tOption:
		src.push("\ttag = try bytesLittleEndian(b, cur, 1)")
		src.push("\tif tag == 0:")
		src.push("\t\tnothing {tyName(i)} = none")
		src.push("\t\treturn nothing")
		src.push("\tx = try {c.readFor("unbin", deriveUnbin, innerOf(tys, t), "b")}")
		src.push("\tpresent {tyName(i)} = x")
		src.push("\treturn present")
	elif k == tBox:
		src.push("\tx = try {c.readFor("unbin", deriveUnbin, innerOf(tys, t), "b")}")
		src.push("\treturn Box(x)")
	elif k == tStruct:
		d = declOf(tys, t)
		fts = c.fieldTypes(d)
		for f, ft in fts:
			src.push("\tg{f} = try {c.readFor("unbin", deriveUnbin, ft, "b")}")
		c.gridChecked(t, src)
		src.push("\treturn {c.structMade(i, t, d, fts.len)}")
	elif k == tEnum:
		d = declOf(tys, t)
		src.push("\ttag = try bytesLittleEndian(b, cur, 4)")
		for vi in 0..c.nodes[d].kids(c.kidIds).len:
			vn = nodes[d].kids(kidIds)[vi]
			fts = c.fieldTypes(vn)
			src.push("\tif tag == {vi}:")
			args = []
			for f, ft in fts:
				src.push("\t\tg{f} = try {c.readFor("unbin", deriveUnbin, ft, "b")}")
				args.push("g{f}")
			if fts.isEmpty:
				src.push("\t\treturn {tyName(i)}.{nodes[vn].text}")
			else:
				src.push("\t\treturn {tyName(i)}.{nodes[vn].text}({args.join(", ")})")
		src.push("\treturn none")
	else:
		src.push("\treturn none")
	src.push("fn $frombytes{i}(b u8[]) {tyName(i)}?:")
	src.push("\tcur = Cursor(at = 0)")
	src.push("\tv = try $unbin{i}(b, cur)")
	src.push("\tif cur.at != b.len:")
	src.push("\t\treturn none")
	src.push("\treturn v")

# ---------- read with a Reader ----------

# whether t is the runtime's Reader (or a reference to one)
pub fn isReader(c Checker, maybeT TypeId?) bool:
	t = maybeT ?? return false
	while tys[t].kind == tRef:
		t = innerOf(tys, t)
	tys[t].kind == tStruct and nodes[declOf(tys, t)].mod() == "rt" and
		nodes[declOf(tys, t)].text2() == "Reader"

# the expression reading a value of type t with the reader r
fn readWith(mut c Checker, t TypeId):
	"$read{c.noteDerive(t, deriveRead)}(r)"

# the Reader's method reading a number of integer or float type t as stored (its base for a
# range): u8, i32, f64...
fn readerMethod(c Checker, t TypeId):
	b = rangeBase(tys, t)
	if tys[b].kind == tFloat: return "f{tys[b].bits}"
	"{"i" if tys[b].isSigned else "u"}{tys[b].bits}"

# whether a list of t is read in one copy of its bytes: numbers as the machine keeps them
fn copiedNumbers(c Checker, t TypeId):
	k = tys[t].kind
	(k == tInt and not tys[t].ranged or k == tFloat and tys[t].bits >= 32)

# the fewest bytes a value of type t takes in toBytes's layout (a count read for a list of them
# is checked against it)
fn leastBytes(mut c Checker, t TypeId) i64:
	k = tys[t].kind
	if k == tInt or k == tFloat: return tys[t].bits / 8
	if k == tArray: return tys[t].bits * c.leastBytes(innerOf(tys, t))
	if k == tStruct: return c.fieldTypes(declOf(tys, t)).map(c.leastBytes(it)).sum()
	if k in [tStr, tList, tMap, tEnum]: return 4
	1

# The value T.fromBytes(r) reads: toBytes's layout in the reader's byte order, a fixed array its
# N values; what runs past the end, a range's value outside it and an enum's unknown tag set
# r.short and give the lowest value
fn writeRead(mut c Checker, i i64, mut src str[]):
	t = c.deriveTypes[i]
	k = tys[t].kind
	src.push("fn $read{i}(mut r Reader) {tyName(i)}:")
	if k == tInt and tys[t].ranged:
		lo, hi = intBounds(tys, t)
		src.push("\tv = r.{c.readerMethod(t)}()")
		src.push("\tif v < {lo} or v > {hi}:")
		src.push("\t\tr.short = true")
		src.push("\tv.clamp({lo}, {hi})")
	elif k == tInt or k == tFloat and tys[t].bits >= 32:
		src.push("\t{c.definedOf(t, "r.{c.readerMethod(t)}()")}")
	elif k == tFloat:
		src.push("\t{typeStr(tys, t)}.fromBits(r.u16())")
	elif k == tBool:
		src.push("\tr.u8() != 0")
	elif k == tStr:
		src.push("\tstr(r.bytes(r.recordCount(1)))")
	elif k == tList:
		et = innerOf(tys, t)
		if c.copiedNumbers(et):
			size = tys[et].bits / 8
			src.push("\tn = r.recordCount({size})")
			src.push("\tif not r.big or {size} == 1: return r.numbers(n, {typeStr(tys, et)}(0))")
		else:
			src.push("\tn = r.recordCount({c.leastBytes(et)})")
		src.push("\titems {tyName(i)} = []")
		src.push("\titems.reserve(n)")
		src.push("\tloop n:")
		src.push("\t\titems.push({c.readWith(et)})")
		src.push("\titems")
	elif k == tArray:
		src.push("\titems {tyName(c.noteDerive(innerOf(tys, t), 0))}[{tys[t].bits}]")
		src.push("\tfor k in 0..{tys[t].bits}:")
		src.push("\t\titems[k] = {c.readWith(innerOf(tys, t))}")
		src.push("\titems")
	elif k == tMap:
		src.push("\tn = r.recordCount(1)")
		src.push("\tm {tyName(i)} = \{}")
		src.push("\tloop n:")
		src.push("\t\tkey = {c.readWith(innerOf(tys, t))}")
		src.push("\t\tm[key] = {c.readWith(valOf(tys, t))}")
		src.push("\tm")
	elif k == tOption:
		src.push("\tif r.u8() == 0:")
		src.push("\t\tnothing {tyName(i)} = none")
		src.push("\t\treturn nothing")
		src.push("\tpresent {tyName(i)} = {c.readWith(innerOf(tys, t))}")
		src.push("\tpresent")
	elif k == tBox:
		src.push("\tBox({c.readWith(innerOf(tys, t))})")
	elif k == tStruct:
		d = declOf(tys, t)
		fts = c.fieldTypes(d)
		for f, ft in fts:
			src.push("\tg{f} = {c.readWith(ft)}")
		src.push("\t{c.structMade(i, t, d, fts.len)}")
	elif k == tEnum:
		d = declOf(tys, t)
		n = c.nodes[d].kids(c.kidIds).len
		src.push("\ttag = r.u32()")
		src.push("\tif tag >= {n}:")
		src.push("\t\tr.short = true")
		src.push("\t\ttag = 0")
		for vi in 0..n:
			vn = nodes[d].kids(kidIds)[vi]
			fts = c.fieldTypes(vn)
			last = vi == n - 1   # the tag is one of the variants'
			pad = "\t" if last else "\t\t"
			if not last:
				src.push("\tif tag == {vi}:")
			args = []
			for f, ft in fts:
				src.push("{pad}g{f} = {c.readWith(ft)}")
				args.push("g{f}")
			made = "" if fts.isEmpty else "({args.join(", ")})"
			src.push("{pad}return {tyName(i)}.{nodes[vn].text}{made}")

# T.fromBytesAt(b, at): $read at a position of the bytes, none when it ran past their end
fn writeReadAt(mut c Checker, i i64, mut src str[]):
	src.push("fn $readat{i}(b u8[], at i64) {tyName(i)}?:")
	src.push("	r = Reader(d = b, at = at)")
	src.push("	v = $read{i}(r)")
	src.push("	if r.short:")
	src.push("		return none")
	src.push("	return v")

# ---------- bits ----------

# The bits a field of type t takes in its struct's toBits: a bool one, an unsigned integer its
# width, a range type those that hold hi - lo (its value is kept as v - lo); -1 for another type
pub fn packedWidth(c Checker, t TypeId) i64:
	k = tys[t].kind
	if k == tBool: return 1
	if k != tInt: return -1
	if not tys[t].ranged: return -1 if tys[t].isSigned else tys[t].bits
	lo = tys[t].lo
	hi = tys[t].hi
	if lo < 0 and hi > 9_223_372_036_854_775_807 + lo: return -1
	span = hi - lo
	w = 0
	while w < 63 and span >> w != 0:
		w += 1
	w

# the bits all of struct t's fields take, or the first field that cannot be packed (its index
# as -1 - f)
pub fn packedBits(mut c Checker, t TypeId) i64:
	fts = c.fieldTypes(declOf(tys, t))
	total = 0
	for f, ft in fts:
		w = c.packedWidth(ft)
		if w < 0: return -1 - f
		total += w
	total

# the word a struct of `total` bits packs into
pub fn packedWord(total i64) str:
	"u32" if total <= 32 else "u64"

fn writeBits(mut c Checker, i i64, mut src str[]):
	d = declOf(tys, c.deriveTypes[i])
	fts = c.fieldTypes(d)
	word = packedWord(c.packedBits(c.deriveTypes[i]))
	src.push("fn $tobits{i}(v {tyName(i)}) {word}:")
	src.push("\tw {word} = 0")
	at = 0
	for f, ft in fts:
		width = c.packedWidth(ft)
		nm = c.fieldName(d, f)
		if width > 0 and tys[ft].kind == tBool:
			src.push("\tif v.{nm}:")
			src.push("\t\tw |= {word}(1) << {at}")
		elif width > 0:
			lo = tys[ft].lo if tys[ft].ranged else 0
			value = "v.{nm}" if lo == 0 else "v.{nm} - ({lo})"
			src.push("\tw |= {word}({value}) << {at}")
		at += width
	src.push("\tw")

fn writeUnbits(mut c Checker, i i64, mut src str[]):
	d = declOf(tys, c.deriveTypes[i])
	fts = c.fieldTypes(d)
	word = packedWord(c.packedBits(c.deriveTypes[i]))
	inits = []
	at = 0
	for f, ft in fts:
		width = c.packedWidth(ft)
		mask = u64.wrap(-1) >> (64 - width.max(1))
		raw = "(w >> {at} & {mask})"
		value = ""
		if tys[ft].kind == tBool:
			value = "{raw} != 0"
		elif not tys[ft].ranged:
			value = "{typeStr(tys, ft)}({raw})"
		elif width == 0:
			value = "{tys[ft].lo}"
		else:
			lo = tys[ft].lo
			hi = tys[ft].hi
			inner = raw if u64(hi - lo) == mask else "{raw}.min({hi - lo})"
			base = "{typeStr(tys, rangeBase(tys, ft))}({inner})"
			shifted = base if lo == 0 else "({base} + ({lo}))"
			value = "{shifted}.clamp({lo}, {hi})"
		inits.push("{c.fieldName(d, f)} = {value}")
		at += width
	src.push("fn $frombits{i}(w {word}) {tyName(i)}:")
	src.push("\t{tyName(i)}({inits.join(", ")})")

# ---------- equality and order ----------
