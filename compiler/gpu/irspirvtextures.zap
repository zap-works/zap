# The textures' reads in SPIR-V (irTexture, shader.textureMethods): a sample at the level the
# derivatives give in a pixel stage (by a bias) and at an explicit one elsewhere, as a stage
# without derivatives reads the first level (or the bias's); the image operands Bias, Lod, Grad
# and ConstOffset in that order; gathers; a shadow map's comparisons (Dref) at its first level (it
# has one); the level of detail
# (ImageQueryLod, a pixel stage's: elsewhere (0, 0)); the size at a level; a fetch of a texel,
# 0 outside the level or past the levels (as Direct3D's Load gives, where Vulkan's is undefined
# without robustness: the texel read is clamped inside, and chosen only when it was).

import shader

imageBias = 1
imageLod = 2
imageGrad = 4
imageConstOffset = 8

fn spvTexture(mut w SpvWriter, inst IrInst, t shader.Ty) i64:
	kind = w.tys[inst.a].sid
	ptr = w.spvGet(inst.a)
	s = w.spvVal(shader.opLoad, w.tys[inst.a], [ptr])
	if ptr in w.nonUniform:
		w.spvMarkNonUniform(s)
	all = [inst.a]
	all.extend(inst.args)
	r = shader.textureArgsOf(kind, inst.key, all, inst.imm)
	ft = shader.scalar(shader.bFloat)
	pixel = w.stage == shader.stageFragment
	if inst.key == "size": return w.spvTextureSize(s, kind, r.level, t)
	if inst.key == "fetch": return w.spvFetch(s, kind, r, t)
	if inst.key == "lod":
		if not pixel: return w.spvConstOf(t, 0)
		w.imageQuery = true
		return w.spvVal(shader.opImageQueryLod, t, [s, w.spvGet(r.uv)])
	c = w.spvGet(r.uv)
	if r.layer >= 0:
		c = w.spvVal(
			shader.opCompositeConstruct,
			shader.vector(shader.bFloat, shader.coordinateSize(kind) + 1),
			[c, w.spvConvert(w.spvGet(r.layer), w.tys[r.layer], ft)]
		)
	ops = [s, c]
	if r.depth >= 0:
		ops.push(w.spvConvert(w.spvGet(r.depth), w.tys[r.depth], ft))
	if inst.key == "gather":
		ops.push(w.spvInt(r.constants.component))
		ops.extend(w.spvImageOperands(0, [], r.constants, kind))
		return w.spvVal(shader.opImageGather, t, ops)
	if inst.key == "gatherCompare":
		ops.extend(w.spvImageOperands(0, [], r.constants, kind))
		return w.spvVal(shader.opImageDrefGather, t, ops)
	level = w.spvConvert(w.spvGet(r.level), w.tys[r.level], ft) if r.level >= 0
		else w.spvFloat(0.0)
	mask = imageLod
	ids = [level]
	if inst.key == "sampleGrad":
		mask = imageGrad
		ids = [w.spvGet(r.dx), w.spvGet(r.dy)]
	elif pixel and inst.key == "sampleBias":
		mask = imageBias
	elif pixel and inst.key == "sample":
		mask = 0
		ids = []
	ops.extend(w.spvImageOperands(mask, ids, r.constants, kind))
	explicit = mask & (imageLod | imageGrad) != 0
	if r.depth >= 0:
		code = shader.opImageSampleDrefExplicitLod if explicit
			else shader.opImageSampleDrefImplicitLod
		return w.spvVal(code, ft, ops)
	code = shader.opImageSampleExplicitLod if explicit else shader.opImageSampleImplicitLod
	w.spvVal(code, t, ops)

# the image operands: the mask and its ids, the constant offset after them; none when empty
fn spvImageOperands(
	mut w SpvWriter,
	mask i64,
	ids i64[],
	k shader.TextureConstants,
	kind i64
):
	out = [mask | (imageConstOffset if k.offset else 0)]
	if out[0] == 0: return []
	out.extend(ids)
	if k.offset:
		out.push(w.spvOffset(k, kind))
	out

# the constant offset of a read, a vector of the kind's size
fn spvOffset(mut w SpvWriter, k shader.TextureConstants, kind i64) i64:
	n = shader.coordinateSize(kind)
	parts = [w.spvInt(k.x), w.spvInt(k.y), w.spvInt(k.z)]
	w.spvConstComposite(shader.vector(shader.bInt, n), parts[..n].copy())

# A texel at integer coordinates (the offset added, an array's layer after them) of a level, 0
# outside it: the level clamped to the texture's, the coordinates to its size there, and the
# texel read there chosen only when neither moved.
fn spvFetch(mut w SpvWriter, s i64, kind i64, r shader.TextureArgs, t shader.Ty) i64:
	w.imageQuery = true
	int = shader.scalar(shader.bInt)
	image = w.spvValId(shader.opImage, w.spvImageType(kind), [s])
	if s in w.nonUniform:
		w.spvMarkNonUniform(image)
	n = shader.coordinateSize(kind)
	c = w.spvGet(r.uv)
	if r.constants.offset:
		c = w.spvVal(shader.opIAdd, shader.vector(shader.bInt, n), [c, w.spvOffset(r.constants, kind)])
	if r.layer >= 0:
		n += 1
		c = w.spvVal(
			shader.opCompositeConstruct,
			shader.vector(shader.bInt, n),
			[c, w.spvConvert(w.spvGet(r.layer), w.tys[r.layer], int)]
		)
	ints = shader.vector(shader.bInt, n)
	bools = shader.vector(shader.bBool, n)
	level = w.spvConvert(w.spvGet(r.level), w.tys[r.level], int)
	top = w.spvVal(
		shader.opISub,
		int,
		[w.spvVal(shader.opImageQueryLevels, int, [image]), w.spvInt(1)]
	)
	lod = w.spvExt(int, 45, [level, w.spvInt(0), top])   # SClamp
	size = w.spvVal(shader.opImageQuerySizeLod, ints, [image, lod])
	zero = w.spvConstOf(ints, 0)
	last = w.spvVal(shader.opISub, ints, [size, w.spvConstComposite(ints, fill(n, w.spvInt(1)))])
	at = w.spvExt(ints, 45, [c, zero, last])
	same = w.spvVal(
		shader.opAll,
		shader.scalar(shader.bBool),
		[w.spvVal(shader.opIEqual, bools, [at, c])]
	)
	inside = w.spvVal(
		shader.opLogicalAnd,
		shader.scalar(shader.bBool),
		[same, w.spvVal(shader.opIEqual, shader.scalar(shader.bBool), [lod, level])]
	)
	texel = w.spvVal(shader.opImageFetch, t, [image, at, imageLod, lod])
	w.spvVal(shader.opSelect, t, [inside, texel, w.spvConstOf(t, 0)])

# a vector of constants, made once
fn spvConstComposite(mut w SpvWriter, t shader.Ty, parts i64[]):
	tid = w.spvType(t)
	key = "cc{tid}{parts.map(":{it}").join("")}"
	if w.m.made.get(key) is id: return id
	id = w.m.newId()
	ops = [tid, id]
	ops.extend(parts)
	emit(w.m.globals, shader.opConstantComposite, ops)
	w.m.made[key] = id
	id

# the size of the texture's level (vreg level, or the first)
fn spvTextureSize(mut w SpvWriter, s i64, kind i64, level i64, t shader.Ty) i64:
	lod = w.spvConvert(w.spvGet(level), w.tys[level], shader.scalar(shader.bInt)) if level >= 0
		else w.spvInt(0)
	w.imageQuery = true
	image = w.spvValId(shader.opImage, w.spvImageType(kind), [s])
	if s in w.nonUniform:
		w.spvMarkNonUniform(image)
	w.spvVal(shader.opImageQuerySizeLod, t, [image, lod])
