# Textures of other formats than 8-bit RGBA on the backend the environment picks: a BC1 texture of
# red blocks, a BC3 one of green blocks half transparent, a BC7 one of blue, a BC4 one of a red of
# 128, a BC5 one of 128 and 64 in red and green, an sRGB one of a middle gray (128, read as linear
# 0.216), each with two levels written ahead, drawn by the sprite batch into a frame read back.
# Each must show the color it holds: red; green blended at half over black; blue; (128, 0, 0);
# (128, 64, 0); a gray of 55. Where the GPU reads ASTC (Android's; not Direct3D 12, nor most
# desktops), a picture of gradients and shapes encoded by std's ASTC encoder as 4x4 and 6x6
# blocks, linear and sRGB, drawn in a second row, each texel as the CPU decodes it (sRGB's read
# as linear).
#   zap run projects/examples/compressed/main.zap          (from the repository's root; ZAP_RUN=gpu=d3d12 for Direct3D 12)

import engine
import image
import image.astc

size = 64

# a level of w x h of the same block (or pixel) repeated
fn level(format engine.TextureFormat, w i64, h i64, block u8[]):
	out = []
	n = format.levelBytes(w, h) / block.len
	loop n:
		out.extend(block)
	out

# the color read back at the center of the square drawn at x
fn colorAt(img image.Image, x i64) (i64, i64, i64):
	p = img[x + size / 2, size / 2]
	(p.r, p.g, p.b)

fn near(a (i64, i64, i64), b (i64, i64, i64)):
	ar, ag, ab = a
	br, bg, bb = b
	(ar - br).abs() <= 2 and (ag - bg).abs() <= 2 and (ab - bb).abs() <= 2

# a texel of an sRGB texture as a shader reads it: linear, 0..255
fn linear(v u8):
	c = f64(v) / 255.0
	l = c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055).pow(2.4)
	i64((l * 255.0).round())

# a picture of gradients, a disc and stripes, opaque, of 48x48 (blocks of 4 and 6 across)
fn picture():
	img = image.Image(48, 48, fill = image.Rgba8(0, 0, 0, 255))
	for y in 0..48:
		for x in 0..48:
			inside = (x - 30) * (x - 30) + (y - 18) * (y - 18) < 120
			stripe = (x / 3 + y / 5) % 4 == 0
			r = 230 if inside else x * 5
			g = 40 if inside else (200 if stripe and y > 30 else y * 5)
			img[x, y] = image.Rgba8(u8(r), u8(g), u8(255 - x * 2 - y * 2), 255)
	img

# how many pixels of the square drawn at x, y differ from the texels by more than 3 a channel
fn wrongTexels(shot image.Image, x i64, y i64, texels image.Image, srgb bool):
	wrong = 0
	for ty in 0..texels.height:
		for tx in 0..texels.width:
			p = shot[x + tx, y + ty]
			t = texels[tx, ty]
			want = [linear(t.r), linear(t.g), linear(t.b)] if srgb else [i64(t.r), i64(t.g), i64(t.b)]
			got = [i64(p.r), i64(p.g), i64(p.b)]
			if (0..3).any((got[it] - want[it]).abs() > 3): wrong += 1
	wrong

mut frames = engine.newFrames()
mut win = engine.openWindow("Texture formats", size * 6, size * 2)
mut r = engine.newRenderer()
# BC1: color0 red (RGB565 0xF800), color1 black, every index 0
red u8[] = [0x00, 0xF8, 0x00, 0x00, 0, 0, 0, 0]
# BC3: alpha0 128, alpha1 0, every alpha index 0; then color0 green (0x07E0), color1 black, every index 0
green u8[] = [128, 0, 0, 0, 0, 0, 0, 0, 0xE0, 0x07, 0x00, 0x00, 0, 0, 0, 0]
# BC7 mode 6: every endpoint (1, 1, 255, 255) by its p-bit, every index 0
blue u8[] = [0x40, 0, 0, 0, 0xF8, 0xFF, 0xFF, 0xFF, 0x01, 0, 0, 0, 0, 0, 0, 0]
# BC4: red0 128, red1 0, every index 0
one u8[] = [128, 0, 0, 0, 0, 0, 0, 0]
# BC5: red0 128 then green0 64, every index 0
two u8[] = [128, 0, 0, 0, 0, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0]
gray u8[] = [128, 128, 128, 255]
sampling = engine.Sampling(
	smooth = false,
	mipmaps = true,
	repeat = false,
	mirror = 0,
	anisotropy = false
)
formats engine.TextureFormat[] = [.Bc1, .Bc3, .Bc7, .Bc4, .Bc5, .Rgba8Srgb]
blocks = [red, green, blue, one, two, gray]
textures = (0..6).map(i:
	engine.newTextureOfFormat(
		size,
		size,
		formats[i].level(size, size, blocks[i]),
		sampling,
		format = formats[i],
		mips = [formats[i].level(size / 2, size / 2, blocks[i])]
	)
)
astc engine.TextureFormat[] = [.Astc4x4, .Astc4x4Srgb, .Astc6x6, .Astc6x6Srgb]
source = picture()
encoded = (0..4).map(source.encodeAstc(4 if it < 2 else 6, 4 if it < 2 else 6, it % 2 == 1))
astcTextures = (0..4).map(i:
	engine.newTextureOfFormat(48, 48, encoded[i].blocks, sampling, format = astc[i])
) if engine.astcTextures() else []
if not win.nextFrame(frames):
	fail("the window closed")
r.beginFrame(win.width, win.height, Vec4(0.0, 0.0, 0.0, 1.0), engine.Camera())
for i in 0..6:
	r.draw(textures[i].texture(), f32(i * size), 0.0)
for i, t in astcTextures:
	r.draw(t.texture(), f32(i * size), f32(size))
img = r.screenshot()
got = [0, 1, 2, 3, 4, 5].map(img.colorAt(it * size))
wanted = [(255, 0, 0), (0, 128, 0), (0, 0, 255), (128, 0, 0), (128, 64, 0), (55, 55, 55)]
mut right = 0
for i in 0..6:
	if near(got[i], wanted[i]):
		right += 1
print("{engine.backendName()}: BC1, BC3, BC7, BC4, BC5 and sRGB textures read right: {right} of 6 {got}")
if right != 6:
	exit(1)
if astcTextures.isEmpty:
	print("{engine.backendName()}: no ASTC textures on this GPU")
else:
	wrong = (0..4).map(img.wrongTexels(it * size, size, encoded[it].decode(it % 2 == 1), it % 2 == 1))
	print("{engine.backendName()}: ASTC 4x4, 4x4 sRGB, 6x6 and 6x6 sRGB texels read wrong: {wrong}")
	if wrong.any(it != 0):
		exit(1)
