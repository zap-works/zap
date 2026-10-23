# A bits type (`type Status bits u8:`, spec 3.2): a type defined over an unsigned integer whose
# fields name its bits, a bool one bit (`n bool = 7`) and an unsigned integer a range of them, low
# to high, its end left out (`mode u8 = 0..3`). In memory it is the integer; the checker writes its
# uses over as the integer's bit methods (checkBitFieldMethod), so the backend sees shifts and masks:
#   s.n, s.mode              s.bit(7), s.bits(0, 3) (converted to the field's type)
#   s.n = v, s.mode = v      s = Status(s.withBit(7, v)), s = Status(s.withBits(0, 3, v))
#   Status(n = true)         Status(u8(0).withBit(7, true)): a field left out is 0

alias nodes = c.nodes
alias tys = c.types

# the declaration of t when t is a bits type, else none
fn bitsDecl(c Checker, maybeT TypeId?) NodeId?:
	t = try maybeT
	d = try tys[t].defined
	d if nodes[d].kind == nStructDecl and not nodes[d].kids.isEmpty else none

# the first bit and the count of bits field f names (count 0 when it names none: reported by
# checkBitsDecl)
fn bitsOfField(c Checker, f NodeId):
	v = nodes[f].kids[0]
	if nodes[v].kind == nInt: return (checkedLiteral(nodes[v].text) ?? 0, 1)
	if nodes[v].kind != nRange or nodes[v].kids.len != 2: return (0, 0)
	lo = nodes[nodes[v].kids[0]]
	hi = nodes[nodes[v].kids[1]]
	if lo.kind != nInt or hi.kind != nInt: return (0, 0)
	from = checkedLiteral(lo.text) ?? 0
	(from, (checkedLiteral(hi.text) ?? 0) - from)

# A bits type's base is an unsigned integer; each field a bool at one bit or an unsigned integer
# that holds its range, inside the base's width and sharing no bit with another field.
fn checkBitsDecl(mut c Checker, d NodeId):
	base = underOf(tys, c.aliasedType(d))
	if c.tKind(base) != tInt or tys[base].isSigned or tys[base].ranged or isDefined(tys, base):
		c.errorAt(nodes[d].line, nodes[d].col, compileError("BitsBase", ["{c.showTy(base)}"]))
		return
	used u64 = 0
	for f in nodes[d].kids:
		ft = c.resolveType(nodes[f].types[0])
		from, count = c.bitsOfField(f)
		line = nodes[f].line
		col = nodes[f].col
		single = nodes[nodes[f].kids[0]].kind == nInt
		holds = ft == tyBool and single or not single and c.tKind(ft) == tInt and
			not tys[ft].isSigned and not tys[ft].ranged and not isDefined(tys, ft) and
			count <= tys[ft].bits and tys[ft].bits <= tys[base].bits
		if count < 1 or not holds:
			c.errorAt(line, col, compileError("BitsField", ["{nodes[f].text}"]))
			continue
		if from < 0 or from + count > tys[base].bits:
			c.errorAt(
				line,
				col,
				compileError("BitsOutside", ["{from}..{from + count}", "{c.showTy(base)}"])
			)
			continue
		mask = (u64.wrap(-1) >> (64 - count)) << from
		if used & mask != 0:
			other = nodes[d].kids.find(c.bitsOverlap(it, mask)) ?? f
			c.errorAt(
				line,
				col,
				compileError("BitsOverlap", ["{nodes[f].text}", "{nodes[other].text}"])
			)
		used |= mask

# whether bits field f takes a bit of mask
fn bitsOverlap(c Checker, f NodeId, mask u64):
	from, count = c.bitsOfField(f)
	count >= 1 and from >= 0 and from + count <= 64 and
		((u64.wrap(-1) >> (64 - count)) << from) & mask != 0

# s.f of bits type t declared by d: s.bit(n), or s.bits(from, count) as the field's type
fn checkBitsField(mut c Checker, e NodeId, d NodeId, t TypeId, expected TypeId?) TypeId:
	f = c.kidNamed(d, nodes[e].text) ??
		return c.errorTyped(
			nodes[e].line,
			nodes[e].col,
			compileError("NoField", ["{c.showTy(t)}", "{nodes[e].text}"])
		)
	ft = c.resolveType(nodes[f].types[0])
	read = c.bitsCall(f, nodes[e].kids[0], "bit" if ft == tyBool else "bits", none)
	if ft != tyBool and not isSameType(tys, ft, underOf(tys, t)):
		conversion = newNode(
			nodes,
			nField,
			nodes[e].line,
			nodes[e].col,
			text = conversionMethod(c.showTy(ft)),
			kids = [read]
		)
		read = newNode(nodes, nCall, nodes[e].line, nodes[e].col, kids = [conversion])
	nodes[e].kind = nCall
	nodes[e].text = ""
	nodes[e].kids = nodes[read].kids.copy()
	c.checkExpr(e, expected)

# x.m(from[, count][, value]) for bits field f: m is bit or bits, or withBit or withBits given
# the value
fn bitsCall(mut c Checker, f NodeId, x NodeId, m str, value NodeId?):
	line = nodes[x].line
	col = nodes[x].col
	from, count = c.bitsOfField(f)
	callee = newNode(nodes, nField, line, col, text = m.copy(), kids = [x])
	call = newNode(nodes, nCall, line, col, kids = [callee, c.intNode(from, line, col)])
	if not m.endsWith("Bit") and m != "bit":
		nodes[call].kids.push(c.intNode(count, line, col))
	if value is value:
		nodes[call].kids.push(value)
	call

fn intNode(mut c Checker, v i64, line i64, col i64) NodeId:
	newNode(nodes, nInt, line, col, text = "{v}")

# s.f = v, s of a bits type, made s = S(s.withBit(n, v)) (or withBits), before the assignment s is
# checked; false when the target is no bits field
fn bitsAssign(mut c Checker, s NodeId):
	target = nodes[s].kids[0]
	if nodes[target].kind != nField or nodes[target].kids.len != 1 or nodes[target].text2 != "":
		return false
	obj = nodes[target].kids[0]
	t = c.placeType(obj, elements = true) ?? return false
	d = c.bitsDecl(t) ?? return false
	f = c.kidNamed(d, nodes[target].text) ?? return false
	line = nodes[s].line
	col = nodes[s].col
	m = "withBit" if c.resolveType(nodes[f].types[0]) == tyBool else "withBits"
	set = c.bitsCall(f, cloneTree(nodes, obj), m, nodes[s].kids[1])
	nodes[set].flags |= flagInternal   # the value first (irBitField)
	nodes[s].kids = [obj, c.bitsMade(d, set, line, col)]
	true

# value, of a bits type's base, as the bits type declared by d: a conversion naming it by its
# global name (aliasCalled)
fn bitsMade(mut c Checker, d NodeId, value NodeId, line i64, col i64) NodeId:
	name = newNode(nodes, nIdent, line, col, text = nodes[d].text.copy())
	nodes[name].text2 = globalAlias
	newNode(nodes, nCall, line, col, kids = [name, value])

# Status(n = true, c = false), Status(n, c) of names like the fields (as a struct's literal takes
# them), or Status(): the base's 0 with each named field set, made the bits type; false when the
# call is a conversion (one value, naming no field)
fn bitsLiteral(mut c Checker, e NodeId, d NodeId, t TypeId):
	n = c.argCount(e)
	if n == 1 and c.bitsFieldNamed(d, c.argAt(e, 0)) == none and
		nodes[c.argAt(e, 0)].kind != nNamedArg:
		return false
	line = nodes[e].line
	col = nodes[e].col
	zero = newNode(
		nodes,
		nField,
		line,
		col,
		text = conversionMethod(c.showTy(underOf(tys, t))),
		kids = [c.intNode(0, line, col)]
	)
	made = newNode(nodes, nCall, line, col, kids = [zero])
	for i in 0..n:
		arg = c.argAt(e, i)
		if c.bitsFieldNamed(d, arg) is f:
			m = "withBit" if c.resolveType(nodes[f].types[0]) == tyBool else "withBits"
			value = nodes[arg].kids[0] if nodes[arg].kind == nNamedArg else arg
			made = c.bitsCall(f, made, m, value)
		else:
			c.errorAt(
				nodes[arg].line,
				nodes[arg].col,
				compileError("NoField", ["{c.showTy(t)}", "{nodes[arg].text}"])
			)
	nodes[e].kids = [nodes[e].kids[0], made]
	true

# the field of bits type declaration d an argument names: `n = v`, or a name like the field's
fn bitsFieldNamed(c Checker, d NodeId, arg NodeId) NodeId?:
	k = nodes[arg].kind
	c.kidNamed(d, nodes[arg].text) if k == nNamedArg or k == nIdent else none
