# The textures' reads in SPIR-V (irTexture, shader.textureMethods): a sample at the level the
# derivatives give in a pixel stage (by a bias) and at an explicit one elsewhere, as a stage
# without derivatives reads the first level (or the bias's); the image operands Bias, Lod, Grad
# and ConstOffset in that order; gathers; a shadow map's comparisons (Dref) at its first level (it
# has one); the level of detail
# (ImageQueryLod, a pixel stage's: elsewhere (0, 0)); the size at a level.

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
	if inst.key == "lod":
		if not pixel: return w.spvConstOf(t, 0)
		w.imageQuery = true
		return w.spvVal(shader.opImageQueryLod, t, [s, w.spvGet(r.uv)])
	c = w.spvGet(r.uv)
	if r.layer >= 0:
		c = w.spvVal(
			shader.opCompositeConstruct,
			shader.vector(shader.bFloat, 3),
			[c, w.spvConvert(w.spvGet(r.layer), w.tys[r.layer], ft)]
		)
	ops = [s, c]
	if r.depth >= 0:
		ops.push(w.spvConvert(w.spvGet(r.depth), w.tys[r.depth], ft))
	if inst.key == "gather":
		ops.push(w.spvInt(r.constants.component))
		ops.extend(w.spvImageOperands(0, [], r.constants))
		return w.spvVal(shader.opImageGather, t, ops)
	if inst.key == "gatherCompare":
		ops.extend(w.spvImageOperands(0, [], r.constants))
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
	ops.extend(w.spvImageOperands(mask, ids, r.constants))
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
	k shader.TextureConstants
):
	out = [mask | (imageConstOffset if k.offset else 0)]
	if out[0] == 0: return []
	out.extend(ids)
	if k.offset:
		int2 = shader.vector(shader.bInt, 2)
		out.push(w.spvConstComposite(int2, [w.spvInt(k.x), w.spvInt(k.y)]))
	out

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
