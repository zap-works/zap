# The sun's cascaded shadow maps as BSShadowDirectionalLight draws them in the exterior
# (0x14157f080, the per-frame fit): the view's depth from the camera's near plane to
# fShadowDistance cut into three slices, each slice's eight corners boxed by the sun's camera (an
# orthographic camera that looks along the light from 15000 units toward the sun of the slice's
# middle, so everything between the sun and the slice casts) into a depth map of iShadowMapResolution,
# read by the pixel stage (shaders/sunShadow.gpu.zap) from the cascade a place's view depth falls in.
#
# From the executable: the slices' ends are the practical split scheme with half weight on the
# logarithmic one, ((far - near) f + near + near (far / near)^f) / 2 + fSplitOverlap, with f
# climbing linearly from min(distance / 3, max(fFirstSliceDistance, 500)) / distance to 1; slice
# k + 1 starts at the end of slice k less twice the overlap, so the two are blended across their
# overlap. The bias is fShadowBiasScale times 0.00025 times fShadowDirectionalBiasScale for the
# first cascade and fShadowBiasScale times 8.33e-5 for the others (the focus bias terms of
# Utility.hlsl, 0x141568300). Land casts no shadows (bDrawLandShadows 0): only the cell's objects.
#
# Not ported: the actors' focus shadows, the screen-space shadows' contact refinement, the sun's
# shadow update interval (fSunShadowUpdateTime), tree and grass casting rules.

import engine
import world.shaders

# the ini values, from reference/exe/README.md, "Ini settings: [Display]"
shadowDistance f32 = 8000.0   # fShadowDistance:Display
firstSliceDistance f32 = 1250.0   # fFirstSliceDistance
sliceFloor f32 = 500.0   # the least the first slice may be (0x141b5bfac)
splitOverlap f32 = 100.0   # fSplitOverlap
pub cascadeCount = 3
mapResolution = 2048   # iShadowMapResolution
lightDistance f32 = 15000.0   # how far the sun's camera stands from the slice (0x141b4e684)
lightDepth f32 = 30000.0   # the depth its orthographic projection covers
biasScale f32 = 1.0   # fShadowBiasScale
directionalBiasScale f32 = 0.3   # fShadowDirectionalBiasScale
firstBias f32 = 0.00025
otherBias f32 = 8.3333339e-5

# The fraction of the shadow distance each slice reaches: the first slice's, then linearly to 1
pub fn splitFractions(count i64, distance f32) f32[]:
	first = (distance / f32(count)).min(firstSliceDistance.max(sliceFloor)) / distance
	out = [first]
	for k in 1..count:
		out.push((1.0 - first) * f32(k) * (1.0 / f32(count - 1)) + first)
	out

# The view depths each slice ends at, for a camera whose near plane is `near` and whose shadows
# reach `distance` (the far plane or the shadow distance, whichever is less)
pub fn sliceEnds(near f32, distance f32, count i64) f32[]:
	reach = distance.min(shadowDistance)
	out = []
	for f in splitFractions(count, shadowDistance):
		linear = (reach - near) * f + near
		logarithmic = near * (reach / near).pow(f)
		out.push((linear + logarithmic) * 0.5 + splitOverlap)
	out

# where each slice starts: the first at the camera, the others where the one before ends less twice
# the overlap
pub fn sliceStarts(ends f32[]) f32[]:
	out f32[] = [0.0]
	for k in 1..ends.len:
		out.push(ends[k - 1] - splitOverlap * 2.0)
	out

# one cascade: the matrix taking a place to the sun camera's clip space (x and y -1..1, z -1..1
# over lightDepth), and the box it covers
pub type Cascade:
	projection Mat4
	width f32
	height f32

# the camera's frustum between two view depths: its eight corners, in the world
fn sliceCorners(toWorld Mat4, halfX f32, halfY f32, near f32, far f32):
	out = []
	depths f32[] = [near, far]
	signs f32[] = [-1.0, 1.0]
	for d in depths:
		for sy in signs:
			for sx in signs:
				out.push(toWorld.applyPoint(Vec3(sx * halfX * d, sy * halfY * d, -d)))
	out

# a matrix from rows and a last column
fn rows(r0 Vec4, r1 Vec4, r2 Vec4):
	Mat4(
		[r0.x, r1.x, r2.x, 0.0, r0.y, r1.y, r2.y, 0.0, r0.z, r1.z, r2.z, 0.0, r0.w, r1.w, r2.w, 1.0]
	)

# The cascade covering a slice's corners from the sun: the camera at `toward` * lightDistance from
# the slice's middle looking along the light, its box the corners' extent in its x and y rounded out
# to whole texels of the map (so the map's texels do not swim as the camera turns).
pub fn fitCascade(corners Vec3[], toward Vec3) Cascade:
	total = Vec3(0.0, 0.0, 0.0)
	for c in corners:
		total += c
	middle = total * (1.0 / f32(corners.len))
	origin = middle + toward * lightDistance
	up = Vec3(0.0, 1.0, 0.0) if toward.y.abs() < 0.999 else Vec3(1.0, 0.0, 0.0)
	lx = up.cross(toward).normalized()
	ly = toward.cross(lx)
	lo = Vec2(1.0e9, 1.0e9)
	hi = Vec2(-1.0e9, -1.0e9)
	for c in corners:
		d = c - origin
		lo = Vec2(lo.x.min(d @ lx), lo.y.min(d @ ly))
		hi = Vec2(hi.x.max(d @ lx), hi.y.max(d @ ly))
	texel = (hi - lo) * (1.0 / f32(mapResolution))
	lo = Vec2((lo.x / texel.x).floor() * texel.x, (lo.y / texel.y).floor() * texel.y)
	hi = Vec2((hi.x / texel.x).ceil() * texel.x, (hi.y / texel.y).ceil() * texel.y)
	size = hi - lo
	back = toward * -1.0
	Cascade(
		projection = rows(
			(lx * (2.0 / size.x)).withW(-(origin @ lx + lo.x) * 2.0 / size.x - 1.0),
			(ly * (2.0 / size.y)).withW(-(origin @ ly + lo.y) * 2.0 / size.y - 1.0),
			(back * (2.0 / lightDepth)).withW((origin @ toward) * 2.0 / lightDepth - 1.0)
		),
		width = size.x,
		height = size.y
	)

# The sun's cascades for a camera: its place and view, its projection's x and y scales (the cotangents
# of its half angles) and near plane, and the direction toward the sun
pub type SunCascades:
	cascades Cascade[]
	ends f32[]
	starts f32[]

pub fn fitSun(view Mat4, scaleX f32, scaleY f32, near f32, far f32, toward Vec3) SunCascades:
	toWorld = view.inverseAffine()
	ends = sliceEnds(near, far, cascadeCount)
	starts = sliceStarts(ends)
	cascades = []
	for k in 0..cascadeCount:
		corners = toWorld.sliceCorners(1.0 / scaleX, 1.0 / scaleY, starts[k].max(near), ends[k])
		cascades.push(fitCascade(corners, toward))
	SunCascades(cascades, ends, starts)

# the sun's maps on the GPU: the program that draws a cascade's depth and a depth target a cascade
pub type SunShadows:
	program engine.Program
	maps engine.RenderTarget[]

pub fn newSunShadows() SunShadows:
	maps = []
	loop cascadeCount:
		maps.push(engine.newShadowTargetBy(mapResolution, mapResolution))
	SunShadows(
		program = engine.newProgram(shader(shaders.sunShadowVertex, shaders.sunShadowPixel)),
		maps
	)

# the cell's pixel parameters set to read this frame's cascades
pub fn useSunShadows(mut p shaders.CellParams, s SunShadows, fit SunCascades):
	p.sunShadowCount = i32(cascadeCount)
	p.sunProjection0 = fit.cascades[0].projection
	p.sunProjection1 = fit.cascades[1].projection
	p.sunProjection2 = fit.cascades[2].projection
	p.sunEnds = Vec4(fit.ends[0], fit.ends[1], fit.ends[2], 0.0)
	p.sunStarts = Vec4(fit.starts[0], fit.starts[1], fit.starts[2], 0.0)
	p.sunBias = Vec4(
		biasScale * firstBias * directionalBiasScale,
		biasScale * otherBias,
		0.0,
		0.0
	)
	p.sunShadowDistance2 = shadowDistance * shadowDistance
	p.sunShadow0 = s.maps[0].shadowMap()
	p.sunShadow1 = s.maps[1].shadowMap()
	p.sunShadow2 = s.maps[2].shadowMap()

# The cascades fitted for this frame's camera and the cell's parameters set to read them; none
# where the sky has no sun up (the maps then stay out of the way)
pub fn fitSunShadows(mut sc CellScene, projection Mat4, view Mat4):
	lit = false
	if sc.sky is sky: lit = sky.daylight > 0.0
	if not lit:
		sc.params.sunShadowCount = 0
		return
	if sc.sunShadows == none: sc.sunShadows = newSunShadows()
	m = projection.m
	fit = fitSun(
		view,
		m[0],
		m[5],
		m[14] / (m[10] - 1.0),
		m[14] / (m[10] + 1.0),
		sc.params.sunToward.xyz
	)
	if sc.sunShadows is s: sc.params.useSunShadows(s, fit)

# every cascade's depth map drawn from the cell's opaque and cut-out runs
pub fn drawSunShadowMaps(mut r engine.Renderer, sc CellScene):
	if sc.params.sunShadowCount < 1: return
	if sc.sunShadows is s:
		p = sc.params.copy()
		r.setBlending(false)
		r.setDepthBias(true)
		for k in 0..cascadeCount:
			r.useTarget(s.maps[k])
			r.clearTarget(engine.white)
			r.setDepth(true, true, false)
			p.sunCascade = k
			s.program.setParams(p)
			for run in sc.runs:
				if run.kind != .Opaque and run.kind != .Tested: continue
				r.drawIndexed(s.program, sc.model, sc.indices, run.count, firstIndex = run.first)
		r.setDepthBias(false)
