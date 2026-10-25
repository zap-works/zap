# Memory layout of values (spec §2): values are stored inline, so every type has a size
# and an alignment, structs have field offsets and enums their variants' after the tag.
#
#   ints and floats: their natural width; bool 1 byte; unit 0 bytes
#   str, T[]:    { ptr i64, length i64, cap i64 }  (24 bytes; cap 0 = borrowed or static bytes)
#   {K: V}:       one pointer to an owned table (8 bytes)
#   T?:          T's bytes alone when T has a niche (nicheOf: a value none of its own holds in
#                some field's bytes, which says none), else { tag u8 (0 none, 1 some), T at
#                its alignment }
#   T ? E:       { tag u8 (1 ok, 0 an error), T or E at the larger alignment }
#   struct:      fields widest alignment first (those of one alignment in order), each at its
#                alignment, size rounded to the struct's alignment, its largest field's (a Vec3
#                of f32 is 12 bytes at 4, so a list of them, or a struct of three, has no gaps);
#                an extern type's and a GPU file's fields in order, as C and the shaders have them
#   enum:        { tag (the variant's number: enumTagSize), each variant's fields after it,
#                narrowest first }; an enum whose variants carry nothing is its tag alone
#   fn(A) R:         { code i64, env i64 }   (16 bytes; env is an owned heap block or 0)
#   T[N]:            N elements at the element stride, inline (no header)

alias nodes = c.nodes
alias kidIds = c.kidIds
alias tys = c.types

# Where a value says which it is: an enum's variant number, an optional's or a result's tag (0
# none, an error), or the bytes of a field an optional's none is told by (its niche, absent the
# value no value of the field's type holds there).
pub type TagSpot:
	off i64
	size i64
	absent i64 = 0

# the bits a spot of size bytes holds for v (a load of them is unsigned)
pub fn spotBits(v i64, size i64) i64:
	if size >= 8: return v
	v & ((1 << (size * 8)) - 1)

pub fn typeAlign(mut c Checker, t TypeId) i64:
	k = c.tKind(t)
	if k == tStruct:
		sd = declOf(tys, t)
		a = 8 if nodes[sd].hasFlag(flagDrop) else 1   # its live word
		for ft in c.fieldTypesOf(sd):
			a = a.max(c.typeAlign(ft))
		return a
	if k == tInt: return tys[t].bits / 8
	if k == tFloat: return tys[t].bits / 8
	if k == tBool: return 1
	if k == tUnit: return 1
	if k == tArray: return c.typeAlign(innerOf(tys, t))
	if k == tOption:
		if tys[t].inner == none: return 1
		return c.typeAlign(innerOf(tys, t))
	if k == tResult: return c.resultPayload(t)
	if k == tEnum: return c.enumAlign(declOf(tys, t))
	8

# an enum's alignment: its tag's, or its variants' widest field's
fn enumAlign(mut c Checker, ed NodeId):
	a = c.enumTagSize(ed)
	for v in nodes[ed].kids(kidIds).copy():
		for ft in c.fieldTypesOf(v):
			a = a.max(c.typeAlign(ft))
	a

# A read reference to a str or a list is a window { ptr, length } over the bytes or the elements
# (16 bytes); every other reference is the address of the value (8 bytes).
pub fn refIsWindow(c Checker, t TypeId) bool:
	if c.tKind(t) != tRef or tys[t].bits != 0: return false
	ik = c.tKind(tys[t].inner)
	ik == tStr or ik == tList

# True for values that travel in rax: numbers, bool, unit, maps (a pointer), references.
pub fn isScalar(c Checker, t TypeId) bool:
	k = c.tKind(t)
	if k == tRef: return not c.refIsWindow(t)
	k in [tInt, tFloat, tBool, tUnit, tMap, tBox, tError]

# A value no value of type t holds in some of its bytes, which an optional of t keeps for none
# (rustc's niche): a bool's 2; a range's value outside it (`n32?` is 4 bytes, -1 for none; `(u8 in
# 0..=9)?` one byte, 10); an enum's variant count in its tag; a box's or a reference's address 0,
# a window's length -1; an optional's tag 2 (`i64??` is 16 bytes); a str's or a list's cap with
# 0xA0 for its last byte (an owned block's is below 128, a short str's 128 + its length, a
# frame's buffer's 255); a struct's first field's that has one and owns nothing, else its first
# owning field's whose none is not 0 (a str's or a list's cap: a part moved out leaves zeroes,
# still some, and a read of the tag reads those bytes, not the moved value; an extern type has
# none); an array's first element's; a tagless optional's, its value's next one (`bool??` one
# byte, 3 for none; `i64???` 16). None for any other type. kept: how many of the spot's values
# optionals around t already keep, the one returned the next.
pub fn nicheOf(mut c Checker, t TypeId, kept i64 = 0) TagSpot?:
	k = c.tKind(t)
	if k == tBool: return byteNiche(0, 2 + kept)
	if k == tInt and tys[t].ranged:
		lo, hi = intBounds(tys, t)
		least, most = intBounds(tys, rangeBase(tys, t))
		size = tys[t].bits / 8
		# (sums and differences kept from overflowing at the base's ends)
		if lo > least + kept: return TagSpot(off = 0, size, absent = lo - 1 - kept)
		above = kept - (lo - least)
		if hi < most - above: return TagSpot(off = 0, size, absent = hi + 1 + above)
		return none
	if k == tEnum:
		ed = declOf(tys, t)
		size = c.enumTagSize(ed)
		absent = nodes[ed].kids(kidIds).len + kept
		if size < 8 and absent >= 1 << (size * 8): return none
		return TagSpot(off = 0, size, absent)
	if k == tBox or k == tRef and not c.refIsWindow(t):
		return TagSpot(off = 0, size = 8) if kept == 0 else none
	if k == tRef: return TagSpot(off = 8, size = 8, absent = -1 - kept)
	if k == tOption and tys[t].inner != none:
		if c.isTaglessOption(t): return c.nicheOf(innerOf(tys, t), kept + 1)
		return byteNiche(0, 2 + kept)
	if k == tStr or k == tList: return byteNiche(23, 0xA0 + kept)
	if k == tArray and tys[t].bits > 0: return c.nicheOf(innerOf(tys, t), kept)
	if k != tStruct or c.isExternType(declOf(tys, t)): return none
	sd = declOf(tys, t)
	for owning in [false, true]:
		for i in 0..nodes[sd].kids(kidIds).len:
			ft = c.structFieldTypeAt(sd, i)
			if c.isPlainType(ft) == owning: continue
			if c.nicheOf(ft, kept) is n and (not owning or n.absent != 0):
				return TagSpot(
					off = c.structFieldOffsetAt(sd, i) + n.off,
					size = n.size,
					absent = n.absent
				)
	none

# a niche in the byte at off, absent its none, while the byte holds it (below 255: a str's frame
# buffer's cap)
fn byteNiche(off i64, absent i64) TagSpot?:
	TagSpot(off, size = 1, absent) if absent < 255 else none

# Where optional t says whether it holds a value: its value's niche (no tag: isTaglessOption),
# else its tag byte (0 none, 1 some).
pub fn optionTag(mut c Checker, t TypeId) TagSpot:
	if tys[t].inner == none: return TagSpot(off = 0, size = 1)
	c.nicheOf(innerOf(tys, t)) ?? TagSpot(off = 0, size = 1)

# whether optional t is its value's bytes alone, none told by its niche (optionTag)
pub fn isTaglessOption(mut c Checker, t TypeId) bool:
	if c.tKind(t) != tOption or tys[t].inner == none: return false
	c.nicheOf(innerOf(tys, t)) != none

# a tagless optional in one word: a box's, a reference's (the address, 0 for none) or an enum's
# whose variants carry nothing (the variant's number, the variant count for none)
pub fn isNicheOption(c Checker, maybeT TypeId?) bool:
	t = maybeT ?? return false
	if c.tKind(t) != tOption or tys[t].inner == none: return false
	inner = innerOf(tys, t)
	ik = c.tKind(inner)
	ik == tBox or ik == tRef and not c.refIsWindow(inner) or
		ik == tEnum and not c.enumCarries(inner)

# the word a one-word optional (isNicheOption) holds for none; 0, the tag of none, for any other
pub fn optionAbsent(mut c Checker, t TypeId) i64:
	if not c.isNicheOption(t): return 0
	c.optionTag(t).absent

# the value an optional of a range or of a bool holds for none (its niche's), a tag and a value
# in registers; none for any other optional
pub fn scalarNicheAbsent(mut c Checker, t TypeId) i64?:
	if c.tKind(t) != tOption or tys[t].inner == none: return none
	inner = innerOf(tys, t)
	if c.tKind(inner) != tBool and not (c.tKind(inner) == tInt and tys[inner].ranged): return none
	n = try c.nicheOf(inner)
	n.absent

# where an optional's value starts: at its first byte (no tag) or after the tag, at its alignment
pub fn optionPayload(mut c Checker, t TypeId) i64:
	if c.isTaglessOption(t): return 0
	c.typeAlign(innerOf(tys, t))

# where a result's side starts: after its tag byte, at the larger alignment of the two
pub fn resultPayload(mut c Checker, t TypeId) i64:
	c.typeAlign(innerOf(tys, t)).max(c.typeAlign(errOf(tys, t)))

# A result's tag: a byte, 1 ok and 0 an error.
pub fn resultTag() TagSpot:
	TagSpot(off = 0, size = 1)

# The bytes of an enum's tag, the variant's number: one up to 255 variants (the count, its
# optional's none, still fits), two up to 65,535, four past that or in a GPU file (the shader's
# u32).
pub fn enumTagSize(c Checker, ed NodeId) i64:
	n = nodes[ed].kids(kidIds).len
	if isGpuFile(nodes[ed].file()) or n >= 65_536: return 4
	if n >= 256: return 2
	1

# An enum's tag (its variant's number).
pub fn enumTag(c Checker, ed NodeId) TagSpot:
	TagSpot(off = 0, size = c.enumTagSize(ed))

pub fn typeSize(mut c Checker, t TypeId) i64:
	k = c.tKind(t)
	if k == tInt or k == tFloat: return tys[t].bits / 8
	if k == tBool: return 1
	if k == tUnit: return 0
	if k == tStr or k == tList: return 24
	if k in [tSimd, tBytes, tVec]:
		return 32   # a u8x16 takes the same slot as an f64x4
	if k == tMap or k == tBox: return 8
	if k == tFn: return 16
	if k == tRef:
		if c.refIsWindow(t): return 16
		return 8
	if k == tOption and tys[t].inner == none: return 1
	if k == tOption:
		inner = innerOf(tys, t)
		return (c.optionPayload(t) + c.typeSize(inner)).alignUp(c.typeAlign(inner))
	if k == tResult:
		a = c.resultPayload(t)
		return (a + c.typeSize(innerOf(tys, t)).max(c.typeSize(errOf(tys, t)))).alignUp(a)
	if k == tStruct: return c.structSize(declOf(tys, t))
	if k == tEnum: return c.enumSize(declOf(tys, t))
	if k == tArray: return tys[t].bits * c.elemStride(innerOf(tys, t))
	8

# The element stride of a T[]: the element size rounded to its alignment.
pub fn elemStride(mut c Checker, elem TypeId) i64:
	c.typeSize(elem).alignUp(c.typeAlign(elem))

# Resolved field types of a struct declaration (or of a variant), in order.
fn fieldTypesOf(mut c Checker, holder NodeId):
	out = []
	for f in nodes[holder].kids(kidIds).copy():
		out.push(c.resolveType(nodes[f].types()[0]))
	out

# Offsets of a sequence of field types, by index; the last element is the total size rounded to
# the largest alignment. The fields go from start widest alignment first (no gap between fields
# of falling alignment), narrowest first after a variant's tag (small fields fill the bytes beside
# it), or in order (an extern or GPU type, laid out as C has it). In an extern type (cPointers) a
# reference, or an optional one, is a C pointer: 8 bytes, 0 for none.
fn layoutFields(mut c Checker, fts TypeId[], start i64, order i64, cPointers bool):
	aligns = []
	sizes = []
	for ft in fts:
		pointer = cPointers and c.isCPointer(ft)
		aligns.push(8 if pointer else c.typeAlign(ft))
		sizes.push(8 if pointer else c.typeSize(ft))
	offs = fill(fts.len + 1, 0)
	pos = start
	maxAlign = 1
	for i in fieldOrder(aligns, order):
		a = aligns[i]
		maxAlign = maxAlign.max(a)
		pos = pos.alignUp(a)
		offs[i] = pos
		pos += sizes[i]
	offs[fts.len] = pos.alignUp(maxAlign)
	offs

fieldsInOrder = 0
fieldsWidestFirst = 1
fieldsNarrowestFirst = 2

# the indexes of fields of these alignments in the order layoutFields places them (those of one
# alignment in declaration order)
fn fieldOrder(aligns i64[], order i64):
	out = []
	for k in 0..7:
		want = 64 >> k if order == fieldsWidestFirst else 1 << k
		for i, fa in aligns:
			if order == fieldsInOrder and k == 0 or order != fieldsInOrder and fa == want:
				out.push(i)
	out

# how a struct's fields are placed: in order in an extern type (C's) and a GPU file's (the shader's)
fn fieldsOrderOf(c Checker, sd NodeId):
	if c.isExternType(sd) or isGpuFile(nodes[sd].file()): return fieldsInOrder
	fieldsWidestFirst

# whether a declaration is an extern type (a structure laid out as C has it)
pub fn isExternType(c Checker, sd NodeId) bool:
	nodes[sd].kind == nStructDecl and nodes[sd].hasFlag(flagExtern)

# whether a field type of an extern type is a C pointer: a reference, or an optional one
pub fn isCPointer(mut c Checker, t TypeId) bool:
	k = c.tKind(t)
	k == tRef or k == tOption and tys[t].inner != none and c.tKind(tys[t].inner) == tRef

# the offsets of the fields of a struct and its size; laid out once when no type parameter is in
# force (the fields' types are then the same at every use)
pub fn structFieldOffsets(mut c Checker, sd NodeId) i64[]:
	if c.layouts.get(sd) is offs: return offs.copy()
	fts = c.fieldTypesOf(sd)
	if nodes[sd].hasFlag(flagDrop):
		fts.push(tyInt(64, true))   # its live word (dropLiveOffset)
	offs = c.layoutFields(fts, 0, c.fieldsOrderOf(sd), c.isExternType(sd))
	if c.subst.names.isEmpty:
		c.layouts[sd] = offs.copy()
	offs

# A value of a struct with a drop function carries a word after its fields, 1 once it is made, 0 in
# the empty value a move leaves (zeroed bytes): only a live value is dropped, so one whose fields
# are all zero (Handle(id = 0)) is still released. Its offset.
pub fn dropLiveOffset(mut c Checker, sd NodeId) i64:
	c.structFieldOffsets(sd)[nodes[sd].kids(kidIds).len]

pub fn structSize(mut c Checker, sd NodeId) i64:
	if c.layouts.get(sd) is offs: return offs.last ?? 0
	c.structFieldOffsets(sd).last ?? 0

# the offset of field i of struct sd (the index found first, by reading: resolving the layout
# may add types and nodes)
pub fn structFieldOffsetAt(mut c Checker, sd NodeId, i i64) i64:
	if c.layouts.get(sd) is offs: return offs[i]
	c.structFieldOffsets(sd)[i]

pub fn structFieldTypeAt(mut c Checker, sd NodeId, i i64) TypeId:
	c.resolveType(nodes[nodes[sd].kids(kidIds)[i]].types()[0])

pub fn structFieldOffset(mut c Checker, sd NodeId, name str) i64:
	c.structFieldOffsetAt(sd, c.fieldIndexOf(sd, name))

pub fn structFieldType(mut c Checker, sd NodeId, name str) TypeId:
	i = c.fieldIndexOf(sd, name)
	c.resolveType(nodes[nodes[sd].kids(kidIds)[i]].types()[0])

# The offsets of the fields of variant v of enum ed from the start of the enum's value (after its
# tag), the last the variant's end; laid out once as a struct is.
pub fn variantFieldOffsets(mut c Checker, ed NodeId, v NodeId) i64[]:
	if c.layouts.get(v) is offs: return offs.copy()
	offs = c.layoutFields(c.fieldTypesOf(v), c.enumTagSize(ed), fieldsNarrowestFirst, false)
	if c.subst.names.isEmpty:
		c.layouts[v] = offs.copy()
	offs

pub fn enumSize(mut c Checker, ed NodeId) i64:
	end = c.enumTagSize(ed)
	for v in nodes[ed].kids(kidIds).copy():
		end = end.max(c.variantFieldOffsets(ed, v).last ?? 0)
	end.alignUp(c.enumAlign(ed))

# Size of a value when it occupies argument or temporary slots: whole 8-byte words.
pub fn slotSize(mut c Checker, t TypeId) i64:
	c.typeSize(t).alignUp(8)
