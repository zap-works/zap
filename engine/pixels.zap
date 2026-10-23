# A picture of pixels shown in a window at an integer zoom, centred on black: what a console's
# frame needs of the engine (the SNES of projects/recomp/snes, the GBA of projects/firered), and
# its pixels converted from the 15-bit BGR such hardware keeps.

import image

pub type PixelWindow:
	window Window
	frames Frames
	renderer Renderer
	texture GpuTexture
	width i64   # the picture's
	height i64

# a window for a picture of width x height, opened `zoom` times that size, `first` its first picture
pub fn openPixelWindow(title str, width i64, height i64, zoom i64, first image.Image) PixelWindow:
	PixelWindow(
		window = openWindow(title, width * zoom, height * zoom),
		frames = newFrames(),
		renderer = newRenderer(),
		texture = first.newTexture(),
		width,
		height
	)

# Shows the picture (of any size: a frame with controls beside it is wider) centred at the zoom the
# window holds (pictureZoom); false once the window was closed.
pub fn show(mut w PixelWindow, picture image.Image) bool:
	if not w.window.nextFrame(w.frames, escEnds = false): return false
	if picture.width != w.width or picture.height != w.height:
		w.texture = picture.newTexture()
		w.width = picture.width
		w.height = picture.height
	else:
		w.texture.updateTexture(picture)
	ww = w.window.width
	wh = w.window.height
	zoom = pictureZoom(ww, wh, w.width, w.height)
	shownWidth = w.width * zoom
	shownHeight = w.height * zoom
	w.renderer.beginFrame(ww, wh, Vec4(0.0, 0.0, 0.0, 1.0), Camera())
	w.renderer.drawQuad(
		w.texture.texture(),
		f32(((ww - shownWidth) / 2.0).floor()),
		f32(((wh - shownHeight) / 2.0).floor()),
		f32(shownWidth),
		f32(shownHeight)
	)
	w.renderer.showFrame(w.window, w.frames)
	true

# the picture's zoom in a window of ww x wh: the largest whole one that fits, 1 at least
fn pictureZoom(ww i64, wh i64, width i64, height i64) f64:
	(ww / width).min(wh / height).max(1)

# the rate the pictures come at, for a screen that can match it (an app's; a window of Windows
# shows at its own)
pub fn setFrameRate(mut w PixelWindow, perSecond f64):
	_ = perSecond

# the size of what the window shows, in the screen's pixels
pub fn screenSize(w PixelWindow) IVec2:
	IVec2(i32(w.window.width), i32(w.window.height))

# the colours (15-bit BGR, 5 bits a channel, rows from the top) as an RGBA image
pub fn bgr555Image(colors u16[], width i64, height i64) image.Image:
	out = fill(width * height * 4, u8(0))
	for i in 0..colors.len:
		c = i64(colors[i])
		out[4 * i] = channel8(c & 0x1F)
		out[4 * i + 1] = channel8((c >> 5) & 0x1F)
		out[4 * i + 2] = channel8((c >> 10) & 0x1F)
		out[4 * i + 3] = 255
	image.fromBytes(width, height, out)

# a 5-bit channel as 8 bits, its top bits repeated below (as the hardware's screen shows it)
fn channel8(v i64) u8:
	u8((v << 3) | (v >> 2))
