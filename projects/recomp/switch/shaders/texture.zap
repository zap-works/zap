# The texture instructions translated (yuzu's texture_*.cpp): TEX and TEXS sample, TXD samples by
# gradients, TLD and TLDS fetch a texel, TLD4 and TLD4S gather, TMML asks the level of detail, TXQ
# a size. Texture `handle` (the word of the texture constant buffer the instruction names, or for a
# bindless one the word its handle register was loaded from) is `p.<kind's array>[base + slot]`
# (emit.zap): 2D textures, 2D arrays, shadow maps of either, 3D textures, cubes and cube arrays,
# and textures of integers (the handles the TIC says hold them, fetched as numbers); what else an
# instruction asks is noted missing (README.md, "Maxwell shaders", and board/11-switch/ cards switch-13 to switch-15).

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
	if kind == .Image: return "p.{imageField(e.stage.textureBase() + slot)}"
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

# The constant offset register r holds (`n` fields of `bits` signed bits at `at`, each `stride`
# past the one before) as the last argument of a read, none when the code does not show it or
# Zap's range (-8 to 7) cannot.
fn offsetOf(e Emitter, r i64, bits i64, stride i64, at i64 = 0, n i64 = 2) str?:
	k = try e.known.get(r)
	if k.bank >= 0: return none
	parts = (0..n).map(signedField(k.value, at + it * stride, bits))
	if parts.any(it < -8 or it > 7): return none
	", IVec{n}({parts.map("{it}").join(", ")})"

fn lackOffset(mut e Emitter, i Instr):
	e.lack(i, "{i.op}: an offset not known when translating, or past -8..7", i.texDestinations())

fn signedField(v i64, at i64, bits i64):
	f = (v >> at) & ((1 << bits) - 1)
	f - (1 << bits) if f >> (bits - 1) != 0 else f

# The texture types of TEX, TLD, TLD4, TMML and TXD's field 28: 1D, 1D array, 2D, 2D array, 3D,
# 3D array, cube, cube array.
tex2D = 2
tex2DArray = 3
tex3D = 4
texCube = 6
texCubeArray = 7

# The kind a texture of the type is read as (compared when `shadow`; a texture of integers by
# its handle), none for one Zap has not: 1D, 3D arrays, a compared 3D texture or cube, layered
# or 3D integers.
fn kindOf(e Emitter, handle i64, dim i64, shadow bool) TextureKind?:
	if e.integers.get(handle) is signed:
		if dim != tex2D or shadow: return none
		return .SignedIntegers if signed else .Integers
	if shadow:
		if dim == tex2D: return .Shadow
		return .LayeredShadow if dim == tex2DArray else none
	match dim:
		2: .Plain
		3: .Layered
		4: .Volume
		6: .Cube
		7: .LayeredCube
		_: none

fn isInteger(k TextureKind):
	k == .Integers or k == .SignedIntegers

# the kind a filtered read (a gather, gradients, a level of detail) reads the texture as, none
# (noted missing) for a texture of integers or a type Zap has not
fn filteredKind(mut e Emitter, i Instr, handle i64, dim i64, shadow bool) TextureKind?:
	k = e.kindOf(handle, dim, shadow)
	if k is kind and not kind.isInteger(): return kind
	e.lack(i, "{i.op} of a texture of integers, or of type {dim}", i.texDestinations())
	none

# the coordinates of a read of the type from register c on (yuzu's MakeCoords): uv, an array's
# layer (the low 16 bits of c) after them, a 3D texture's or a cube's three
fn coordinates(mut e Emitter, c i64, dim i64):
	match dim:
		3: "Vec2({e.f(c + 1)}, {e.f(c + 2)}), f32({e.x(c)} & 0xFFFF)"
		4, 6: "Vec3({e.f(c)}, {e.f(c + 1)}, {e.f(c + 2)})"
		7: "Vec3({e.f(c + 1)}, {e.f(c + 2)}, {e.f(c + 3)}), f32({e.x(c)} & 0xFFFF)"
		_: "Vec2({e.f(c)}, {e.f(c + 1)})"

# The integer coordinates of a fetch of the type from register c on, the offset register's
# signed 4-bit fields added (TLD.AOFFI: x, y and z from bit 0; -1 none): a texel, then an
# array's layer.
fn texels(mut e Emitter, c i64, dim i64, offset i64 = -1):
	first = c + 1 if dim == tex2DArray else c
	n = 3 if dim == tex3D else 2
	parts = (0..n).map("i32({e.x(first + it)})")
	if offset >= 0:
		parts = (0..n).map("{parts[it]} + maxwell.texelOffset({e.x(offset)}, {it * 4})")
	layer = ", i32({e.x(c)} & 0xFFFF)" if dim == tex2DArray else ""
	"IVec{n}({parts.join(", ")}){layer}"

# a texel of a texture of integers at the 2D coordinates `uv` (as a TEX reads one: the texel uv
# falls in, at the level asked)
fn integerSample(mut e Emitter, t str, uv str, level str):
	e.line("size = {t}.size({level})")
	e.line("at = {uv}")
	"{t}.fetch(IVec2(i32((at.x * f32(size.x)).floor()), i32((at.y * f32(size.y)).floor())), {level})"

# the local a read of the kind is kept in (one a type: Vec4, UVec4, IVec4)
fn texelName(kind TextureKind):
	"signedTexel" if kind == .SignedIntegers else "intTexel" if kind == .Integers else "texel"

# A register's value of component c of a read: a float's bits, a texture of integers' number.
fn component(kind TextureKind, c i64):
	part = "{kind.texelName()}.{components4[c]}"
	if kind == .SignedIntegers: return "u32({part})"
	part if kind == .Integers else "({part}).toBits()"

# the 4 components of `sample` written to the registers TEXS/TLDS name: the components the
# swizzle picks (2 of them when B is RZ, else 3 or 4) into A, A + 1, B, B + 1
fn storeSwizzled(mut e Emitter, i Instr, sample str, kind TextureKind):
	pairs = [1, 2, 4, 8, 3, 9, 10, 12]
	quads = [7, 11, 13, 14, 15]
	b = i.field(28, 8)
	k = i.field(50, 3)
	if b != rz and k >= quads.len:
		e.lack(i, "swizzle {k}", [i.rd])
		return
	mask = pairs[k] if b == rz else quads[k]
	places = [i.rd, i.rd + 1, b, b + 1]
	e.line("{kind.texelName()} = {sample}")
	n = 0
	for c in 0..4:
		if (mask >> c) & 1 != 0:
			e.set(places[n], kind.component(c))
			n += 1

# TEXS's encodings (yuzu's texture_fetch_swizzled.cpp): 1 2D, 2 2D at level 0, 3 2D at a level,
# 4 to 6 2D compared (5 at a level, 6 at level 0), 7 a 2D array, 8 at level 0, 9 a shadow map
# array compared at level 0, 10 and 11 3D (11 at level 0), 12 and 13 a cube (13 at a level);
# a texture of integers' 2D reads fetch the texel uv falls in
pub fn emitTexs(mut e Emitter, i Instr):
	encoding = i.field(53, 4)
	shadow = encoding in [4, 5, 6, 9]
	dim = tex2DArray if encoding in [7, 8, 9] else tex3D if encoding in [10, 11]
		else texCube if encoding in [12, 13]
		else tex2D
	handle = i.field(36, 13)
	kind = e.kindOf(handle, dim, shadow)
	if not i.flag(59) or encoding == 0 or encoding > 13 or kind == none:
		e.lack(
			i,
			"TEXS encoding {encoding} (1D, or integers not 2D), or f16 results",
			[i.rd, i.field(28, 8)]
		)
		return
	k = kind ?? .Plain
	t = e.textureOf(handle, k)
	a = i.ra
	b = i.field(20, 8)   # B is bits 20-27 whatever form the decoder gave
	uv = "Vec2({e.f(a)}, {e.f(b)})" if encoding <= 2
		else "Vec2({e.f(a + 1)}, {e.f(b)})" if dim == tex2DArray
		else "Vec3({e.f(a)}, {e.f(a + 1)}, {e.f(b)})" if dim != tex2D
		else "Vec2({e.f(a)}, {e.f(a + 1)})"
	if k.isInteger():
		level = "i32({e.f(b)})" if encoding == 3 else "0"
		e.storeSwizzled(i, e.integerSample(t, uv, level), k)
		return
	layer = "f32({e.x(a)} & 0xFFFF)"
	sample = match encoding:
		1, 10, 12: "{t}.sample({uv})"
		2, 11: "{t}.sampleLevel({uv}, 0.0)"
		3: "{t}.sampleLevel({uv}, {e.f(b)})"
		13: "{t}.sampleLevel({uv}, {e.f(b + 1)})"
		7: "{t}.sample({uv}, {layer})"
		8: "{t}.sampleLevel({uv}, {layer}, 0.0)"
		9: e.shadowRead(t, "compare", "{uv}, {layer}, {e.f(b + 1)}")
		5: e.shadowRead(t, "compareLevel", "{uv}, {e.f(b + 1)}, {e.f(b)}")
		_: e.shadowRead(t, "compare", "{uv}, {e.f(b)}")
	e.storeSwizzled(i, sample, k)

# a shadow map's comparison `read` of `args` as a Vec4: the fraction lit in r g b, alpha 1
fn shadowRead(mut e Emitter, t str, read str, args str):
	e.line("lit = {t}.{read}({args})")
	"Vec4(lit, lit, lit, 1.0)"

# TLDS's encodings (yuzu's texture_load_swizzled.cpp): 2 2D at level 0 (A, B), 4 with the offset
# in B, 5 at the level in B (A, A + 1), 7 3D at level 0 (A, A + 1, B), 8 a 2D array at level 0
# (B, B + 1, the layer A's low 16 bits), 12 at the level in B, the offset in B + 1
pub fn emitTlds(mut e Emitter, i Instr):
	a = i.ra
	b = i.field(20, 8)   # B is bits 20-27 whatever form the decoder gave
	encoding = i.field(53, 4)
	dim = tex3D if encoding == 7 else tex2DArray if encoding == 8 else tex2D
	handle = i.field(36, 13)
	kind = e.kindOf(handle, dim, false)
	if not i.flag(59) or encoding not in [2, 4, 5, 7, 8, 12] or kind == none:
		e.lack(
			i,
			"TLDS encoding {encoding} (1D, multisampled, integers not 2D), or f16 results",
			[i.rd, i.field(28, 8)]
		)
		return
	k = kind ?? .Plain
	t = e.textureOf(handle, k)
	level = "i32({e.x(b)})" if encoding == 5 or encoding == 12 else "0"
	at = match encoding:
		2: "IVec2(i32({e.x(a)}), i32({e.x(b)}))"
		4: e.texels(a, tex2D, offset = b)
		7: "IVec3(i32({e.x(a)}), i32({e.x(a + 1)}), i32({e.x(b)}))"
		8: "IVec2(i32({e.x(b)}), i32({e.x(b + 1)})), i32({e.x(a)} & 0xFFFF)"
		12: e.texels(a, tex2D, offset = b + 1)
		_: e.texels(a, tex2D)
	e.storeSwizzled(i, "{t}.fetch({at}, {level})", k)

# TEX (TEX.B: its handle in B): the coordinates from A (yuzu's texture_fetch.cpp), then from B on
# the handle (bindless), the lod or bias, the offset and the depth reference; the mask's
# components into rd, rd + 1...
pub fn emitTex(mut e Emitter, i Instr):
	bindless = i.form == .Bindless
	dim = i.field(28, 3)
	blod = i.field(37 if bindless else 55, 3)
	shadow = i.flag(50)
	if i.flag(40 if bindless else 58) or blod == 4 or blod == 5 or i.field(51, 3) != pt:
		e.lack(i, "TEX: a lod clamp or a sparse result", i.texDestinations())
		return
	handle, bank, meta = e.handleOf(i, i.field(20, 8)) ?? return
	kind = e.kindOf(handle, dim, shadow) ??
		return e.lack(
			i,
			"TEX of type {dim} (1D, a 3D array, a compared 3D texture or cube, integers not 2D)",
			i.texDestinations()
		)
	lod = ""
	if blod >= 2:
		lod = ", {e.f(meta)}"
		meta += 1
	offset = ""
	if i.flag(36 if bindless else 54):
		if dim == texCube or dim == texCubeArray:
			return e.lack(i, "TEX: an offset of a cube", i.texDestinations())
		n = 3 if dim == tex3D else 2
		offset = e.offsetOf(meta, 4, 4, n = n) ?? return e.lackOffset(i)
		meta += 1
	t = e.textureOf(handle, kind, bank)
	args = e.coordinates(i.ra, dim)
	if kind.isInteger():
		level = "i32({lod[2..]})" if blod % 4 == 3 else "0"
		e.storeMasked(i, e.integerSample(t, args, level), kind)
		return
	# none, LZ, LB, LL, LBA, LLA (the A forms read as theirs)
	if shadow:
		read = ["compare", "compare", "compareBias", "compareLevel"][blod % 4]
		e.storeMasked(i, e.shadowRead(t, read, "{args}, {e.f(meta)}{lod}{offset}"), kind)
		return
	method = ["sample", "sampleLevel", "sampleBias", "sampleLevel"][blod % 4]
	if blod == 1: lod = ", 0.0"
	e.storeMasked(i, "{t}.{method}({args}{lod}{offset})", kind)

fn texDestinations(i Instr):
	out = []
	for k in 0..field(i, 31, 4).bitCount():
		out.push(i.rd + k)
	out

fn storeMasked(mut e Emitter, i Instr, sample str, kind TextureKind = .Plain):
	e.line("{kind.texelName()} = {sample}")
	n = 0
	for c in 0..4:
		if (i.field(31, 4) >> c) & 1 != 0:
			e.set(i.rd + n, kind.component(c))
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
	t = e.textureOf(handle, e.filteredKind(i, handle, kind, false) ?? return, bank)
	layer = ", f32({e.x(last)} & 0xFFFF)" if kind == 3 else ""
	d = i.field(20, 8)
	e.storeMasked(i, "{t}.sampleGrad(Vec2({e.f(c)}, {e.f(c + 1)}){layer}, Vec2({e.f(d)}, {e.f(d + 2)}), Vec2({e.f(d + 1)}, {e.f(d + 3)}){offset})")

# TLD (TLD.B: its handle in B, yuzu's texture_load.cpp): a texel of a 2D texture, an array or a
# 3D texture at integer coordinates from A (an array's layer first), then from B on the handle,
# the level (LOD), the offset (AOFFI, added to the coordinates)
pub fn emitTld(mut e Emitter, i Instr):
	dim = i.field(28, 3)
	if dim != tex2D and dim != tex2DArray and dim != tex3D or i.flag(50) or i.flag(54) or
		i.field(51, 3) != pt:
		e.lack(i, "TLD: 1D, a cube, multisampled, clamped or sparse", i.texDestinations())
		return
	handle, bank, meta = e.handleOf(i, i.field(20, 8)) ?? return
	kind = e.kindOf(handle, dim, false) ??
		return e.lack(i, "TLD of integers not 2D", i.texDestinations())
	lod = "0"
	if i.flag(55):
		lod = "i32({e.x(meta)})"
		meta += 1
	offset = meta if i.flag(35) else -1
	t = e.textureOf(handle, kind, bank)
	e.storeMasked(i, "{t}.fetch({e.texels(i.ra, dim, offset)}, {lod})", kind)

# TLD4 (TLD4.B: its handle in B): a gather of component 56 (38) of a 2D texture, an array or a
# cube, or a shadow map's depth comparisons, from B on the handle, the offset (six bits at 0 and
# 8; a cube's none) and the reference
pub fn emitTld4(mut e Emitter, i Instr):
	bindless = i.form == .Bindless
	kind = i.field(28, 3)
	offsetKind = i.field(36 if bindless else 54, 2)
	cube = kind == texCube or kind == texCubeArray
	if kind != 2 and kind != 3 and not cube or offsetKind > 1 or cube and offsetKind != 0 or
		i.field(51, 3) != pt:
		e.lack(
			i,
			"TLD4: 1D, 3D, per-texel offsets, a cube's offset or a sparse result",
			i.texDestinations()
		)
		return
	handle, bank, meta = e.handleOf(i, i.field(20, 8)) ?? return
	offset = ""
	if offsetKind == 1:
		offset = e.offsetOf(meta, 6, 8) ?? return e.lackOffset(i)
		meta += 1
	shadow = i.flag(50)
	t = e.textureOf(handle, e.filteredKind(i, handle, kind, shadow) ?? return, bank)
	args = e.coordinates(i.ra, kind)
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
	handle = i.field(36, 13)
	t = e.textureOf(handle, e.filteredKind(i, handle, tex2D, shadow) ?? return)
	uv = "Vec2({e.f(a)}, {e.f(a + 1)})" if offsetGiven or shadow else "Vec2({e.f(a)}, {e.f(b)})"
	depth = e.f(b + 1 if offsetGiven else b)
	read = "gatherCompare({uv}, {depth}" if shadow else "gather({uv}, {i.field(52, 2)}"
	e.line("texel = {t}.{read}{offset})")
	d = i.field(28, 8)
	places = [i.rd, i.rd + 1, d, d + 1]
	for c in 0..4:
		if places[c - c % 2] != rz: e.setF(places[c], "texel.{components4[c]}")

# TMML (TMML.B: its handle in B): the level of detail of a 2D texture, an array, a 3D texture or
# a cube at the coordinates from A (an array's after its layer), the level read and the one
# asked as fixed point of 8 fraction bits
pub fn emitTmml(mut e Emitter, i Instr):
	kind = i.field(28, 3)
	if kind not in [tex2D, tex2DArray, tex3D, texCube, texCubeArray] or i.field(31, 4) & 0xC != 0:
		e.lack(i, "TMML: 1D, a 3D array, or its third and fourth results", i.texDestinations())
		return
	handle, bank, _ = e.handleOf(i, i.field(20, 8)) ?? return
	t = e.textureOf(handle, e.filteredKind(i, handle, kind, false) ?? return, bank)
	c = i.ra + (1 if kind == tex2DArray or kind == texCubeArray else 0)
	uv = "Vec2({e.f(c)}, {e.f(c + 1)})" if kind == tex2D or kind == tex2DArray
		else "Vec3({e.f(c)}, {e.f(c + 1)}, {e.f(c + 2)})"
	e.line("level = {t}.lod({uv})")
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
