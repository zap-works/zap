# The texture instructions translated (yuzu's texture_*.cpp): TEX and TEXS sample, TXD samples by
# gradients, TLD and TLDS fetch a texel, TLD4 and TLD4S gather, TMML asks the level of detail, TXQ
# a size. Texture `handle` (the word of the texture constant buffer the instruction names, or for a
# bindless one the word its handle register was loaded from) is `p.<kind's array>[base + slot]`
# (emit.zap). Zap has 2D textures, 2D arrays and 2D shadow maps of either: what else an
# instruction asks is noted missing (README.md, "Maxwell shaders", and TODO.md).

components4 = ["x", "y", "z", "w"]

# The texture of `handle` (in `bank`, -1 the texture buffer) read as this kind: a texture read two
# ways (a depth texture sampled and compared) takes a slot of each kind, the renderer binding the
# one image to both.
fn textureOf(mut e Emitter, handle i64, kind TextureKind, bank i64 = -1):
	slot = e.textures.filter(.kind == kind).len
	if e.textures.find(.handle == handle and .kind == kind and .bank == bank) is known:
		slot = known.slot
	else:
		e.textures.push(TextureUse(handle, kind, slot, bank))
	"p.{kind.arrayName()}[{e.stage.textureBase() + slot}]"

# A texture instruction's handle and the register after `meta`: field 36's for a bound one, for
# a bindless one the constant buffer word its register (meta) was loaded from when the code
# shows it.
# A bindless one whose handle is not known is noted missing.
fn handleOf(mut e Emitter, i Instr, meta i64) (i64, i64, i64)?:
	if i.form != .Bindless: return (i.field(36, 13), -1, meta)
	if e.known.get(meta) is k and k.bank >= 0: return (k.word, k.bank, meta + 1)
	e.lack(i, "{i.op}.B: a handle not known when translating", i.texDestinations())
	none

# The constant offset register r holds (`bits` signed bits at `at` and `stride` past it) as the
# last argument of a read, none when the code does not show it or Zap's range (-8 to 7) cannot.
fn offsetOf(e Emitter, r i64, bits i64, stride i64, at i64 = 0) str?:
	k = try e.known.get(r)
	if k.bank >= 0: return none
	x = signedField(k.value, at, bits)
	y = signedField(k.value, at + stride, bits)
	if x < -8 or x > 7 or y < -8 or y > 7: return none
	", IVec2({x}, {y})"

fn lackOffset(mut e Emitter, i Instr):
	e.lack(i, "{i.op}: an offset not known when translating, or past -8..7", i.texDestinations())

fn signedField(v i64, at i64, bits i64):
	f = (v >> at) & ((1 << bits) - 1)
	f - (1 << bits) if f >> (bits - 1) != 0 else f

# the coordinates of a 2D (or with `layered` a 2D array) read from register c on: uv, then the
# layer (the low 16 bits of c)
fn coordinates(mut e Emitter, c i64, layered bool):
	if not layered: return "Vec2({e.f(c)}, {e.f(c + 1)})"
	"Vec2({e.f(c + 1)}, {e.f(c + 2)}), f32({e.x(c)} & 0xFFFF)"

fn kindOf(layered bool, shadow bool) TextureKind:
	if shadow: return .LayeredShadow if layered else .Shadow
	.Layered if layered else .Plain

# the 4 components of `sample` written to the registers TEXS/TLDS name: the components the
# swizzle picks (2 of them when B is RZ, else 3 or 4) into A, A + 1, B, B + 1
fn storeSwizzled(mut e Emitter, i Instr, sample str):
	pairs = [1, 2, 4, 8, 3, 9, 10, 12]
	quads = [7, 11, 13, 14, 15]
	b = i.field(28, 8)
	k = i.field(50, 3)
	if b != rz and k >= quads.len:
		e.lack(i, "swizzle {k}", [i.rd])
		return
	mask = pairs[k] if b == rz else quads[k]
	places = [i.rd, i.rd + 1, b, b + 1]
	e.line("texel = {sample}")
	n = 0
	for c in 0..4:
		if (mask >> c) & 1 != 0:
			e.setF(places[n], "texel.{components4[c]}")
			n += 1

# TEXS's encodings Zap reads: 1 2D, 2 2D at level 0, 3 2D at a level, 4 and 6 2D compared (6 at
# level 0; a comparison reads a shadow map's one level), 7 a 2D array, 8 at level 0, 9 a shadow
# map array compared at level 0
pub fn emitTexs(mut e Emitter, i Instr):
	encoding = i.field(53, 4)
	if not i.flag(59) or encoding == 0 or encoding == 5 or encoding > 9:
		e.lack(
			i,
			"TEXS encoding {encoding} (1D, 3D, cube, a compare at a level), or f16 results",
			[i.rd, i.field(28, 8)]
		)
		return
	shadow = encoding in [4, 6, 9]
	layered = encoding >= 7
	t = e.textureOf(i.field(36, 13), kindOf(layered, shadow))
	a = i.ra
	b = i.field(20, 8)   # B is bits 20-27 whatever form the decoder gave
	uv = "Vec2({e.f(a)}, {e.f(b)})" if encoding <= 2
		else "Vec2({e.f(a + 1)}, {e.f(b)})" if layered
		else "Vec2({e.f(a)}, {e.f(a + 1)})"
	layer = "f32({e.x(a)} & 0xFFFF)"
	sample = match encoding:
		1: "{t}.sample({uv})"
		2: "{t}.sampleLevel({uv}, 0.0)"
		3: "{t}.sampleLevel({uv}, {e.f(b)})"
		7: "{t}.sample({uv}, {layer})"
		8: "{t}.sampleLevel({uv}, {layer}, 0.0)"
		9: e.shadowRead(t, "{uv}, {layer}, {e.f(b + 1)}")
		_: e.shadowRead(t, "{uv}, {e.f(b)}")
	e.storeSwizzled(i, sample)

# a shadow map's compare of `args` as a Vec4: the fraction lit in r g b, alpha 1
fn shadowRead(mut e Emitter, t str, args str):
	e.line("lit = {t}.compare({args})")
	"Vec4(lit, lit, lit, 1.0)"

# a texel fetch: no fetch in Zap, a sample of the level at the texel's centre in its place
fn fetch(mut e Emitter, t str, x str, y str, lod str):
	level = "0" if lod == "0" else "i32({lod})"
	e.line("size = {t}.size({level})")
	"{t}.sampleLevel(Vec2((f32(i32({x})) + 0.5) / f32(size.x), (f32(i32({y})) + 0.5) / f32(size.y)), {"0.0" if lod == "0" else "f32({level})"})"

pub fn emitTlds(mut e Emitter, i Instr):
	a = i.ra
	b = i.field(20, 8)   # B is bits 20-27 whatever form the decoder gave
	encoding = i.field(53, 4)
	if not i.flag(59) or (encoding != 2 and encoding != 5):
		e.lack(
			i,
			"TLDS encoding {encoding} (1D, 3D, an array, an offset, multisampled), or f16 results",
			[i.rd, i.field(28, 8)]
		)
		return
	t = e.textureOf(i.field(36, 13), .Plain)
	sample = e.fetch(t, e.x(a), e.x(b), "0") if encoding == 2
		else e.fetch(t, e.x(a), e.x(a + 1), e.x(b))
	e.storeSwizzled(i, sample)

# TEX (TEX.B: its handle in B): the coordinates from A, then from B on the handle (bindless), the
# lod or bias, the offset and the depth reference; the mask's components into rd, rd + 1...
pub fn emitTex(mut e Emitter, i Instr):
	bindless = i.form == .Bindless
	kind = i.field(28, 3)
	blod = i.field(37 if bindless else 55, 3)
	shadow = i.flag(50)
	if kind != 2 and kind != 3 or i.flag(40 if bindless else 58) or blod == 4 or blod == 5 or
		i.field(51, 3) != pt or shadow and blod > 1:
		e.lack(
			i,
			"TEX: 1D, 3D, cube, a lod clamp, a sparse result, or a compare at a level",
			i.texDestinations()
		)
		return
	handle, bank, meta = e.handleOf(i, i.field(20, 8)) ?? return
	lod = ""
	if blod >= 2:
		lod = ", {e.f(meta)}"
		meta += 1
	offset = ""
	if i.flag(36 if bindless else 54):
		offset = e.offsetOf(meta, 4, 4) ?? return e.lackOffset(i)
		meta += 1
	t = e.textureOf(handle, kindOf(kind == 3, shadow), bank)
	args = e.coordinates(i.ra, kind == 3)
	if shadow:
		e.storeMasked(i, e.shadowRead(t, "{args}, {e.f(meta)}{offset}"))
		return
	# none, LZ, LB, LL, LBA, LLA (the A forms read as theirs)
	method = ["sample", "sampleLevel", "sampleBias", "sampleLevel"][blod % 4]
	if blod == 1: lod = ", 0.0"
	e.storeMasked(i, "{t}.{method}({args}{lod}{offset})")

fn texDestinations(i Instr):
	out = []
	for k in 0..field(i, 31, 4).bitCount():
		out.push(i.rd + k)
	out

fn storeMasked(mut e Emitter, i Instr, sample str):
	e.line("texel = {sample}")
	n = 0
	for c in 0..4:
		if (i.field(31, 4) >> c) & 1 != 0:
			e.setF(i.rd + n, "texel.{components4[c]}")
			n += 1

# TXD (TXD.B: its handle in A, the coordinates after it): a sample of a 2D texture or array by
# the gradients from B (x's across x, across y, y's across x, across y), the layer (low 16 bits)
# and the offset (bits 16-23) in the register after the coordinates
pub fn emitTxd(mut e Emitter, i Instr):
	kind = i.field(28, 3)
	if kind != 2 and kind != 3 or i.flag(50) or i.field(51, 3) != pt:
		e.lack(i, "TXD: 1D, 3D, cube, a lod clamp or a sparse result", i.texDestinations())
		return
	handle, bank, c = e.handleOf(i, i.ra) ?? return
	last = c + 2
	offset = ""
	if i.flag(35):
		offset = e.offsetOf(last, 4, 4, at = 16) ?? return e.lackOffset(i)
	t = e.textureOf(handle, kindOf(kind == 3, false), bank)
	layer = ", f32({e.x(last)} & 0xFFFF)" if kind == 3 else ""
	d = i.field(20, 8)
	e.storeMasked(i, "{t}.sampleGrad(Vec2({e.f(c)}, {e.f(c + 1)}){layer}, Vec2({e.f(d)}, {e.f(d + 2)}), Vec2({e.f(d + 1)}, {e.f(d + 3)}){offset})")

# TLD of a 2D texture: integer coordinates in A, A + 1, the level in B when LOD
pub fn emitTld(mut e Emitter, i Instr):
	if i.form == .Bindless or i.field(28, 3) != 2 or i.flag(35) or i.flag(50) or i.flag(54) or
		i.field(51, 3) != pt:
		e.lack(
			i,
			"TLD: bindless, not 2D, an offset, multisampled, clamped or sparse",
			i.texDestinations()
		)
		return
	t = e.textureOf(i.field(36, 13), .Plain)
	lod = e.x(i.field(20, 8)) if i.flag(55) else "0"
	e.storeMasked(i, e.fetch(t, e.x(i.ra), e.x(i.ra + 1), lod))

# TLD4 (TLD4.B: its handle in B): a gather of component 56 (38) of a 2D texture or array, or its
# depth comparisons, from B on the handle, the offset (six bits at 0 and 8) and the reference
pub fn emitTld4(mut e Emitter, i Instr):
	bindless = i.form == .Bindless
	kind = i.field(28, 3)
	offsetKind = i.field(36 if bindless else 54, 2)
	if kind != 2 and kind != 3 or offsetKind > 1 or i.field(51, 3) != pt:
		e.lack(i, "TLD4: 1D, 3D, cube, per-texel offsets or a sparse result", i.texDestinations())
		return
	handle, bank, meta = e.handleOf(i, i.field(20, 8)) ?? return
	offset = ""
	if offsetKind == 1:
		offset = e.offsetOf(meta, 6, 8) ?? return e.lackOffset(i)
		meta += 1
	shadow = i.flag(50)
	t = e.textureOf(handle, kindOf(kind == 3, shadow), bank)
	args = e.coordinates(i.ra, kind == 3)
	read = "gatherCompare({args}, {e.f(meta)}" if shadow
		else "gather({args}, {i.field(38 if bindless else 56, 2)}"
	e.storeMasked(i, "{t}.{read}{offset})")

# TLD4S: a gather of component 52 of a 2D texture into A, A + 1, B, B + 1; the coordinates A and
# B, or with an offset (or a compare) A and A + 1, the offset in B and the reference after it
pub fn emitTld4s(mut e Emitter, i Instr):
	a = i.ra
	b = i.field(20, 8)
	offsetGiven = i.flag(51)
	shadow = i.flag(50)
	offset = ""
	if offsetGiven:
		offset = e.offsetOf(b, 6, 8) ?? ""
	if i.flag(55) or offsetGiven and offset == "":
		e.lack(
			i,
			"TLD4S: f16 results, or an offset not known when translating",
			[i.rd, i.field(28, 8)]
		)
		return
	t = e.textureOf(i.field(36, 13), kindOf(false, shadow))
	uv = "Vec2({e.f(a)}, {e.f(a + 1)})" if offsetGiven or shadow else "Vec2({e.f(a)}, {e.f(b)})"
	depth = e.f(b + 1 if offsetGiven else b)
	read = "gatherCompare({uv}, {depth}" if shadow else "gather({uv}, {i.field(52, 2)}"
	e.line("texel = {t}.{read}{offset})")
	d = i.field(28, 8)
	places = [i.rd, i.rd + 1, d, d + 1]
	for c in 0..4:
		if places[c - c % 2] != rz: e.setF(places[c], "texel.{components4[c]}")

# TMML (TMML.B: its handle in B): the level of detail of a 2D texture or array at the
# coordinates from A, the level read and the one asked as fixed point of 8 fraction bits
pub fn emitTmml(mut e Emitter, i Instr):
	kind = i.field(28, 3)
	if kind != 2 and kind != 3 or i.field(31, 4) & 0xC != 0:
		e.lack(i, "TMML: 1D, 3D, cube, or its third and fourth results", i.texDestinations())
		return
	handle, bank, _ = e.handleOf(i, i.field(20, 8)) ?? return
	t = e.textureOf(handle, kindOf(kind == 3, false), bank)
	c = i.ra + (1 if kind == 3 else 0)
	e.line("level = {t}.lod(Vec2({e.f(c)}, {e.f(c + 1)}))")
	n = 0
	for k in 0..2:
		if (i.field(31, 4) >> k) & 1 != 0:
			e.set(i.rd + n, "u32(level.{components4[k]}.max(0.0) * 256.0)")
			n += 1

# TXQ's dimensions of a 2D texture at the level in A: width, height (depth 1, the level count
# Zap does not give)
pub fn emitTxq(mut e Emitter, i Instr):
	if i.form == .Bindless or i.field(22, 3) != 1 or i.field(31, 4) & 8 != 0:
		e.lack(i, "TXQ: bindless, not the dimensions, or the level count", i.texDestinations())
		return
	t = e.textureOf(i.field(36, 13), .Plain)
	e.line("size = {t}.size(i32({e.x(i.ra)}))")
	values = ["u32(size.x)", "u32(size.y)", "1"]
	n = 0
	for c in 0..3:
		if (i.field(31, 4) >> c) & 1 != 0:
			e.set(i.rd + n, values[c])
			n += 1
