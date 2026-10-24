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
		if shader.isLayered(kind): return "zapSizeArray({texture}, {level})"
		return "zapSize({texture}, {level})"
	pixel = h.stage == shader.stageFragment
	uv = h.texts[r.uv]
	if inst.key == "lod":
		if not pixel: return "float2(0.0, 0.0)"
		return "float2({texture}.CalculateLevelOfDetail({sampler}, {uv}), {texture}.CalculateLevelOfDetailUnclamped({sampler}, {uv}))"
	args = [sampler]
	args.push(
		"float3({uv}, {h.hConvert(h.texts[r.layer], h.tys[r.layer], ft)})" if r.layer >= 0
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
	k = r.constants
	if k.offset:
		args.push("int2({k.x}, {k.y})")
	"{texture}.{name}({args.join(", ")})"
