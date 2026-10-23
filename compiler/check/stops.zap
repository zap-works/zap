# What one node may stop the program on, and the facts that prove it does not (what a function
# may do through its calls: purity.zap; the promise noStops: options.zap). An integer's values
# lie in its type's bounds (a range type's, a narrower width's), a literal's in itself, a
# conversion's in its operand's, and arithmetic's in what its operands' give when that fits its
# type: `i64(a) + i64(b)` of two i32s never overflows, `x & 255` and `x % 16` are small. What is
# not proven is named with the fact missing.

alias nodes = c.nodes
alias tys = c.types

# the integer type e gives (read through a reference), none for any other
fn intTypeOf(mut c Checker, e NodeId) TypeId?:
	if nodes[e].ty == none: return none
	t = c.derefType(typeOf(nodes, e))
	t if c.tKind(t) == tInt else none

# the bounds of e's integer type; none for a u64, whose values pass an i64's
fn typeSpan(mut c Checker, e NodeId) Span?:
	t = try c.intTypeOf(e)
	if tys[t].bits == 64 and not tys[t].isSigned: return none
	lo, hi = intBounds(tys, t)
	Span(lo, hi)

# the values e lies in: computed from its parts when they say more, else its type's (which
# carries the ranges of arithmetic on range types, ranges.zap)
fn spanOf(mut c Checker, e NodeId) Span?:
	b = c.typeSpan(e)
	s = c.computedSpan(e) ?? return b
	if b is t:
		if s.lo >= t.lo and s.hi <= t.hi: return s
		if c.intTypeOf(e) is known and tys[known].isSigned:   # past it stops
			return Span(s.lo.max(t.lo), s.hi.min(t.hi))
		return t   # wraps: any of the type's
	s if s.lo >= 0 and s.isSpanBounded() else none

# the values e's parts give it, none when they say nothing
fn computedSpan(mut c Checker, e NodeId) Span?:
	k = nodes[e].kind
	if c.knownInt(e) is v: return spanAt(v)
	if k == nUnary and nodes[e].ival == unNeg: return negSpan(try c.spanOf(nodes[e].kids[0]))
	if k == nCall and c.bitsCount(e) is n: return Span(0, (1 << n) - 1)
	if k == nCall: return c.spanOf(try c.convertedOperand(e))
	if k != nBinary or c.intTypeOf(e) == none: return none
	op = nodes[e].ival
	a = c.spanOf(nodes[e].kids[0])
	b = c.spanOf(nodes[e].kids[1])
	if a == none and c.intTypeOf(nodes[e].kids[0]) is t and tys[t].bits == 64 and
		not tys[t].isSigned:
		return u64OpSpan(op, b ?? spanAll())
	opSpan(op, a ?? spanAll(), b ?? spanAll())

# the values op gives on a u64 of any value (past an i64's, which Span's ends are) and one in b:
# below b's top for %, inside b's for &, the u64's top shifted for >>; none when they say nothing
fn u64OpSpan(op i64, b Span) Span?:
	if not b.isSpanBounded() or b.lo < 0: return none
	if op == binMod and b.hi >= 1: return Span(0, b.hi - 1)
	if op == binBand: return Span(0, b.hi)
	if op == binShr and b.lo >= 1 and b.hi <= 63: return Span(0, spanUp >> (b.lo - 1))
	none

# whether e's values, as its parts give them (spanOf), lie in integer type t's
fn provenInside(mut c Checker, e NodeId, t TypeId):
	lo, hi = intBounds(tys, t)
	s = c.spanOf(e) ?? return false
	s.lo >= lo and s.hi <= hi

# the count of x.bits(from, count) when the compiler knows it and the bits are never negative (an
# unsigned x, or fewer than a signed one's width), else none
fn bitsCount(mut c Checker, e NodeId) i64?:
	callee = nodes[e].kids[0]
	if nodes[callee].kind != nField or nodes[callee].text != "bits" or nodes[e].kids.len != 3 or
		nodes[callee].kids.isEmpty:
		return none
	t = try c.intTypeOf(nodes[callee].kids[0])
	n = try foldedInt(nodes, nodes[e].kids[2], x: none)
	n if n >= 1 and n < 63 and (n < tys[t].bits or not tys[t].isSigned) else none

# the operand of an integer conversion call (`i32(x)`, `Percent(x)`), none for any other node
fn convertedOperand(mut c Checker, e NodeId) NodeId?:
	if nodes[e].kind != nCall or c.intTypeOf(e) == none: return none
	if nodes[e].hasFlag(flagRangeConversion): return c.argAt(e, 0)
	callee = nodes[e].kids[0]
	if nodes[callee].kind != nField or nodes[callee].text not in intConversions or
		nodes[callee].kids.isEmpty:
		return none
	x = nodes[callee].kids[0]
	x if c.intTypeOf(x) != none else none

# What e itself may stop the program on (not what is under it, nor what a function it calls
# does): the operation and the fact missing, "" when it never stops. The runtime's arithmetic,
# indexes and conversions are on the addresses, sizes and tables it keeps, inside by its own
# construction: it stops only by its own checks of what the program hands it (boundsFail, fail).
fn stopFact(mut c Checker, e NodeId):
	k = nodes[e].kind
	if k == nCall and c.isSlice(e):
		if nodes[e].hasFlag(flagInBounds) or c.walkingRuntime(): return ""
		return "a slice not proven inside its {c.showTy(c.derefType(typeOf(nodes, c.sliceList(e))))}"
	if k == nCall: return c.builtinCallStop(e)
	if c.walkingRuntime(): return ""
	if k == nBinary: return c.arithmeticStop(e)
	if k == nUnary and nodes[e].ival == unNeg: return c.negationStop(e)
	if k == nIndex: return c.indexStop(e)
	if k == nFor: return c.stepStop(nodes[e].kids[0])
	""

fn negationStop(mut c Checker, e NodeId):
	t = c.intTypeOf(e) ??
		return "" if c.floatValued(typeOf(nodes, e))
			else "a negation of a {c.showTy(typeOf(nodes, e))}"
	base = rangeBase(tys, t)
	if not tys[base].isSigned: return ""
	if c.spanOf(nodes[e].kids[0]) is s and s.lo > intMin(tys[base].bits, true): return ""
	"a negation not proven not to overflow {c.showTy(base)}"

# whether t is a float or holds floats (a list's or a vector's elements)
fn floatValued(mut c Checker, maybeT TypeId?) bool:
	t = maybeT ?? return false
	k = c.tKind(t)
	if k == tFloat or k == tSimd: return true
	(k in [tList, tVec, tArray]) and c.floatValued(tys[t].inner)

# whether the node being walked is the runtime's
fn walkingRuntime(c Checker):
	c.curMod >= 0 and c.modules[c.curMod].id == "rt"

# what an operation on values of no integer type stops on: nothing for floats and texts
fn notIntegerStop(mut c Checker, e NodeId, what str):
	if c.floatValued(typeOf(nodes, e)) or c.tKind(typeOf(nodes, e)) == tStr: return ""
	"{what} on {c.showTy(typeOf(nodes, e))} not proven not to overflow"

fn arithmeticStop(mut c Checker, e NodeId):
	op = nodes[e].ival
	if op > binMatmul and op != binShl and op != binShr or nodes[e].hasFlag(flagWrap): return ""
	what = "a {binName(op)}"
	if nodes[e].hasFlag(flagInBounds): return ""   # a sum of an index (lengths.zap)
	t = c.intTypeOf(e) ?? return c.notIntegerStop(e, what)
	base = rangeBase(tys, t)
	bits = tys[base].bits
	signed = tys[base].isSigned
	right = c.spanOf(nodes[e].kids[1])
	if op == binShl or op == binShr:
		if right is s and s.lo >= 0 and s.hi < bits: return ""
		return "{what} whose count is not proven inside 0..{bits}"
	if op == binDiv or op == binMod:
		d = right ?? Span(-1, 1)
		if d.lo <= 0 and d.hi >= 0: return "{what} whose divisor is not proven not 0"
		if op == binMod or not signed or d.lo > -1 or d.hi < -1: return ""
		if c.spanOf(nodes[e].kids[0]) is n and n.lo > intMin(bits, true): return ""
		return "{what} whose divisor is not proven not -1 nor its dividend not {intMin(bits, true)}"
	if op == binPow or op == binMatmul: return "{what} of integers not proven not to overflow"
	if not signed: return ""   # + - * of unsigned integers wrap
	lo, hi = intBounds(tys, base)
	if c.computedSpan(e) is s and s.isSpanBounded() and s.lo >= lo and s.hi <= hi: return ""
	"{what} not proven not to overflow {c.showTy(base)}"

fn indexStop(mut c Checker, e NodeId):
	if nodes[e].kids.len < 2: return "an index"
	ct = c.derefType(typeOf(nodes, nodes[e].kids[0]))
	at = nodes[e].kids[1]
	if c.tKind(ct) == tMap:
		return "a map's [k], which stops when k is absent (get(k) ?? fallback does not)"
	if nodes[at].kind == nRange: return "a slice not proven inside its {c.showTy(ct)}"
	if nodes[e].hasFlag(flagInBounds): return ""
	if c.tKind(ct) == tArray:
		if c.spanOf(at) is s and s.lo >= 0 and s.hi < tys[ct].bits: return ""
		return "an index not proven inside 0..{tys[ct].bits}"
	"an index not proven inside its {c.showTy(ct)}"

# whether e is the checker's call for xs[lo..hi], which the backend checks in place
fn isSlice(c Checker, e NodeId):
	if not nodes[e].hasFlag(flagInternal) or nodes[e].kids.isEmpty: return false
	callee = nodes[e].kids[0]
	nodes[callee].text == "slice" and nodes[callee].kind == nField and nodes[e].kids.len == 3 or
		nodes[callee].text == "rt__listSlice" and nodes[e].kids.len == 4

# the list a slice's call cuts
fn sliceList(c Checker, e NodeId):
	callee = nodes[e].kids[0]
	nodes[callee].kids[0] if nodes[callee].kind == nField else nodes[e].kids[1]

# a for over a range with a step stops when the step is not positive
fn stepStop(mut c Checker, iter NodeId):
	if nodes[iter].kind != nRange or nodes[iter].kids.len < 3: return ""
	if c.spanOf(nodes[iter].kids[2]) is s and s.lo > 0: return ""
	"a range whose step is not proven positive"

# the methods of an integer that never stop
quietIntMethods = ["min", "max", "hash"]

# a call the analysis knows no function for: a size read, a raw intrinsic of the runtime, a
# number's method that gives no integer or keeps it inside, and a conversion that wraps or whose
# operand fits never stop; anything else may
fn builtinCallStop(mut c Checker, e NodeId):
	callee = nodes[e].kids[0]
	m = nodes[callee].text
	if nodes[callee].hasFlag(flagSize) or nodes[e].hasFlag(flagWrap) or
		nodes[e].hasFlag(flagInBounds):
		return ""   # a loadWord proven inside (lengths.zap)
	if c.isVariantOf(c.derefType(typeOf(nodes, e)), m): return ""   # an enum's variant made
	if nodes[callee].kind == nIdent and nodes[e].kids.len == 2 and
		isDefined(tys, typeOf(nodes, e)) and
		c.tKind(underlying(tys, typeOf(nodes, e))) != tInt:
		return ""   # a defined type made of its base's value (`Image(grid)`)
	if nodes[callee].kind == nIdent:
		if endsProgram(m): return "{m[4..] if m.startsWith("rt__") else m}, which ends the program"
		if m.startsWith("__") and m != "__callRec": return ""
		return "a call of {m}, whose checks are not known"
	if c.walkingRuntime(): return ""
	t = c.intTypeOf(e)
	if c.convertedOperand(e) is x:
		into = t ?? return ""
		from = c.intTypeOf(x) ?? return ""
		if not tys[into].ranged and tys[into].bits >= tys[from].bits: return ""
		if c.provenInside(x, into): return ""
		return "a conversion into {c.showTy(into)} not proven inside it"
	if nodes[callee].kind != nField or nodes[callee].kids.isEmpty:
		return "a call of {m}, whose checks are not known"
	recv = nodes[callee].kids[0]
	if m == "copy" or m == "take": return ""   # a value copied or moved out (memory is no stop)
	if c.floatValued(typeOf(nodes, recv)) and t == none: return ""   # a float's method giving a float
	if m.len > 2 and conversionMethod(conversionType(m)) == m:
		if t == none: return ""   # an integer into a float
		return "a conversion of a {c.showTy(c.derefType(typeOf(nodes, recv)))} into {c.showTy(t)}"
	if c.intTypeOf(recv) != none:
		if m in quietIntMethods or m in intBitMethods: return ""
		if m in bitFieldMethods:
			positions = nodes[e].kids[1..(2 if m == "bit" or m == "withBit" else 3)]
			if positions.all(foldedInt(nodes, it, x: none) != none): return ""   # checked by the checker
			return "bit positions not known to lie inside the width"
		if m == "abs" and t is t and c.spanOf(recv) is s and
			s.lo > intMin(tys[rangeBase(tys, t)].bits, true):
			return ""
	"a call of {m}, whose checks are not known"

# A for over lo..hi (lo a literal not below 0) proves its variable i an index inside: of xs in
# each xs[i] when hi is xs.len (xs a list or a text named by a variable or its fields) and the
# body leaves xs's length alone; of a fixed array of at least hi elements when hi is a literal.
# The xs[i] marked (flagInBounds) are those in the body outside a lambda, which may run after
# the loop; none when the body binds i or xs's name again. Read once the body is checked.
type LoopIndex:
	index str   # the loop's variable
	name str   # xs's root variable ("" for none)
	path str   # xs below it (".items")
	bare str = ""   # xs's root as written, when it is a field named bare (name is then self)
	upTo i64   # hi as a literal (0 for none)

fn proveLoopIndexes(mut c Checker, s NodeId):
	iter = nodes[s].kids[0]
	if nodes[iter].kind != nRange or nodes[iter].kids.len < 2 or nodes[s].text == "_": return
	lo = nodes[iter].kids[0]
	hi = nodes[iter].kids[1]
	if nodes[lo].kind != nInt or nodes[lo].text.startsWith("-"): return
	walk = LoopIndex(index = nodes[s].text.copy(), name = "", path = "", upTo = 0)
	if nodes[hi].kind == nInt:
		walk.upTo = i64.parse(nodes[hi].text) ?? 0
	place = c.lenReceiver(hi)
	if place is place and c.tKind(c.derefType(typeOf(nodes, place))) in [tList, tStr]:
		found, path = c.placePath(place)
		if found is root and not nodes[root].hasFlag(flagModuleVar):
			name, under = c.selfPlace(nodes[root].text, path)
			if name != nodes[root].text: walk.bare = nodes[root].text.copy()
			walk.name = name
			walk.path = under
	if walk.name == "" and walk.upTo <= 0: return
	body = nodes[s].sub[0]
	if c.mayChangeLength(body, walk): return
	c.markInBounds(body, walk)

# whether e may change the length of the loop's list (changing it or what holds it, or a call
# whose body is not known), or binds or changes its variable or the list's name
fn mayChangeLength(mut c Checker, e NodeId, walk LoopIndex) bool:
	k = nodes[e].kind
	names = [walk.index.copy(), walk.name.copy(), walk.bare.copy()]
	if k in [nLet, nFor, nPattern, nArm, nLambda] and
		(nodes[e].text in names or nodes[e].names.any(it in names)):
		return true
	if k == nCall and
		(nodes[e].hasFlag(flagClosure) or nodes[nodes[e].kids[0]].names2().any(it in names)):
		return true   # a function value's call, a local lambda changing the name
	for p in c.placesChanged(e):
		found, under = c.placePath(c.placeUnder(p))
		r = found ?? continue
		name, at = c.selfPlace(nodes[r].text, under)
		if nodes[r].text == walk.index or name == walk.name and walk.path.startsWith(at):
			return true
	nodes[e].kids.any(c.mayChangeLength(it, walk)) or nodes[e].sub.any(c.mayChangeLength(it, walk))

# a place's root variable and path, a field named bare in a method's body spelled through self
# (`items` is `self.items`), as what a method's call changes names it
fn selfPlace(c Checker, root str, path str):
	("self", ".{root}{path}") if c.isBareField(root) else (root.copy(), path.copy())

fn markInBounds(mut c Checker, e NodeId, walk LoopIndex):
	if nodes[e].kind == nLambda: return
	if nodes[e].kind == nIndex and nodes[e].kids.len == 2 and
		nodes[nodes[e].kids[1]].kind == nIdent and nodes[nodes[e].kids[1]].text == walk.index:
		found, under = c.placePath(nodes[e].kids[0])
		name = ""
		p = ""
		if found is r:
			name, p = c.selfPlace(nodes[r].text, under)
		at = c.derefType(typeOf(nodes, nodes[e].kids[0]))
		if found != none and name == walk.name and p == walk.path or
			walk.upTo > 0 and c.tKind(at) == tArray and tys[at].bits >= walk.upTo:
			nodes[e].flags |= flagInBounds
	for kid in nodes[e].kids:
		c.markInBounds(kid, walk)
	for sb in nodes[e].sub:
		c.markInBounds(sb, walk)
