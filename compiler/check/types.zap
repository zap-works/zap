# Semantic types resolved by the checker. They live in one arena (Ty[]) and are referred
# to by index; -1 means "no type". The primitive types have fixed ids (see newTypes).

pub tUnit = 0
pub tBool = 1
pub tInt = 2
pub tFloat = 3
pub tStr = 4
pub tStruct = 5
pub tEnum = 6
pub tOption = 7
pub tResult = 8
pub tList = 11
pub tMap = 12
pub tFn = 13
pub tError = 14
pub tRef = 15
pub tSimd = 16   # f64x4: four f64 lanes in one 256-bit register
pub tBytes = 17   # u8x16: sixteen bytes in one 128-bit register
pub tBox = 18   # Box<T>: an owned value on the heap, one pointer word (shared: counted)
pub tArray = 20   # T[N]: N values of T stored inline (bits: N)
pub tVec = 19   # f32x8, i32x8, i64x4, u8x32: lanes of one element type in 256 bits (vecs.zap)
pub tSeq = 21   # Seq<T>: what a generator gives, only walked (inner: T)
pub tNum = 22   # a number given for a number parameter (`<N n64>`): bits its value (-1 at the
# definition, whose stand-in names it), inner the parameter's integer type, decl its literal node

# a type's index in the checker's types (`TypeId?` where there may be none)
pub type TypeId = n32

pub type Ty:
	kind i64
	bits i64   # int and float widths
	isSigned bool   # ints
	name str   # struct/enum: global name of the declaration
	display str   # struct/enum: the name as written in the source (instances: Stack<i64>)
	decl NodeId?   # struct/enum: declaration node
	inner TypeId?   # option inner, result ok, list element, map key
	err TypeId?   # result error
	val TypeId?   # map value
	params TypeId[]   # fn parameters
	ret TypeId?   # fn result
	counted bool   # a box of a `shared type`: copies share the value, a count says when it ends
	param str   # the stand-in of a type parameter in the definition check (its name), else ""
	ranged bool = false   # an integer whose values lie in lo..=hi (`i64 in 0..=100`, n64), stored as its base
	lo i64 = 0
	hi i64 = 0
	defined NodeId? = none   # a defined type (`type NodeId = n32`): its declaration; the rest is its base's
	under TypeId? = none   # a defined type: its base
	definedName str = ""   # a defined type: its declaration's global name
	closed bool = false   # made once from parts made once (tyOnce): isSameType to another such type only as the same id

# fixed ids
pub tyUnit TypeId = 0
pub tyBool TypeId = 1
pub tyStr TypeId = 2
pub tyError TypeId = 3
pub tySimd TypeId = 16
pub tyBytes TypeId = 17
pub tyN32 TypeId = 4   # the naturals: i32 in 0.. and i64 in 0..
pub tyN64 TypeId = 5
# 6..9: i8 i16 i64 i64; 10..13: u8 u16 u32 u64; 14: f32; 15: f64

# the built-in types written by name, and their ids
pub type PrimType:
	name str
	id TypeId

pub primTypes = [
	PrimType("i8", 6),
	PrimType("i16", 7),
	PrimType("i32", 8),
	PrimType("i64", 9),
	PrimType("u8", 10),
	PrimType("u16", 11),
	PrimType("u32", 12),
	PrimType("u64", 13),
	PrimType("f32", 14),
	PrimType("f64", 15), PrimType("n32", tyN32), PrimType("n64", tyN64), PrimType(
		"bool",
		tyBool
	), PrimType("str", tyStr), PrimType("()", tyUnit)]

fn blankTy(kind i64):
	Ty(
		kind,
		bits = 0,
		isSigned = false,
		name = "",
		display = "",
		decl = none,
		inner = none,
		err = none,
		val = none,
		params = [],
		ret = none,
		counted = false,
		param = ""
	)

pub fn newTypes() Ty[]:
	typeIndex = {}
	ts = []
	ts.push(blankTy(tUnit))
	ts.push(blankTy(tBool))
	ts.push(blankTy(tStr))
	ts.push(blankTy(tError))
	ts.push(rangedTy(32, 0, intMax(32, true)))   # n32
	ts.push(rangedTy(64, 0, intMax(64, true)))   # n64
	widths = [8, 16, 32, 64]
	for w in widths:
		t = blankTy(tInt)
		t.bits = w
		t.isSigned = true
		ts.push(t)
	for w in widths:
		t = blankTy(tInt)
		t.bits = w
		ts.push(t)
	f32 = blankTy(tFloat)
	f32.bits = 32
	ts.push(f32)
	f64 = blankTy(tFloat)
	f64.bits = 64
	ts.push(f64)
	ts.push(blankTy(tSimd))   # index 16: f64x4
	ts.push(blankTy(tBytes))   # index 17: u8x16
	for i, mut t in ts:
		t.closed = i != i64(tyError)
	ts

# a signed integer of `bits` bits whose values lie in lo..=hi
fn rangedTy(bits i64, lo i64, hi i64):
	t = blankTy(tInt)
	t.bits = bits
	t.isSigned = true
	t.ranged = true
	t.lo = lo
	t.hi = hi
	t

# the largest value of an integer type (of a u64, the largest i64: a range's bounds are i64s)
pub fn intMax(bits i64, isSigned bool) i64:
	if bits == 64: return 9_223_372_036_854_775_807
	(1 << (bits - 1)) - 1 if isSigned else (1 << bits) - 1

# the smallest value of an integer type
pub fn intMin(bits i64, isSigned bool) i64:
	if not isSigned: return 0
	-intMax(bits, true) - 1

# the integer type base whose values lie in lo..=hi: n32 and n64 for the naturals (one spelling
# each), else a range type of its own
pub fn tyRange(mut ts Ty[], base TypeId, lo i64, hi i64) TypeId:
	bits = ts[base].bits
	if ts[base].isSigned and lo == 0 and hi == intMax(bits, true) and (bits == 32 or bits == 64):
		return tyN32 if bits == 32 else tyN64
	t = rangedTy(bits, lo, hi)
	t.isSigned = ts[base].isSigned
	ts.push(t)
	TypeId(ts.len - 1)

# the leaf standing for the tag of an optional of a range or a bool (the backend's irLeaves): a bool with
# no memory of its own, read as the value's being other than the absent word; inner the optional
pub fn tyNicheTag(mut ts Ty[], opt TypeId) TypeId:
	t = blankTy(tBool)
	t.inner = opt
	ts.push(t)
	TypeId(ts.len - 1)

# a type of its own over base (`type Meters = f64`, declaration d named global, shown as
# display): base's layout and operations, never a value of base
pub fn tyDefined(mut ts Ty[], base TypeId, d NodeId, global str, display str) TypeId:
	t = ts[base].copy()
	t.defined = d
	t.under = base
	t.definedName = global.copy()
	t.display = display.copy()
	tyOnce(ts, t)

# whether t is a defined type
pub fn isDefined(ts Ty[], maybeT TypeId?) bool:
	t = maybeT ?? return false
	ts[t].defined != none

# The parts of a type where its kind has them (an optional's or a list's inner, a result's error,
# a map's value, a function's result, a defined type's base): the error type where it has none,
# and of no type.
pub fn innerOf(ts Ty[], t TypeId?) TypeId:
	ts[t ?? return tyError].inner ?? tyError

pub fn errOf(ts Ty[], t TypeId?) TypeId:
	ts[t ?? return tyError].err ?? tyError

pub fn valOf(ts Ty[], t TypeId?) TypeId:
	ts[t ?? return tyError].val ?? tyError

pub fn retOf(ts Ty[], t TypeId?) TypeId:
	ts[t ?? return tyError].ret ?? tyError

pub fn underOf(ts Ty[], t TypeId?) TypeId:
	ts[t ?? return tyError].under ?? tyError

# a struct's or an enum's declaration (a type of another kind has none: the compiler stops)
pub fn declOf(ts Ty[], t TypeId?) NodeId:
	ts[t ?? fail("no type has no declaration")].decl ??
		fail("{typeStr(ts, t)} has no declaration")

# the type under t's defined types (Color for `type Hue = Paint` of `type Paint = Color`), or t
pub fn underlying(ts Ty[], t TypeId) TypeId:
	at = t
	while isDefined(ts, at):
		at = underOf(ts, at)
	at

# the integer type a range type is stored as (any other type itself)
pub fn rangeBase(ts Ty[], t TypeId) TypeId:
	tyInt(ts[t].bits, ts[t].isSigned) if ts[t].ranged else t

# whether t is n32 or n64, a natural: an integer that is never negative, of no upper bound but
# its base's
pub fn isNatural(ts Ty[], maybeT TypeId?) bool:
	t = maybeT ?? return false
	ts[t].ranged and ts[t].lo == 0 and ts[t].hi == intMax(ts[t].bits, ts[t].isSigned)

# a type's kind, -1 for none
pub fn kindOf(ts Ty[], t TypeId?) i64:
	ts[t ?? return -1].kind

# the lowest and the highest value of integer type t
pub fn intBounds(ts Ty[], t TypeId) (i64, i64):
	if ts[t].ranged: return (ts[t].lo, ts[t].hi)
	(intMin(ts[t].bits, ts[t].isSigned), intMax(ts[t].bits, ts[t].isSigned))

pub fn tyInt(bits i64, isSigned bool) TypeId:
	base TypeId = 6
	if not isSigned:
		base = 10
	if bits == 8: return base
	if bits == 16: return base + 1
	if bits == 32: return base + 2
	base + 3

pub fn tyFloat(bits i64) TypeId:
	if bits == 32: return 14
	15

# The types made from their parts: the same parts give the same id (tyOnce). A list or an
# optional of no inner type yet (`[]`, `none`) is made anew each time, since its first use tells
# its inner type in place.
pub fn tyList(mut ts Ty[], elem TypeId?) TypeId:
	t = blankTy(tList)
	t.inner = elem
	tyFresh(ts, t) if elem == none else tyOnce(ts, t)

pub fn tySeq(mut ts Ty[], elem TypeId) TypeId:
	t = blankTy(tSeq)
	t.inner = elem
	tyOnce(ts, t)

pub fn tyBox(mut ts Ty[], inner TypeId) TypeId:
	t = blankTy(tBox)
	t.inner = inner
	tyOnce(ts, t)

# a vector of `lanes` elements of type elem (vecs.zap); at a generic's definition lanes -1 and
# count the number parameter's stand-in
pub fn tyVec(mut ts Ty[], elem TypeId, lanes i64, count TypeId? = none) TypeId:
	t = blankTy(tVec)
	t.inner = elem
	t.bits = lanes
	t.val = count
	tyOnce(ts, t)

# [n]elem: n values of elem stored inline, one after another
pub fn tyArray(mut ts Ty[], elem TypeId, n i64) TypeId:
	t = blankTy(tArray)
	t.inner = elem
	t.bits = n
	tyOnce(ts, t)

# elem[N] for the number size (a tNum): its value's array, or at a generic's definition one whose
# length is the parameter (bits -1, val the stand-in)
pub fn tyArrayOf(mut ts Ty[], elem TypeId, size TypeId) TypeId:
	if ts[size].param == "": return tyArray(ts, elem, ts[size].bits)
	t = blankTy(tArray)
	t.inner = elem
	t.bits = -1
	t.val = size
	tyOnce(ts, t)

# the number value given for a number parameter of integer type of (-1 when not known yet)
pub fn tyNum(mut ts Ty[], value i64, of TypeId?) TypeId:
	t = blankTy(tNum)
	t.bits = value
	t.inner = of
	ts.push(t)
	TypeId(ts.len - 1)

# the value of a `shared type`: a pointer to the struct on the heap, its count in the word
# before it
pub fn tyShared(mut ts Ty[], inner TypeId) TypeId:
	t = blankTy(tBox)
	t.inner = inner
	t.counted = true
	tyOnce(ts, t)

pub fn tyMap(mut ts Ty[], key TypeId, val TypeId) TypeId:
	t = blankTy(tMap)
	t.inner = key
	t.val = val
	tyOnce(ts, t)

pub fn tyOption(mut ts Ty[], inner TypeId?) TypeId:
	t = blankTy(tOption)
	t.inner = inner
	tyFresh(ts, t) if inner == none else tyOnce(ts, t)

pub fn tyResult(mut ts Ty[], ok TypeId, err TypeId) TypeId:
	t = blankTy(tResult)
	t.inner = ok
	t.err = err
	tyOnce(ts, t)

pub fn tyFn(mut ts Ty[], params TypeId[], ret TypeId?) TypeId:
	t = blankTy(tFn)
	# the caller keeps its list (it is called with lists it reads again), so the type holds its own
	t.params = params.copy()
	t.ret = ret
	if ret == none:
		t.ret = tyUnit
	tyOnce(ts, t)

# ref T (read) or mut ref T (bits = 1): a pointer to a value owned elsewhere
pub fn tyRef(mut ts Ty[], inner TypeId, isMut bool) TypeId:
	t = blankTy(tRef)
	t.inner = inner
	if isMut:
		t.bits = 1
	tyOnce(ts, t)

# A struct or enum type for a declaration node (nStructDecl or nEnumDecl).
pub fn tyOfDecl(mut ts Ty[], nodes Node[], d NodeId) TypeId:
	t = blankTy(tStruct)
	if nodes[d].kind == nEnumDecl:
		t.kind = tEnum
	t.decl = d
	# the type keeps its own names: the declaration node keeps its text
	t.name = nodes[d].text.copy()
	if nodes[d].text2 == "":
		t.display = nodes[d].text.copy()
	else:
		t.display = nodes[d].text2.copy()
	tyOnce(ts, t)

# The made types by a hash of their parts: open addressing, a taken slot whose type has other
# parts sends the search on (partsHash's next). newTypes empties it for a new arena; an entry
# is believed only when the arena's type at its id has the parts asked for.
mut typeIndex {i64: TypeId} = {}

hashMask = 1_099_511_627_775   # 2^40 - 1: a hash times a mixing factor stays in an i64

fn mixIn(h i64, x i64):
	(h * 1_000_003 + (x & 4_294_967_295)) & hashMask

fn idOrNone(t TypeId?):
	if t is t: i64(t) + 1 else: 0

fn nodeOrNone(d NodeId?):
	if d is d: i64(d) + 1 else: 0

# a hash of what tells a type apart (its names aside)
fn partsHash(t Ty):
	h = mixIn(t.kind, t.bits)
	h = mixIn(h, idOrNone(t.inner))
	h = mixIn(h, idOrNone(t.err))
	h = mixIn(h, idOrNone(t.val))
	h = mixIn(h, idOrNone(t.ret))
	h = mixIn(h, nodeOrNone(t.decl))
	h = mixIn(h, nodeOrNone(t.defined))
	for p in t.params:
		h = mixIn(h, i64(p))
	h

# whether a and b are the same type to isSameType and every other reader but for their names
fn sameIdentity(a Ty, b Ty):
	a.kind == b.kind and a.bits == b.bits and a.isSigned == b.isSigned and a.inner == b.inner and
		a.err == b.err and
		a.val == b.val and
		a.ret == b.ret and
		a.counted == b.counted and
		a.decl == b.decl and
		a.param == b.param and
		a.ranged == b.ranged and
		a.lo == b.lo and
		a.hi == b.hi and
		a.defined == b.defined and
		a.under == b.under and
		a.params.len == b.params.len and
		(0..a.params.len).all(a.params[it] == b.params[it])

fn sameNames(a Ty, b Ty):
	a.name == b.name and a.display == b.display and a.definedName == b.definedName

# whether t's parts make it a type isSameType tells apart by its id: no part still open, of an error,
# a type parameter's or a number's, every part such a type
fn partsClosed(ts Ty[], t Ty):
	if t.param != "" or t.kind == tError or t.kind == tNum or (t.ranged and t.defined == none):
		return false
	if (t.kind in [tOption, tList, tMap]) and t.inner == none: return false
	for part in [t.inner, t.err, t.val, t.ret, t.under]:
		if part is p and not ts[p].closed: return false
	t.params.all(ts[it].closed)

# The type of t's parts, made once: the type made before of the same parts, else t added. A type
# of the same parts but other names (a declaration shown another way) is added apart and not
# closed, so isSameType still compares it by its parts.
pub fn tyOnce(mut ts Ty[], move t Ty) TypeId:
	h = t.partsHash()
	while typeIndex.get(h) is at:
		if i64(at) < ts.len and ts[at].sameIdentity(t):
			if ts[at].sameNames(t):
				typesMet = typesMet or typesPast >= 0 and i64(at) >= typesPast
				return at
			return tyFresh(ts, t)
		h = mixIn(h, 1)
	t.closed = partsClosed(ts, t)
	ts.push(t)
	id = TypeId(ts.len - 1)
	typeIndex[h] = id
	id

# while a function being kept is lowered (keptir.zap): the kept stages' types, and whether it met
# a type past them, which another program may make elsewhere
mut typesPast = -1
mut typesMet = false

# t added as a type of its own, never found by its parts
pub fn tyFresh(mut ts Ty[], move t Ty) TypeId:
	t.closed = false
	ts.push(t)
	TypeId(ts.len - 1)

pub fn typeIsMapKey(ts Ty[], maybeT TypeId?) bool:
	t = maybeT ?? return false
	k = ts[t].kind
	if k == tRef and ts[t].bits == 0:
		return ts[innerOf(ts, t)].kind == tStr   # a ref str: the map borrows its keys
	k in [tInt, tStr, tError]

pub fn typeIsNumeric(ts Ty[], maybeT TypeId?) bool:
	t = maybeT ?? return false
	k = ts[t].kind
	k == tInt or k == tFloat

pub fn isSameType(ts Ty[], maybeA TypeId?, maybeB TypeId?) bool:
	b = maybeB ?? return false
	a = maybeA ?? return false
	if a == b: return true
	if ts[a].closed and ts[b].closed: return false
	ka = ts[a].kind
	kb = ts[b].kind
	if ka == tError or kb == tError: return true
	if ka != kb or ts[a].param != ts[b].param: return false   # a type parameter is itself only
	if ts[a].defined != ts[b].defined and not openLiteral(ts, a) and not openLiteral(ts, b):
		return false   # a defined type is itself only
	if ka == tInt:
		return ts[a].bits == ts[b].bits and ts[a].isSigned == ts[b].isSigned and
			ts[a].ranged == ts[b].ranged and ts[a].lo == ts[b].lo and ts[a].hi == ts[b].hi
	if ka == tFloat: return ts[a].bits == ts[b].bits and ts[a].isSigned == ts[b].isSigned
	if ka == tStruct or ka == tEnum: return ts[a].decl == ts[b].decl
	if ka == tOption or ka == tList:
		# none (inner -1) and [] are compatible with any optional or list
		if ts[a].inner == none or ts[b].inner == none: return true
		return isSameType(ts, ts[a].inner, ts[b].inner)
	if ka == tBox:
		return ts[a].counted == ts[b].counted and isSameType(ts, ts[a].inner, ts[b].inner)
	if ka == tSeq: return isSameType(ts, ts[a].inner, ts[b].inner)
	if ka == tVec:
		return ts[a].bits == ts[b].bits and
			(ts[a].bits >= 0 or isSameType(ts, ts[a].val, ts[b].val)) and
			isSameType(ts, ts[a].inner, ts[b].inner)
	if ka == tArray:
		return ts[a].bits == ts[b].bits and
			(ts[a].bits >= 0 or isSameType(ts, ts[a].val, ts[b].val)) and
			isSameType(ts, ts[a].inner, ts[b].inner)
	if ka == tNum: return ts[a].bits == ts[b].bits
	if ka == tMap:
		if ts[a].inner == none or ts[b].inner == none: return true
		return isSameType(ts, ts[a].inner, ts[b].inner) and isSameType(ts, ts[a].val, ts[b].val)
	if ka == tResult:
		return isSameType(ts, ts[a].inner, ts[b].inner) and isSameType(ts, ts[a].err, ts[b].err)
	if ka == tRef: return ts[a].bits == ts[b].bits and isSameType(ts, ts[a].inner, ts[b].inner)
	if ka == tFn:
		pa = ts[a].params
		pb = ts[b].params
		if pa.len != pb.len: return false
		if (0..pa.len).any(not isSameType(ts, pa[it], pb[it])): return false
		return isSameType(ts, ts[a].ret, ts[b].ret)
	true

# none or [] or {} before a place gives their type: they fit any optional, list or map
fn openLiteral(ts Ty[], t TypeId):
	ts[t].inner == none and (ts[t].kind in [tOption, tList, tMap])

# True when storing `src` into `dst` needs the T -> T? wrap in the backend.
pub fn typeNeedsOptWrap(ts Ty[], maybeSrc TypeId?, maybeDst TypeId?) bool:
	src = maybeSrc ?? return false
	dst = maybeDst ?? return false
	ts[dst].kind == tOption and ts[src].kind != tError and
		ts[dst].inner != none and isSameType(ts, src, ts[dst].inner)

# True when storing `src` into `dst` needs the T -> T ? E (or E -> T ? E) wrap.
pub fn typeNeedsResWrap(ts Ty[], maybeSrc TypeId?, maybeDst TypeId?) bool:
	src = maybeSrc ?? return false
	dst = maybeDst ?? return false
	ts[dst].kind == tResult and ts[src].kind != tResult and ts[src].kind != tError and
		(isSameType(ts, src, ts[dst].inner) or isSameType(ts, src, ts[dst].err))

pub fn isAssignable(ts Ty[], src TypeId, dst TypeId) bool:
	isSameType(ts, src, dst) or intWidensTy(ts, src, dst) or typeNeedsOptWrap(ts, src, dst) or
		typeNeedsResWrap(ts, src, dst) or isRefAssignable(ts, src, dst) or
		isRangeIntoWrapped(ts, src, dst)

# whether src is a range where an optional or a result of a type holding it is expected (an n64
# where an i64? is): widened, then wrapped
pub fn isRangeIntoWrapped(ts Ty[], maybeSrc TypeId?, maybeDst TypeId?) bool:
	dst = maybeDst ?? return false
	src = maybeSrc ?? return false
	ts[src].kind == tInt and ts[src].ranged and
		(ts[dst].kind == tOption or ts[dst].kind == tResult) and ts[dst].inner != none and
		intWidensTy(ts, src, ts[dst].inner)

# An integer widens to a wider one without loss: the same sign, or signed when it is
# unsigned (u8 to i64). The checker inserts the conversion; narrowing stays explicit. A range
# type goes where its base goes, and into a range that holds its own.
pub fn intWidensTy(ts Ty[], maybeSrc TypeId?, maybeDst TypeId?) bool:
	dst = maybeDst ?? return false
	src = maybeSrc ?? return false
	if ts[src].kind != tInt or ts[dst].kind != tInt: return false
	if ts[src].defined != ts[dst].defined: return false
	if ts[dst].ranged:
		return ts[src].ranged and not isSameType(ts, src, dst) and ts[dst].lo <= ts[src].lo and
			ts[src].hi <= ts[dst].hi and baseWidens(ts, src, dst, true)
	baseWidens(ts, src, dst, ts[src].ranged)

# whether the base of src widens to the base of dst (or is it, when same is allowed)
fn baseWidens(ts Ty[], src TypeId, dst TypeId, same bool):
	if ts[dst].bits <= ts[src].bits:
		return same and ts[dst].bits == ts[src].bits and ts[dst].isSigned == ts[src].isSigned
	ts[dst].isSigned == ts[src].isSigned or ts[dst].isSigned

# A reference where its value is expected (the checker inserts the dereference), and a mutable
# reference where a read reference is expected.
pub fn isRefAssignable(ts Ty[], maybeSrc TypeId?, maybeDst TypeId?) bool:
	dst = maybeDst ?? return false
	src = maybeSrc ?? return false
	if ts[src].kind == tOption and ts[dst].kind == tOption and ts[src].inner != none and
		ts[dst].inner != none and
		ts[innerOf(ts, src)].kind == tRef and ts[innerOf(ts, dst)].kind != tRef:
		# an optional reference where an optional value is expected (the value is copied out)
		return isSameType(ts, ts[innerOf(ts, src)].inner, ts[dst].inner)
	if ts[src].kind == tBox and ts[dst].kind != tBox:
		return isAssignable(ts, innerOf(ts, src), dst)   # a box where its value is expected
	if ts[src].kind != tRef: return false
	if ts[dst].kind == tRef:
		return ts[src].bits == 1 and ts[dst].bits == 0 and
			isSameType(ts, ts[src].inner, ts[dst].inner)
	isAssignable(ts, innerOf(ts, src), dst)

# a range type as written: n32, n64, an alias's name (as shown), else `i64 in 0..=100` (`0..`
# for an open end)
fn rangeWritten(ts Ty[], t TypeId, mode i64):
	if t == tyN32: return "n32"
	if t == tyN64: return "n64"
	if mode == 0 and ts[t].display != "": return ts[t].display.copy()
	base = typeWritten(ts, tyInt(ts[t].bits, ts[t].isSigned), mode)
	end = "" if ts[t].hi == intMax(ts[t].bits, ts[t].isSigned) else "={ts[t].hi}"
	"{base} in {ts[t].lo}..{end}"

# lists and fixed arrays as written, one bracket for their layers outer first: i64[], f32[4],
# Vec3[, 4] (a list of arrays of four), f64[,]; an element that would read otherwise in parentheses
fn layersWritten(ts Ty[], t TypeId):
	sizes = []
	inner TypeId? = t
	while inner is layer and (ts[layer].kind == tList or ts[layer].kind == tArray):
		sizes.push("" if ts[layer].kind == tList else str(ts[layer].bits))
		inner = ts[layer].inner
	elem = tyOrBlank(ts, inner, 0)
	k = tUnit if inner == none else kindOf(ts, inner)
	if k in [tRef, tResult, tFn] or " in " in elem:
		elem = "({elem})"
	out = "{elem}["
	for i, size in sizes:
		if i > 0:
			out = "{out}," if size == "" and sizes[i - 1] == "" else "{out}, "
		out = "{out}{size}"
	"{out}]"

fn tyOrBlank(ts Ty[], t TypeId?, mode i64):
	if t == none: return "_"
	typeWritten(ts, t, mode)

# the name of a runtime tuple type as it is written: Tuple2<i64, str> is (i64, str)
pub fn tupleShown(name str) str:
	if name.len > 8 and name.startsWith("Tuple") and name[5] >= '2' and name[5] <= '8' and
		name[6] == '<' and name.endsWith(">"):
		return "({name[7..name.len - 1]})"
	name.copy()

# a type as it is written in the source
pub fn typeStr(ts Ty[], t TypeId?) str:
	typeWritten(ts, t, 0)

# A key that tells types apart where their written names may not: a struct or enum carries its
# global name, so two modules' `Body` (and lists of them) give two keys.
pub fn typeKey(ts Ty[], t TypeId?) str:
	typeWritten(ts, t, 1)

# a type as an instance's global name takes it: a struct or enum of a module by its global name
# (two modules' `Key` make two instances of a generic function or struct, not one)
pub fn typeMangled(ts Ty[], t TypeId) str:
	typeWritten(ts, t, 2)

fn typeWritten(ts Ty[], maybeT TypeId?, mode i64) str:
	t = maybeT ?? return "<null>"
	if ts[t].param != "":
		# the definition checks of two generics each have their own T
		return ts[t].param.copy() if mode == 0 else "{ts[t].param}${t}"
	if ts[t].defined != none: return ts[t].display.copy() if mode == 0 else ts[t].definedName.copy()
	k = ts[t].kind
	if k == tUnit: return "()"
	if k == tBool: return "bool"
	if k == tStr: return "str"
	if k == tError: return "<error>"
	if k == tInt and ts[t].ranged: return rangeWritten(ts, t, mode)
	if k == tInt:
		if ts[t].isSigned: return "i{ts[t].bits}"
		return "u{ts[t].bits}"
	if k == tFloat: return "bf{ts[t].bits}" if ts[t].isSigned else "f{ts[t].bits}"
	if k == tStruct or k == tEnum:
		if mode == 1: return "{ts[t].display}#{ts[t].name}"
		if mode == 2 and ts[t].name != ts[t].display: return ts[t].name.copy()
		return tupleShown(ts[t].display)
	if k == tRef:
		if ts[t].bits == 1: return "mut ref {typeWritten(ts, ts[t].inner, mode)}"
		return "ref {typeWritten(ts, ts[t].inner, mode)}"
	if k == tOption: return "{tyOrBlank(ts, ts[t].inner, mode)}?"
	if k == tResult:
		value = typeWritten(ts, ts[t].inner, mode)
		shown = "({value})" if ts[t].inner != none and ts[innerOf(ts, t)].kind == tOption else value
		return "{shown} ? {typeWritten(ts, ts[t].err, mode)}"
	if k == tSimd: return "Simd<4, f64>"
	if k == tBytes: return "Simd<16, u8>"
	if (k == tList or k == tArray) and mode == 0: return layersWritten(ts, t)
	if k == tList: return "{typeWritten(ts, ts[t].inner, mode)}[]"
	if k == tSeq: return "Seq<{typeWritten(ts, ts[t].inner, mode)}>"
	if k == tVec:
		lanes = str(ts[t].bits) if ts[t].bits >= 0 else typeWritten(ts, ts[t].val, mode)
		return "Simd<{lanes}, {typeWritten(ts, ts[t].inner, mode)}>"
	if k == tArray:
		size = str(ts[t].bits) if ts[t].bits >= 0 else typeWritten(ts, ts[t].val, mode)
		return "[{size}]{typeWritten(ts, ts[t].inner, mode)}"
	if k == tNum: return str(ts[t].bits)
	if k == tBox and ts[t].counted: return "shared {typeWritten(ts, ts[t].inner, mode)}"
	if k == tBox: return "Box<{typeWritten(ts, ts[t].inner, mode)}>"
	if k == tMap and mode == 0:
		return "\{{tyOrBlank(ts, ts[t].inner, mode)}: {tyOrBlank(ts, ts[t].val, mode)}}"
	if k == tMap: return "\{{tyOrBlank(ts, ts[t].inner, mode)}: {tyOrBlank(ts, ts[t].val, mode)}}"
	s = "fn({ts[t].params.map(typeWritten(ts, it, mode)).join(", ")})"
	if ts[t].ret != none and ts[retOf(ts, t)].kind != tUnit:
		s = "{s} {typeWritten(ts, ts[t].ret, mode)}"
	s
