# Ranges carried through arithmetic (spec 3.1): the values an integer operation gives, computed
# from its operands' values. The checker writes them in the result's type (carriedType), so a sum
# of two values in 0..=a and 0..=b is an `i64 in 0..=a + b`; the analyses that prove a value inside
# (stops.zap, the backend's checks) read them back from the types.

# the values an integer lies in, lo..=hi; below (above) when it has no bound on that side, lo
# (hi) then the i64's own end
import fold

pub type Span:
	lo i64
	hi i64
	below bool = false
	above bool = false

spanUp = 9_223_372_036_854_775_807
spanDown = -9_223_372_036_854_775_807 - 1

# a span of one value
pub fn spanAt(v i64) Span:
	Span(v, v)

# the span with no bound on either side
fn spanAll():
	Span(spanDown, spanUp, below = true, above = true)

# the span of integer type t computed in integer type base (t's or a wider one): its range, or
# its width's bounds; a bound at base's own end stands for no bound (n64's top is no limit a sum
# keeps under)
pub fn typeSpanIn(ts Ty[], t TypeId, base TypeId) Span:
	lo, hi = intBounds(ts, t)
	least, most = intBounds(ts, rangeBase(ts, base))
	Span(
		spanDown if lo == least else lo,
		spanUp if hi == most else hi,
		below = lo == least,
		above = hi == most
	)

# whether s has a bound on both sides
pub fn isSpanBounded(s Span) bool:
	not s.below and not s.above

# one end of a span: a value, or no bound (inf, the value then i64's end on its side)
type End:
	v i64
	inf bool

fn ends(s Span):
	(End(s.lo, s.below), End(s.hi, s.above))

fn spanOf2(lo End, hi End):
	Span(lo.v, hi.v, below = lo.inf, above = hi.inf)

# no bound, toward up or down
fn endless(up bool):
	End(spanUp if up else spanDown, true)

fn endAdd(x End, y End):
	if x.inf: return x
	if y.inf: return y
	if y.v > 0 and x.v > spanUp - y.v: return endless(true)
	if y.v < 0 and x.v < spanDown - y.v: return endless(false)
	End(x.v + y.v, false)

fn endNeg(x End):
	if x.inf: return endless(x.v < 0)
	if x.v == spanDown: return endless(true)
	End(-x.v, false)

fn endMul(x End, y End):
	if not x.inf and x.v == 0 or not y.inf and y.v == 0: return End(0, false)
	negative = (x.v < 0) != (y.v < 0)
	if x.inf or y.inf or x.v == spanDown or y.v == spanDown: return endless(not negative)
	if x.v.abs() > spanUp / y.v.abs(): return endless(not negative)
	End(x.v * y.v, false)

# x / y truncated, y not 0
fn endDiv(x End, y End):
	if y.inf: return End(0, false)
	if x.inf: return endless((x.v < 0) == (y.v < 0))
	End(x.v / y.v, false)

# the least and the most of ends
fn endsLeast(xs End[]):
	best = xs[0]
	for x in xs:
		if x.v < best.v or x.v == best.v and x.inf: best = x
	best

fn endsMost(xs End[]):
	best = xs[0]
	for x in xs:
		if x.v > best.v or x.v == best.v and x.inf: best = x
	best

fn endMin(x End, y End):
	endsLeast([x, y])

fn endMax(x End, y End):
	endsMost([x, y])

# the values a op b gives (+ - * / % & | ^ >> and min, max), none when they say nothing; a divisor
# that may be 0 is taken as at least 1, since a division by 0 stops
pub fn opSpan(op i64, a Span, b Span) Span?:
	alo, ahi = a.ends()
	blo, bhi = b.ends()
	if op == binAdd: return alo.endAdd(blo).spanOf2(ahi.endAdd(bhi))
	if op == binSub: return alo.endAdd(bhi.endNeg()).spanOf2(ahi.endAdd(blo.endNeg()))
	if op == binMul:
		products = [alo.endMul(blo), alo.endMul(bhi), ahi.endMul(blo), ahi.endMul(bhi)]
		return endsLeast(products).spanOf2(endsMost(products))
	if op == binDiv:
		if b.lo < 0: return none
		dlo = End(b.lo.max(1), false)
		dhi = bhi if bhi.inf else End(b.hi.max(1), false)
		lo = alo.endDiv(dhi) if a.lo >= 0 else alo.endDiv(dlo)
		hi = ahi.endDiv(dlo) if a.hi >= 0 else ahi.endDiv(dhi)
		return lo.spanOf2(hi)
	if op == binMod:
		# |a % b| < |b| and <= |a|, with a's sign
		top = blo.endNeg().endMax(bhi)
		m = top if top.inf else End(top.v - 1, false)
		lo = alo.endMax(m.endNeg()) if a.lo < 0 else End(0, false)
		hi = ahi.endMin(m) if a.hi > 0 else End(0, false)
		return lo.spanOf2(hi)
	if op == binBand:
		if a.lo >= 0 and b.lo >= 0: return spanOf2(End(0, false), ahi.endMin(bhi))
		if a.lo >= 0: return spanOf2(End(0, false), ahi)
		if b.lo >= 0: return spanOf2(End(0, false), bhi)
		return none
	if op == binBor or op == binBxor:
		if a.lo < 0 or b.lo < 0: return none
		top = ahi.endMax(bhi)
		if top.inf: return Span(0, spanUp, above = true)
		ones = 0
		while ones < top.v:
			ones = ones * 2 + 1
		return Span(a.lo.max(b.lo) if op == binBor else 0, ones)
	if op == binShr:
		if b.lo < 0 or b.hi > 63 or b.above: return none
		if a.lo >= 0: return Span(a.lo >> b.hi, a.hi >> b.lo, above = a.above and b.lo == 0)
		# an arithmetic shift: a negative value goes up toward -1 as the count grows
		return Span(
			a.lo >> b.lo,
			a.hi >> (b.lo if a.hi >= 0 else b.hi),
			below = a.below and b.lo == 0,
			above = a.above and b.lo == 0
		)
	if op == binShl:
		if a.lo < 0 or a.above or b.lo < 0 or b.hi > 62 or b.above or a.hi > spanUp >> b.hi:
			return none
		return Span(a.lo << b.lo, a.hi << b.hi)
	none

# the values a.min(b) and a.max(b) give
pub fn minSpan(a Span, b Span) Span:
	alo, ahi = a.ends()
	blo, bhi = b.ends()
	alo.endMin(blo).spanOf2(ahi.endMin(bhi))

pub fn maxSpan(a Span, b Span) Span:
	alo, ahi = a.ends()
	blo, bhi = b.ends()
	alo.endMax(blo).spanOf2(ahi.endMax(bhi))

# the values -a gives
pub fn negSpan(a Span) Span:
	alo, ahi = a.ends()
	ahi.endNeg().spanOf2(alo.endNeg())

# the type a value of span s has in integer type base: the range s inside base's bounds (none
# when it holds them all). A signed result past its type stops the program (6.6), so its range is
# cut at the type's end; an unsigned one wraps, so it keeps a range only when it lies inside.
pub fn spanType(mut ts Ty[], mut known {str: TypeId}, base TypeId, s Span) TypeId:
	least, most = intBounds(ts, base)
	if not ts[base].isSigned and (s.lo < least or s.hi > most): return base
	lo = s.lo.max(least)
	hi = s.hi.min(most)
	if lo == least and hi == most or lo > hi: return base
	key = "{ts[base].bits} {ts[base].isSigned} {lo} {hi}"
	if known.get(key) is t:
		if typesPast >= 0 and i64(t) >= typesPast: spansAsked.push([i64(base), lo, hi, i64(t), 0])
		return t
	t = tyRange(ts, base, lo, hi)
	known[key] = t
	if typesPast >= 0: spansAsked.push([i64(base), lo, hi, i64(t), 1])
	t

alias nodes = c.nodes
alias tys = c.types

# whether arithmetic op on integers of types lt and rt carries a range: either is a range type,
# or op narrows a signed value (`x % 16`, `x & 255`)
fn carries(c Checker, lt TypeId, rt TypeId, op i64):
	if c.tKind(lt) != tInt or c.tKind(rt) != tInt or isDefined(tys, lt) or isDefined(tys, rt) or
		tys[lt].param != "" or tys[rt].param != "":
		return false
	tys[lt].ranged or tys[rt].ranged or
		tys[rangeBase(tys, lt)].isSigned and (op == binMod or op == binBand)

# the type op on l (of type lt) and r (rt) gives, computed in integer type res: the range their
# values give it (spec 3.1), else res's base
fn carriedType(mut c Checker, op i64, l NodeId, lt TypeId, r NodeId, rt TypeId, res TypeId) TypeId:
	base = rangeBase(tys, res)
	if c.tKind(res) != tInt or not c.carries(lt, rt, op): return base
	s = opSpan(op, c.operandSpan(l, lt, base), c.operandSpan(r, rt, base)) ?? return base
	spanType(tys, c.rangeTypes, base, s)

# the value of e when it is known compiling: a literal, arithmetic of literals, a name of an
# immutable local or a constant bound to one, arithmetic of those (the value kept in the node's
# origin by the checker)
fn knownInt(c Checker, e NodeId) i64?:
	if foldedInt(nodes, e, x: none) is v: return v
	if nodes[e].kind != nIdent and nodes[e].kind != nBinary: return none
	foldedInt(nodes, try nodes[e].origin, x: none)

# integer arithmetic e of known values (`(1 << fastBits) - 1`): its value kept in its origin
fn noteKnownValue(mut c Checker, e NodeId):
	if nodes[e].kind != nBinary or c.tKind(typeOf(nodes, e)) != tInt: return
	nodes[e].origin = none
	l = nodes[e].kids[0]
	r = nodes[e].kids[1]
	if nodes[l].kind == nInt and nodes[r].kind == nInt: return   # folded as it is
	a = c.knownInt(l) ?? return
	b = c.knownInt(r) ?? return
	v = fold.intOp(binName(nodes[e].ival), a, b, tys[rangeBase(tys, typeOf(nodes, e))].bits) ??
		return
	nodes[e].origin = newNode(nodes, nInt, nodes[e].line, nodes[e].col, text = "{v}")

# the values e, an integer of type t, has as an operand computed in base: a literal's own, a
# widening's (written or the checker's) its operand's, else its type's
fn operandSpan(mut c Checker, e NodeId, t TypeId, base TypeId) Span:
	if c.knownInt(e) is v: return spanAt(v)
	x = c.unwidened(e)
	from NodeId? = x if x != e else c.convertedOperand(e)
	if from is from and nodes[from].ty != none:
		ft = c.derefType(typeOf(nodes, from))
		if c.tKind(ft) == tInt and tys[ft].bits <= tys[base].bits and
			(tys[ft].isSigned or tys[ft].bits < tys[base].bits):
			return c.operandSpan(from, ft, base)   # the same value, in a type as wide or wider
	typeSpanIn(tys, t, base)

# the type x.min(y) or x.max(y) (m) gives, x of type xt and y of yt: the range of their values
fn extremeType(mut c Checker, m str, x NodeId, xt TypeId, y NodeId, yt TypeId) TypeId:
	if c.tKind(xt) != tInt or not c.carries(xt, yt, binAdd) and
		not (tys[rangeBase(tys, xt)].isSigned and nodes[y].kind == nInt):
		return xt
	base = rangeBase(tys, xt)
	a = c.operandSpan(x, xt, base)
	b = c.operandSpan(y, yt, base)
	spanType(tys, c.rangeTypes, base, a.minSpan(b) if m == "min" else a.maxSpan(b))

# the type a choice among the integer values vs and a value of type also, if any, gives (a
# match's arms, a range's bounds, `x ?? fallback`): the range holding all their values, none
# when they are not integers of one base
fn joinedInts(mut c Checker, vs NodeId[], also TypeId?) TypeId?:
	base TypeId? = none
	lo = spanUp
	hi = spanDown
	if also is also:
		if c.tKind(also) != tInt or isDefined(tys, also) or tys[also].param != "": return none
		b = rangeBase(tys, also)
		base = b
		s = typeSpanIn(tys, also, b)
		lo = s.lo
		hi = s.hi
	for v in vs:
		t = c.derefType(typeOf(nodes, v))
		if c.tKind(t) != tInt or isDefined(tys, t) or tys[t].param != "": return none
		b = base ?? rangeBase(tys, t)
		if not isSameType(tys, b, rangeBase(tys, t)): return none
		base = b
		s = c.operandSpan(v, t, b)
		lo = lo.min(s.lo)
		hi = hi.max(s.hi)
	b = try base
	spanType(tys, c.rangeTypes, b, Span(lo, hi))

# the type of the variable of a for over the range iter of integer type base: the values from
# its start to before its end (from its start down to after its end with a negative step)
fn loopVarType(mut c Checker, iter NodeId, base TypeId) TypeId:
	if c.tKind(base) != tInt or isDefined(tys, base): return base
	from = c.operandSpan(nodes[iter].kids[0], c.derefType(typeOf(nodes, nodes[iter].kids[0])), base)
	to = c.operandSpan(nodes[iter].kids[1], c.derefType(typeOf(nodes, nodes[iter].kids[1])), base)
	# the end is never reached: past the type's own end it is that end (i + 1 fits)
	least, most = intBounds(tys, base)
	if nodes[iter].kids.len > 2 and nodes[nodes[iter].kids[2]].text.startsWith("-") or
		nodes[iter].kids.len > 2 and nodes[nodes[iter].kids[2]].kind == nUnary:
		return spanType(tys, c.rangeTypes, base, Span(to.lo.max(least) + 1, from.hi))
	spanType(tys, c.rangeTypes, base, Span(from.lo, to.hi.min(most) - 1))

# the type a place inferred from a value of type t holds (a `mut` binding, a list's element, a
# type parameter): an integer range's base, so the place takes any value of it
fn heldType(c Checker, t TypeId):
	rangeBase(tys, t) if c.tKind(t) == tInt and not isDefined(tys, t) and tys[t].param == "" else t

# A check just made proves a value inside a range: in the block an `if` runs when its condition
# holds (or, in its else, fails), and after an `if` whose block leaves, an immutable integer
# variable the condition compares (`x < 100`, `0 <= i and i < n`) reads as the range the
# comparison leaves it (`if x < 100: p Percent = x`).

# the variables cond narrows when it holds (truth) or fails, each the name read as a narrower
# range, in the current scope (unless only lengths), and the lengths it checks (lengths.zap)
fn narrowBy(mut c Checker, cond NodeId, truth bool, onlyLengths bool = false):
	k = nodes[cond].kind
	if k == nUnary and nodes[cond].ival == unNot:
		c.narrowBy(nodes[cond].kids[0], not truth, onlyLengths)
		return
	if k != nBinary:
		c.noteEmptyCheck(cond, truth)
		return
	op = nodes[cond].ival
	l = nodes[cond].kids[0]
	r = nodes[cond].kids[1]
	if op == binAnd and truth or op == binOr and not truth:
		c.narrowBy(l, truth, onlyLengths)
		c.narrowBy(r, truth, onlyLengths)
		return
	if op < binEq or op > binGe: return
	held = op if truth else negatedComparison(op)
	c.noteLengthCheck(held, l, r)
	if onlyLengths: return
	c.narrowVar(l, held, r)
	c.narrowVar(r, mirroredComparison(held), l)

# `n < 0` of a natural or an unsigned integer is always false (`n >= 0` always true): an error, as
# it tests nothing (what a sentinel below 0 meant is an optional, `n?`)
fn rejectDecidedComparison(mut c Checker, e NodeId, op i64):
	if nodes[e].hasFlag(flagInternal): return
	l = nodes[e].kids[0]
	r = nodes[e].kids[1]
	x = l
	held = op
	if (c.knownInt(l) ?? 1) == 0 and c.knownInt(r) == none:
		x = r
		held = mirroredComparison(op)
	elif (c.knownInt(r) ?? 1) != 0:
		return
	if held != binLt and held != binGe: return
	written = c.derefType(typeOf(nodes, c.unwidened(x)))
	t = underlying(tys, written) if isDefined(tys, written) else written   # (NodeId: n32)
	if not (
		t == tyN32 or t == tyN64 or c.tKind(t) == tInt and not tys[t].isSigned and not tys[t].ranged
	):
		return
	c.errorAt(
		nodes[e].line,
		nodes[e].col,
		compileError(
			"ComparisonDecided",
			["{c.showTy(written)}", "false" if held == binLt else "true"]
		)
	)

# the comparison that holds when op fails
fn negatedComparison(op i64):
	if op == binLt: binGe elif op == binGe: binLt elif op == binGt: binLe elif op == binLe: binGt
	elif op == binNe: binEq else: binNe

# op with its sides swapped (a < b is b > a)
fn mirroredComparison(op i64):
	if op == binLt: binGt elif op == binGt: binLt elif op == binLe: binGe elif op == binGe: binLe
	else: op

# x, when it names an immutable integer variable, read as the range `x op other` leaves it
fn narrowVar(mut c Checker, widened NodeId, op i64, other NodeId):
	x = c.unreferenced(c.unwidened(widened))
	if nodes[x].kind != nIdent or op < binEq or op > binGe or op == binNe: return
	v = c.lookupVar(nodes[x].text)
	if v < 0 or c.vars[v].isMut or c.vars[v].isField or c.vars[v].literal != none or
		c.vars[v].row >= 0:
		return
	lent = c.tKind(c.vars[v].ty) == tRef and tys[c.vars[v].ty].bits == 0   # `ref xs[i]`: its value
	xt = innerOf(tys, c.vars[v].ty) if lent else c.vars[v].ty
	ot = c.derefType(typeOf(nodes, other))
	if c.tKind(xt) != tInt or c.tKind(ot) != tInt or isDefined(tys, xt) or tys[xt].param != "":
		return
	base = rangeBase(tys, xt)
	if not isSameType(tys, rangeBase(tys, ot), base) or isDefined(tys, ot): return
	was = typeSpanIn(tys, xt, base)
	by = c.operandSpan(other, ot, base)
	lo = was.lo
	hi = was.hi
	if op == binLt and by.hi > spanDown: hi = hi.min(by.hi - 1)
	if op == binLe or op == binEq: hi = hi.min(by.hi)
	if op == binGt and by.lo < spanUp: lo = lo.max(by.lo + 1)
	if op == binGe or op == binEq: lo = lo.max(by.lo)
	if lo > hi or lo == was.lo and hi == was.hi: return
	ranged = spanType(tys, c.rangeTypes, base, Span(lo, hi))
	t = tyRef(tys, ranged, false) if lent else ranged
	if v >= c.scopeStarts[len - 1]:
		c.vars[v].ty = t   # a name of this scope: read so from here on
		return
	narrowed = c.vars[v].copy()
	narrowed.ty = t
	narrowed.isParam = true   # read where the variable is: its own unused check stands
	narrowed.narrowed = true
	c.varIndex.noteName(narrowed.name, c.vars.len)
	c.vars.push(narrowed)

# the block b checked with what cond's holding (truth) or failing proves
fn checkNarrowed(mut c Checker, b NodeId, cond NodeId, truth bool):
	c.enterScope()
	c.narrowBy(cond, truth)
	c.checkBlock(b)
	c.exitScope()

# whether argument i of call e, of type t, is of type want or a range of it, made want then
fn rangeArg(mut c Checker, e NodeId, i i64, t TypeId, want TypeId):
	if isSameType(tys, t, want): return true
	if c.tKind(t) != tInt or isDefined(tys, t) or not isSameType(tys, rangeBase(tys, t), want):
		return false
	c.setArg(e, i, c.coerceTo(c.argAt(e, i), want))
	true

# e without the dereference the checker put around it (a lent name's value)
fn unreferenced(c Checker, e NodeId):
	nodes[e].kids[0] if nodes[e].kind == nDeref and nodes[e].kids.len == 1 else e

# e without the widening the checker put around it (flagAutoWiden), which keeps its value
fn unwidened(c Checker, e NodeId):
	if nodes[e].kind != nCall or not nodes[e].hasFlag(flagAutoWiden): return e
	callee = nodes[e].kids[0]
	nodes[callee].kids[0] if nodes[callee].kind == nField and nodes[callee].kids.len == 1 else e

# whether the integer e's values, by its type's range or its literal, lie in lo..=hi (an index
# inside a fixed array, a shift's count inside the width: no check is made)
fn spanInside(mut c Checker, e NodeId, lo i64, hi i64):
	t = c.derefType(typeOf(nodes, e))
	if c.tKind(t) != tInt or tys[t].bits == 64 and not tys[t].isSigned: return false
	s = c.operandSpan(e, t, t)
	s.isSpanBounded() and s.lo >= lo and s.hi <= hi

# whether integer arithmetic e (+ - * /) stays inside its type, its operands' ranges proving it:
# its overflow check is left out
fn arithmeticInside(mut c Checker, e NodeId):
	t = c.derefType(typeOf(nodes, e))
	if nodes[e].kind != nBinary or c.tKind(t) != tInt or isDefined(tys, t): return false
	base = rangeBase(tys, t)
	l = nodes[e].kids[0]
	r = nodes[e].kids[1]
	lt = c.derefType(typeOf(nodes, l))
	rt = c.derefType(typeOf(nodes, r))
	if c.tKind(lt) != tInt or c.tKind(rt) != tInt: return false
	least, most = intBounds(tys, base)
	# an operand's end that is no bound is base's own: a value like any other here (i + 1 of an
	# i below its type's top stays inside, however low i goes)
	a = c.operandSpan(l, lt, base).boundedBy(least, most)
	b = c.operandSpan(r, rt, base).boundedBy(least, most)
	s = opSpan(nodes[e].ival, a, b) ?? return false
	s.isSpanBounded() and s.lo >= least and s.hi <= most

# s with its ends that are no bound at least and most
fn boundedBy(s Span, least i64, most i64):
	Span(least if s.below else s.lo, most if s.above else s.hi)

# `i32 in 0..` and `i64 in 0..` noted for zap fmt as `n32` and `n64`, the naturals' one spelling
fn noteNaturalSpelling(mut c Checker, te NodeId, t TypeId):
	if not noting: return
	b = nodes[te].types[0]
	src = c.file if c.curFile == "" else c.curFile
	text = sourceLineOf(src, nodes[b].line)
	at = nodes[b].col - 1
	long = "i32 in 0.." if t == tyN32 else "i64 in 0.."
	end = at + long.len
	if at < 0 or end > text.len or text[at..end] != long: return
	if end < text.len and (text[end] == '=' or text[end].isWordByte()): return
	c.canonNote(noteReplace, nodes[b].line, at + 1, long.len, "n32" if t == tyN32 else "n64")

# the type a checked conversion of a value of integer type from into integer type to gives: the
# range from's values keep inside to (`i32(n)` after `if n < 0 or n > 9: return`, `i64(b)` of a
# u8 lies in 0..=255), else to
fn convertedRange(mut c Checker, from TypeId, to TypeId) TypeId:
	if c.tKind(from) != tInt or c.tKind(to) != tInt or isDefined(tys, from) or
		isDefined(tys, to) or tys[from].param != "" or tys[to].param != "" or
		tys[from].bits == 64 and not tys[from].isSigned:
		return to
	lo, hi = intBounds(tys, from)
	spanType(tys, c.rangeTypes, to, Span(lo, hi))
