# The texture instructions translated (yuzu's texture_*.cpp): TEX and TEXS sample, TLD and TLDS
# fetch a texel, TXQ asks a size. Texture `handle` (the word of the texture constant buffer the
# instruction names) is `p.<kind's array>[base + slot]` (emit.zap). Zap has 2D textures, 2D arrays and 2D shadow
# maps, sampled with an implicit or explicit level: what else an instruction asks is noted
# missing (NOTES.md, "Shaders").

components4 = ["x", "y", "z", "w"]

# the texture of `handle` as this kind, none when the program read it as another kind
fn textureOf(mut e Emitter, handle i64, kind TextureKind) str?:
	if e.textures.find(.handle == handle) is t:
		if t.kind != kind: return none
	else:
		e.textures.push(TextureUse(handle, kind, slot = e.textures.filter(.kind == kind).len))
	slot = (try e.textures.find(.handle == handle)).slot
	"p.{kind.arrayName()}[{e.stage.textureBase() + slot}]"

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
# level 0: a shadow map has one), 7 a 2D array, 8 a 2D array at level 0
pub fn emitTexs(mut e Emitter, i Instr):
	encoding = i.field(53, 4)
	kind = TextureKind.Shadow if encoding == 4 or encoding == 6
		else .Layered if encoding >= 7
		else .Plain
	t = e.textureOf(i.field(36, 13), kind) ?? ""
	if not i.flag(59) or t == "" or encoding == 0 or encoding == 5 or encoding > 8:
		e.lack(i, "TEXS encoding {encoding} (1D, 3D, cube, a compare at a level), f16 results, or a texture read two ways", [i.rd, i.field(28, 8)])
		return
	a = i.ra
	b = i.field(20, 8)   # B is bits 20-27 whatever form the decoder gave
	uv = "Vec2({e.f(a)}, {e.f(b)})" if encoding <= 2
		else "Vec2({e.f(a + 1)}, {e.f(b)})" if encoding >= 7
		else "Vec2({e.f(a)}, {e.f(a + 1)})"
	layer = "f32({e.x(a)} & 0xFFFF)"
	sample = match encoding:
		1: "{t}.sample({uv})"
		2: "{t}.sampleLevel({uv}, 0.0)"
		3: "{t}.sampleLevel({uv}, {e.f(b)})"
		7: "{t}.sample({uv}, {layer})"
		8: "{t}.sampleLevel({uv}, {layer}, 0.0)"
		_: e.shadowRead(t, uv, e.f(b))
	e.storeSwizzled(i, sample)

# a shadow map's compare as a Vec4: the fraction lit in r g b, alpha 1
fn shadowRead(mut e Emitter, t str, uv str, depth str):
	e.line("lit = {t}.compare({uv}, {depth})")
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
	t = e.textureOf(i.field(36, 13), .Plain) ?? ""
	if not i.flag(59) or t == "" or (encoding != 2 and encoding != 5):
		e.lack(
			i,
			"TLDS encoding {encoding} (1D, 3D, an array, an offset, multisampled), or f16 results",
			[i.rd, i.field(28, 8)]
		)
		return
	sample = e.fetch(t, e.x(a), e.x(b), "0") if encoding == 2
		else e.fetch(t, e.x(a), e.x(a + 1), e.x(b))
	e.storeSwizzled(i, sample)

# TEX: the coordinates from A, the lod, offset and depth reference from B on; the mask's
# components into rd, rd + 1...
pub fn emitTex(mut e Emitter, i Instr):
	kind = i.field(28, 3)
	blod = i.field(55, 3)
	shadow = i.flag(50)
	if i.form == .Bindless or i.flag(54) or i.flag(58) or (kind != 2 and kind != 3) or blod > 3 or
		blod == 2 or i.field(51, 3) != pt:
		e.lack(
			i,
			"TEX: bindless, an offset, a lod clamp or bias, a sparse result, or 1D, 3D, cube",
			i.texDestinations()
		)
		return
	c = i.ra
	m = i.field(20, 8)
	layered = kind == 3
	uv = "Vec2({e.f(c + 1)}, {e.f(c + 2)})" if layered else "Vec2({e.f(c)}, {e.f(c + 1)})"
	lod = e.f(m) if blod == 3 else "0.0"
	depth = e.f(m + 1 if blod == 3 else m)
	handle = i.field(36, 13)
	sample = ""
	if shadow and not layered:
		t = e.textureOf(handle, .Shadow) ?? ""
		if t != "": sample = e.shadowRead(t, uv, depth)
	elif layered and not shadow:
		t = e.textureOf(handle, .Layered) ?? ""
		layer = "f32({e.x(c)} & 0xFFFF)"
		if t != "":
			sample = "{t}.sample({uv}, {layer})" if blod == 0
				else "{t}.sampleLevel({uv}, {layer}, {lod})"
	elif not shadow:
		t = e.textureOf(handle, .Plain) ?? ""
		if t != "": sample = "{t}.sample({uv})" if blod == 0 else "{t}.sampleLevel({uv}, {lod})"
	if sample == "":
		e.lack(i, "TEX of a shadow array, or a texture read two ways", i.texDestinations())
		return
	e.storeMasked(i, sample)

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
	t = e.textureOf(i.field(36, 13), .Plain) ?? ""
	if t == "":
		e.lack(i, "a texture read two ways", i.texDestinations())
		return
	lod = e.x(i.field(20, 8)) if i.flag(55) else "0"
	e.storeMasked(i, e.fetch(t, e.x(i.ra), e.x(i.ra + 1), lod))

# TXQ's dimensions of a 2D texture at the level in A: width, height (depth 1, the level count
# Zap does not give)
pub fn emitTxq(mut e Emitter, i Instr):
	t = e.textureOf(i.field(36, 13), .Plain) ?? ""
	if i.form == .Bindless or i.field(22, 3) != 1 or t == "" or i.field(31, 4) & 8 != 0:
		e.lack(i, "TXQ: bindless, not the dimensions, or the level count", i.texDestinations())
		return
	e.line("size = {t}.size(i32({e.x(i.ra)}))")
	values = ["u32(size.x)", "u32(size.y)", "1"]
	n = 0
	for c in 0..3:
		if (i.field(31, 4) >> c) & 1 != 0:
			e.set(i.rd + n, values[c])
			n += 1
