# The textures' reads in HLSL (irTexture, shader.textureMethods), as the SPIR-V writes them: a
# pixel stage's at the level its derivatives give (Sample, SampleBias), another's at an explicit
# one (the first, or the bias's); a comparison at the first (a shadow map has one); gathers by component; the level of detail as
# (CalculateLevelOfDetail, CalculateLevelOfDetailUnclamped); the size at a level, as the uint
# HLSL takes. A constant offset is the call's last argument.

import shader

gatherNames = ["GatherRed", "GatherGreen", "GatherBlue", "GatherAlpha"]

fn hTexture(h HlslWriter, inst IrInst, t shader.Ty):
	tex = h.texts[inst.a]
	kind = h.tys[inst.a].sid
	all = [inst.a]
	all.extend(inst.args)
	r = shader.textureArgsOf(kind, inst.key, all, inst.imm)
	texture = h.hTexturePart(tex, "_t")
	sampler = h.hTexturePart(tex, "_s")
	ft = shader.scalar(shader.bFloat)
	if inst.key == "size":
		level = h.hConvert(h.texts[r.level], h.tys[r.level], shader.scalar(shader.bUint))
			if r.level >= 0
			else "0u"
		return "zapSize({texture}, {level})"
	pixel = h.stage == shader.stageFragment
	uv = h.texts[r.uv]
	if inst.key == "fetch": return h.hFetch(texture, kind, r)
	if inst.key == "lod":
		if not pixel: return "float2(0.0, 0.0)"
		return "float2({texture}.CalculateLevelOfDetail({sampler}, {uv}), {texture}.CalculateLevelOfDetailUnclamped({sampler}, {uv}))"
	args = [sampler]
	n = shader.coordinateSize(kind)
	args.push(
		"float{n + 1}({uv}, {h.hConvert(h.texts[r.layer], h.tys[r.layer], ft)})" if r.layer >= 0
		else uv.copy()
	)
	if r.depth >= 0:
		args.push(h.hConvert(h.texts[r.depth], h.tys[r.depth], ft))
	level = h.hConvert(h.texts[r.level], h.tys[r.level], ft) if r.level >= 0 else "0.0"
	name = ""
	if inst.key == "gather":
		name = gatherNames[r.constants.component].copy()
	elif inst.key == "gatherCompare":
		name = "GatherCmp"
	elif r.depth >= 0:
		name = "SampleCmpLevelZero"
	elif inst.key == "sampleGrad":
		name = "SampleGrad"
		args.push(h.texts[r.dx].copy())
		args.push(h.texts[r.dy].copy())
	elif pixel and inst.key == "sample":
		name = "Sample"
	elif pixel and inst.key == "sampleBias":
		name = "SampleBias"
		args.push(level)
	else:
		name = "SampleLevel"
		args.push(level)
	if r.constants.offset:
		args.push(hOffset(r.constants, kind))
	"{texture}.{name}({args.join(", ")})"

# a read's constant offset, a vector of the kind's size
fn hOffset(k shader.TextureConstants, kind i64):
	n = shader.coordinateSize(kind)
	"int{n}({[k.x, k.y, k.z][..n].map(str(it)).join(", ")})"

# a fetch: Load of the texel (an array's layer and the level after its coordinates), which gives
# 0 outside the level or past the levels
fn hFetch(h HlslWriter, texture str, kind i64, r shader.TextureArgs):
	int = shader.scalar(shader.bInt)
	parts = [h.texts[r.uv].copy()]
	if r.layer >= 0:
		parts.push(h.hConvert(h.texts[r.layer], h.tys[r.layer], int))
	parts.push(h.hConvert(h.texts[r.level], h.tys[r.level], int))
	n = shader.coordinateSize(kind) + (2 if r.layer >= 0 else 1)
	offset = ", {hOffset(r.constants, kind)}" if r.constants.offset else ""
	"{texture}.Load(int{n}({parts.join(", ")}){offset})"

# zapSize(t, lod), the size of a level of each texture HLSL declares, as the shader reads it
fn hDeclareSizes(mut h HlslWriter):
	done str[] = []
	for kind, k in shader.samplerKinds:
		if k.hlslTexture in done: continue
		done.push(k.hlslTexture.copy())
		parts = ["w", "h", "d"][..shader.sizeComponents(kind + 1)].copy()
		h.hLine("int{parts.len} zapSize({k.hlslTexture} t, uint lod) \{ uint {parts.join(", ")}, levels; t.GetDimensions(lod, {parts.join(", ")}, levels); return int{parts.len}({parts.join(", ")}); }")
