# Drawing: textures, and the renderer: the state its draws are drawn with (gpu.zap) and a
# sprite batch that collects textured, tinted quads (four corners each, drawn by a shared index
# buffer) and draws them in a single call, each quad naming its texture among the batch's. A frame of the batch is beginFrame (clear, set the camera), draws, then endFrame
# (flush what is left). Coordinates are pixels of the camera's view, y downward.

import rhi
import rhi.core
import image
import math

# a texture as a shader's parameters and the batch read it: a handle, made by the texture that
# owns it (GpuTexture.texture, RenderTarget.colorTexture), valid while that owner lives
pub type Texture:
	id i64
	width i64
	height i64

# a texture on the GPU, destroyed where it is dropped
pub type GpuTexture:
	id i64 = -1   # the RHI's texture, -1 none
	width i64 = 0
	height i64 = 0

	# the handle shaders and the batch read it by
	pub fn texture() Texture:
		Texture(id, width, height)

	# the draws put off that may read it drawn first
	mut fn drop():
		if id >= 0:
			drawQueued()
			gpu.destroyTexture(id)

# how a texture is read: smoothed or sharp, mipmapped, repeating past its edges, sharpened at
# grazing angles (anisotropy)
pub type Sampling:
	smooth bool
	mipmaps bool
	repeat bool
	mirror i64   # mirrored repeats: 1 across, 2 down, 3 both
	anisotropy bool

# sharp texels up close, mipmapped far away, repeating: blocks and tiles
pub pixelArt = Sampling(
	smooth = false,
	mipmaps = true,
	repeat = true,
	mirror = 0,
	anisotropy = true
)
# sharp texels, one level, clamped: sprites, the batch's textures
pub sharpClamped = Sampling(
	smooth = false,
	mipmaps = false,
	repeat = false,
	mirror = 0,
	anisotropy = false
)
# smoothed, mipmapped and repeating: surfaces seen from afar and up close
pub smoothTiled = Sampling(
	smooth = true,
	mipmaps = true,
	repeat = true,
	mirror = 0,
	anisotropy = true
)

# a rectangle of a texture, in pixels (an atlas frame, a tile)
pub type Region:
	tex Texture
	x i64
	y i64
	w i64
	h i64

pub type Camera:
	x f32 = 0.0   # the world point at the view's top-left corner
	y f32 = 0.0
	zoom f32 = 1.0   # pixels of the screen per pixel of the world

# what draws are drawn with, and the sprite batch
pub type Renderer:
	state DrawState = DrawState()
	program Program
	vertices SpriteVertex[]
	textures Texture[]   # those the quads collected name
	arrays bool   # the device has texture arrays: a batch names up to maxTextures, else one
	image i32   # the one the last quad named
	corners IndexBuffer   # a quad's two triangles of its four corners, for every quad of a batch
	white GpuTexture   # one opaque white pixel: rectangles are quads of it
	drawCalls i64   # since the frame began
	quads i64
	viewW i64
	viewH i64
	view Mat4

maxQuads = 16_384
maxTextures = 64   # of a batch

# the batch: its program (shaders.zap's sprite stages, of one texture where the device has no
# texture arrays), a white texel for plain rectangles
pub fn newRenderer() Renderer:
	arrays = gpu.textureArrays()
	Renderer(
		program = newProgram(shader(spriteVertex, spritePixel)) if arrays
			else newProgram(shader(spriteVertexOne, spritePixelOne)),
		vertices = [],
		textures = [],
		arrays,
		image = 0,
		corners = newIndexBuffer((0..maxQuads * 6).map(u32(it / 6 * 4 + quadCorners[it % 6]))),
		white = image.fromBytes(1, 1, [255, 255, 255, 255]).newTexture(),
		drawCalls = 0, quads = 0, viewW = 0, viewH = 0, view = Mat4(1.0))

# ---------- textures ----------

# A texture of an image, read as `sampling` says (sharp and clamped by default: pixel art stays
# sharp); its mip levels made when the sampling wants them.
pub fn newTexture(img image.Image, sampling Sampling = sharpClamped) GpuTexture:
	newTextureOfFormat(img.width, img.height, img.cells.bytes(), sampling)

# A texture of width x height pixels of a format: `pixels` holds the first level's bytes (rows of
# pixels, or of blocks of 4x4 pixels, the texture then a multiple of 4 wide and high) and `mips`
# the smaller levels made ahead (each the size of the one before halved).
pub fn newTextureOfFormat(
	width i64,
	height i64,
	pixels u8[],
	sampling Sampling = sharpClamped,
	format TextureFormat = .Rgba8,
	mips u8[,] = []
) GpuTexture:
	expected = format.levelBytes(width, height)
	if pixels.len != expected:
		fail("a {width}x{height} texture needs {expected} bytes, got {pixels.len}")
	code = format.code()
	id = makeTexture(width, height, 1, code, 1 + mips.len, false, sampling, (texture i64):
		gpu.writeTextureLevel(texture, 0, 0, pixels)
		for level, mip in mips:
			gpu.writeTextureLevel(texture, level + 1, 0, mip)
	)
	GpuTexture(id, width, height)

# A texture's format: 4 bytes a pixel (r, g, b, a; sRGB-encoded and read as linear; or b, g, r,
# a), half floats (r, g, b, a; or r, g), unsigned floats of 11, 11 and 10 bits, 10 bits each of r,
# g, b and 2 of a, a float, one or two bytes; or blocks of 4x4 pixels compressed (BC1: 8 bytes,
# RGB and a 1-bit alpha; BC3: 16 bytes, RGBA; BC4: 8 bytes, one channel; BC5: 16 bytes, two
# channels; BC7: 16 bytes, RGBA), not drawn into.
pub type TextureFormat:
	Rgba8
	Rgba8Srgb
	Bgra8
	Bgra8Srgb
	Rgba16Float
	Rg16Float
	R11G11B10Float
	Rgb10A2
	R32Float
	R8
	Rg8
	Bc1
	Bc1Srgb
	Bc3
	Bc3Srgb
	Bc4
	Bc5
	Bc7
	Bc7Srgb

	# the RHI's code of the format
	fn code():
		match self:
			Rgba8: core.fmtRgba8
			Rgba8Srgb: core.fmtRgba8Srgb
			Bgra8: core.fmtBgra8
			Bgra8Srgb: core.fmtBgra8Srgb
			Rgba16Float: core.fmtRgba16Float
			Rg16Float: core.fmtRg16Float
			R11G11B10Float: core.fmtR11G11B10Float
			Rgb10A2: core.fmtRgb10A2
			R32Float: core.fmtR32Float
			R8: core.fmtR8
			Rg8: core.fmtRg8
			Bc1: core.fmtBc1
			Bc1Srgb: core.fmtBc1Srgb
			Bc3: core.fmtBc3
			Bc3Srgb: core.fmtBc3Srgb
			Bc4: core.fmtBc4
			Bc5: core.fmtBc5
			Bc7: core.fmtBc7
			Bc7Srgb: core.fmtBc7Srgb

# the bytes a w x h level of a texture of the format holds (rows of pixels, or of blocks)
pub fn levelBytes(format TextureFormat, w i64, h i64) i64:
	core.levelBytes(format.code(), w, h)

# A texture of `layers` layers (read as an array when `array`) of the format, `levels` levels
# each, their bytes written by `write` (given the texture's id), sampled as `sampling` says.
# With one level of pixels (not of blocks) and a sampling that wants mip levels, they are made
# from the first. Its id.
fn makeTexture(
	width i64,
	height i64,
	layers i64,
	format i64,
	levels i64,
	array bool,
	sampling Sampling,
	write fn(i64)
):
	made = levels == 1 and sampling.mipmaps and not core.isBlockFormat(format)
	id = gpu.newTexture(core.TextureDesc(
		width,
		height,
		layers,
		levels = 0 if made else levels,
		format,
		samples = 1,
		array,
		target = false))
	write(id)
	if made:
		gpu.generateMips(id)
	rhi.setSampler(
		gpu,
		id,
		samplerOf(Sampling(..sampling, mipmaps = sampling.mipmaps and (made or levels > 1)))
	)
	id

fn samplerOf(s Sampling):
	core.SamplerDesc(
		smooth = s.smooth,
		mipmaps = 2 if s.mipmaps else 0,
		repeat = s.repeat,
		mirror = s.mirror,
		anisotropy = s.anisotropy,
		compare = false
	)

# the pixels of a texture replaced by an image of its size (a picture drawn on the CPU each frame)
pub fn updateTexture(t GpuTexture, img image.Image):
	if img.width != t.width or img.height != t.height:
		fail("a {t.width}x{t.height} texture needs an image of its size, got {img.width}x{img.height}")
	gpu.writeTexture(t.id, 0, img.cells.bytes())

# a texture from an image file (PNG); stops with the reason when it cannot be read
pub fn loadTexture(path str) GpuTexture:
	image.loadPng(path).newTexture()

# ---------- the frame ----------

# Begins a frame on the screen of w x h pixels: cleared to `clear`, the camera's view of the
# world.
pub fn beginFrame(mut r Renderer, w i64, h i64, clear Vec4, cam Camera):
	r.useScreen()
	r.clearTarget(clear)
	r.beginOverlay(w, h, cam)

# Begins a frame of the batch over what is drawn already on the screen (a scene of meshes).
pub fn beginOverlay(mut r Renderer, w i64, h i64, cam Camera):
	r.useScreen()
	r.drawCalls = 0
	r.quads = 0
	r.viewW = w
	r.viewH = h
	r.setCamera(cam)

# the camera for what is drawn next (what was collected goes out first, under the old one)
pub fn setCamera(mut r Renderer, cam Camera):
	r.flush()
	vw = f32(r.viewW) / cam.zoom
	vh = f32(r.viewH) / cam.zoom
	r.view = Mat4.ortho(cam.x, cam.x + vw, cam.y + vh, cam.y)

# the screen point (window pixels) as a point of the world, under the camera
pub fn screenToWorld(cam Camera, at IVec2) Vec2:
	Vec2(x = cam.x + f32(at.x) / cam.zoom, y = cam.y + f32(at.y) / cam.zoom)

# draws what is collected; the frame ends here
pub fn endFrame(mut r Renderer):
	r.flush()

# the quads collected drawn in one call: blended, without depth or culling, whatever the 3D
# state is
fn flush(mut r Renderer):
	n = r.vertices.len
	if n == 0: return
	if r.arrays:
		r.program.setParams(SpriteParams(projection = r.view, images = r.textures.copy()))
	else:
		r.program.setParams(SpriteParamsOne(projection = r.view, image = r.textures[0]))
	handle, offset = frameData(r.vertices)
	drawQueued()
	r.state.ensurePass()
	streams(handle, offset)
	st = programs[r.program.id]
	gpu.draw(core.DrawCall(
		program = r.program.id,
		layout = r.program.layout,
		state = core.PipelineState(blend = core.blendAlpha, alphaToCoverage = false, lines = false),
		vertexBuffers = streamBuffers,
		vertexOffsets = streamOffsets,
		indexBuffer = gpu.bufferHandle(r.corners.buffer.id),
		count = n / 4 * 6,
		instances = 1,
		textures = st.textures,
		storage = st.storage,
		cull = false,
		depthTest = false, depthWrite = false, depthBias = false))
	r.vertices.clear()
	r.textures.clear()
	r.drawCalls += 1

# ---------- drawing ----------

# a quad of texture `tex`: the screen rectangle x, y, w, h (world pixels), the texture's
# rectangle u0, v0 .. u1, v1 (0..1, the whole texture by default), tinted (white: as it is)
pub fn drawQuad(
	mut r Renderer,
	tex Texture,
	x f32,
	y f32,
	w f32,
	h f32,
	u0 f32 = 0.0,
	v0 f32 = 0.0,
	u1 f32 = 1.0,
	v1 f32 = 1.0,
	tint Vec4 = white
):
	image = r.batchTexture(tex)
	r.vertex(x, y, u0, v0, tint, image)
	r.vertex(x + w, y, u1, v0, tint, image)
	r.vertex(x, y + h, u0, v1, tint, image)
	r.vertex(x + w, y + h, u1, v1, tint, image)
	r.quads += 1

# the corners of a quad's two triangles (its corners top-left, top-right, bottom-left,
# bottom-right; a triangle's third repeated)
quadCorners = [0, 1, 2, 1, 3, 2]

# The batch made ready for a shape of `tex`: a full batch, or one that names as many textures as
# it may and not this one, drawn first. The place of `tex` among the batch's textures.
fn batchTexture(mut r Renderer, tex Texture):
	if r.vertices.len >= maxQuads * 4:
		r.flush()
	n = r.textures.len
	if r.image < n and r.textures[r.image].id == tex.id: return r.image
	for i in 0..n:
		if r.textures[i].id == tex.id:
			r.image = i32(i)
			return r.image
	if n == maxTextures or (n == 1 and not r.arrays):
		r.flush()
	r.textures.push(tex)
	r.image = i32(r.textures.len - 1)
	r.image

# a triangle of texture `tex`: its corners a, b, c (world pixels) and their places in the
# texture (0..1), tinted (white: as it is); a vector shape's fill, a clipped quad
pub fn drawTriangle(
	mut r Renderer,
	tex Texture,
	a Vec2,
	b Vec2,
	c Vec2,
	uvA Vec2,
	uvB Vec2,
	uvC Vec2,
	tint Vec4 = white
):
	image = r.batchTexture(tex)
	r.vertex(a.x, a.y, uvA.x, uvA.y, tint, image)
	r.vertex(b.x, b.y, uvB.x, uvB.y, tint, image)
	r.vertex(c.x, c.y, uvC.x, uvC.y, tint, image)
	r.vertex(c.x, c.y, uvC.x, uvC.y, tint, image)

fn vertex(mut r Renderer, x f32, y f32, u f32, v f32, c Vec4, image i32):
	r.vertices.push(
		SpriteVertex(position = Vec2(x, y), uv = Vec2(x = u, y = v), tint = c, image)
	)

# the whole texture at x, y in its own size
pub fn draw(mut r Renderer, tex Texture, x f32, y f32):
	r.drawQuad(tex, x, y, f32(tex.width), f32(tex.height))

# a region of a texture at x, y, w x h, tinted; flipped mirrors it left to right
pub fn drawRegion(
	mut r Renderer,
	reg Region,
	x f32,
	y f32,
	w f32,
	h f32,
	tint Vec4 = white,
	flipped bool = false
):
	tw = f32(reg.tex.width)
	th = f32(reg.tex.height)
	u0 = f32(reg.x) / tw
	u1 = f32(reg.x + reg.w) / tw
	if flipped:
		u0, u1 = u1, u0
	r.drawQuad(reg.tex, x, y, w, h, u0, f32(reg.y) / th, u1, f32(reg.y + reg.h) / th, tint)

# a filled rectangle
pub fn fillRect(mut r Renderer, x f32, y f32, w f32, h f32, c Vec4):
	r.drawQuad(r.white.texture(), x, y, w, h, tint = c)

# a line of thickness t from (x0, y0) to (x1, y1), as a thin rotated quad
pub fn drawLine(mut r Renderer, x0 f32, y0 f32, x1 f32, y1 f32, t f32, c Vec4):
	d = Vec2(x1 - x0, y1 - y0).normalized()
	nx = -d.y * t * 0.5
	ny = d.x * t * 0.5
	image = r.batchTexture(r.white.texture())
	r.vertex(x0 + nx, y0 + ny, 0.0, 0.0, c, image)
	r.vertex(x1 + nx, y1 + ny, 1.0, 0.0, c, image)
	r.vertex(x0 - nx, y0 - ny, 0.0, 1.0, c, image)
	r.vertex(x1 - nx, y1 - ny, 1.0, 1.0, c, image)
	r.quads += 1

# The window's frame as an image (rows from the top), for a screenshot or a check: the frame
# is ended (shown) to read it back; what follows draws into the next one.
pub fn screenshot(mut r Renderer) image.Image:
	r.flush()
	drawQueued()
	if not frameOpen:
		fail("a screenshot outside a frame")
	pixels = gpu.endFrameCapturing()
	frameOpen = false
	width, height = gpu.screenSize()
	image.fromBytes(width, height, pixels)
