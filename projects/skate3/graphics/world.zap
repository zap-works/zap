# The prepared district on the GPU and drawn: a texture for every color texture and lightmap
# page, a material for every batch of triangles (its textures by their index in the district's
# table), and one model per kind of batch holding all of that kind's triangles in their order,
# each vertex naming its batch's material: the district is four draws, opaque first, then cut
# out, then decals, then the see-through ones; the sky's color behind and the haze in front.

import engine
import image
import skate
import graphics.shaders

pub type WorldScene:
	program engine.Program
	params shaders.WorldParams   # the district's textures and materials, and the frame's view
	textures engine.GpuTexture[]   # whose handles the params read
	kinds engine.Model[]   # by skate's kind
	depth engine.RenderTarget
	sky Vec4

# the light the lightmap pages hold, scaled by the game's exposure (its shaders work on squared
# colors: diffuse² · lightmap² · 0.93 · exposure, then the square root)
lightmapScale f32 = 1.4
hazeDistance f32 = 900.0

pub tiled = engine.Sampling(
	smooth = true,
	mipmaps = true,
	repeat = true,
	mirror = 0,
	anisotropy = true
)
clamped = engine.Sampling(
	smooth = true,
	mipmaps = true,
	repeat = false,
	mirror = 0,
	anisotropy = false
)

# textures on the GPU: their owners, their handles by id, and a white one for what has none
pub type GpuTextures:
	owned engine.GpuTexture[]
	byId {i64: engine.Texture}
	white engine.Texture

# each texture sent to the GPU, tiled, or clamped when its id is in clampedIds
fn uploadTextures(textures skate.WorldTexture[], clampedIds {i64: bool}):
	owned = []
	byId {i64: engine.Texture} = {}
	for t in textures:
		sampling = clamped if t.id in clampedIds else tiled
		texture = t.image.newTexture(sampling)
		byId[t.id] = texture.texture()
		owned.push(texture)
	whiteTexture = image.fromBytes(1, 1, [255, 255, 255, 255]).newTexture(tiled)
	white = whiteTexture.texture()
	owned.push(whiteTexture)
	GpuTextures(owned, byId, white)

# The world's textures and batches sent to the GPU (the prepared data is dropped as it goes).
pub fn newWorldScene(move w skate.PreparedWorld) WorldScene:
	lightmapIds {i64: bool} = {}
	for b in w.batches:
		lightmapIds[b.lightmap] = true
	# a lightmap page is not repeated past its edges
	gpu = uploadTextures(w.textures, lightmapIds)
	textures = gpu.byId
	white = gpu.white
	program = engine.newProgram(shader(shaders.worldVertex, shaders.worldPixel))
	table = engine.TextureTable()
	materials = []
	kinds u8[,] = [[], [], [], []]
	for b in w.batches:
		material = i32(materials.len)
		materials.push(shaders.Material(
			color = table.indexOf(textures.get(b.color) ?? white),
			lightmap = table.indexOf(textures.get(b.lightmap) ?? white),
			extra = table.indexOf(textures.get(b.extra) ?? white),
			lightmapScale = lightmapScale if b.lightmap in textures else -1.0,
			extraAlpha = 1 if b.kind == skate.kindCutout and b.extra in textures else 0))
		placeVertices(kinds[b.kind], b.vertices, material)
	models = kinds.map(engine.newModel(it, program.vertexStride))
	sky = Vec4(0.62, 0.74, 0.86, 1.0)
	params = shaders.WorldParams(
		projection = Mat4(1.0),
		view = Mat4(1.0),
		mode = .Opaque,
		eye = Vec3(0.0, 0.0, 0.0),
		haze = shaders.Haze(color = Vec3(sky.r, sky.g, sky.b), halfway = hazeDistance),
		sun = Vec3(0.4, 0.8, 0.3).normalized(),
		show = .Everything,
		textures = table.textures, materials = move materials)
	WorldScene(
		program,
		params,
		textures = gpu.owned,
		kinds = models,
		depth = engine.newDepthTarget(1, 1),
		sky
	)

# the prepared vertices (shaders.WorldVertex, 40 bytes) added to a kind's as PlacedVertex values:
# each followed by the batch's material
fn placeVertices(mut into u8[], vertices u8[], material i32):
	m = i64(material)
	tail = [u8(m & 255), u8(m.bits(8, 8)), u8(m.bits(16, 8)), u8(m.bits(24, 8))]
	into.reserve(into.len + vertices.len / 40 * 44)
	at = 0
	while at + 40 <= vertices.len:
		into.extend(vertices[at..at + 40])
		into.extend(tail)
		at += 40

# the haze of distance: the sky's color, half thick at hazeDistance
pub fn hazeOf(sc WorldScene) shaders.Haze:
	shaders.Haze(color = Vec3(sc.sky.r, sc.sky.g, sc.sky.b), halfway = hazeDistance)

# a batch's kind (skate's) as the shader's mode
fn modeOf(kind i64) shaders.Mode:
	match kind:
		1: .CutOut
		2: .Blended
		3: .Decal
		_: .Opaque

# Begins the frame on a screen of w x h pixels: cleared to the sky, with a depth of its own.
pub fn beginWorld(mut r engine.Renderer, mut sc WorldScene, w i64, h i64):
	if sc.depth.width != w or sc.depth.height != h:
		sc.depth = engine.newDepthTarget(w, h)
	r.useScreenWithDepth(sc.depth)
	r.clearTarget(sc.sky)

# the world seen from `eye` through the projection and view
pub fn drawWorld(
	mut r engine.Renderer,
	mut sc WorldScene,
	projection Mat4,
	view Mat4,
	eye Vec3,
	show i64 = 0
):
	p = sc.program
	shown = match show:
		1: shaders.Show.Lightmap
		2: shaders.Show.Color
		3: shaders.Show.Kind
		_: shaders.Show.Everything
	sc.params.projection = projection
	sc.params.view = view
	sc.params.eye = eye
	sc.params.haze = sc.hazeOf()
	sc.params.show = shown
	for pass in [skate.kindOpaque, skate.kindCutout, skate.kindDecal, skate.kindBlended]:
		r.setBlending(pass == skate.kindBlended)
		r.setDepth(true, pass != skate.kindBlended, false)
		sc.params.mode = modeOf(pass)
		p.setParams(sc.params)
		r.drawModel(p, sc.kinds[pass])
	r.setBlending(false)
	r.setDepth(true, true, false)
