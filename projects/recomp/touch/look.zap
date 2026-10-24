# The picture's look on a phone, as a graphics mod changes it: the colours more vivid, the
# picture enlarged with its edges smoothed (image.smoothInto) or kept sharp, and lines like a CRT's
# across it (each pixel row's last frame row darkened). The program chooses them (its menu); the
# zoom is the screen's, up to 4.

import image

pub type Look:
	smooth bool = true
	scanlines bool = false
	vivid bool = true

vividGain = 80   # the saturation added, in 256ths of a colour's distance from its grey
lineShade = 176   # a CRT line's brightness, in 256ths

# The picture into the frame at (margin, 0), k times larger, as the look draws it; the margins black.
fn drawPicture(mut o Overlay, picture image.Image, k i64, margin i64):
	shown = picture.vivid() if o.look.vivid else picture
	black = image.Rgba8(0, 0, 0, 255)
	o.frame.fillRect(0, 0, margin, o.frame.height, black)
	right = margin + picture.width * k
	o.frame.fillRect(right, 0, o.frame.width - right, o.frame.height, black)
	if o.look.smooth:
		o.frame.smoothInto(shown, k, margin, 0)
	else:
		o.scalePicture(shown, k, margin)
	if o.look.scanlines and k > 1: o.shadeLines(k, margin, right)

# each pixel's colour moved away from its grey by vividGain
fn vivid(picture image.Image):
	out = picture.copy()
	for i in 0..out.cells.len:
		p = out.cells[i]
		r = i64(p.r)
		g = i64(p.g)
		b = i64(p.b)
		grey = (r * 77 + g * 150 + b * 29) >> 8
		out.cells[i] = image.Rgba8(
			saturated(r, grey),
			saturated(g, grey),
			saturated(b, grey),
			255
		)
	out

fn saturated(c i64, grey i64) u8:
	(c + (c - grey) * vividGain / 256).clamp(0, 255)

# the last frame row of each pixel row darkened to lineShade, between the margins
fn shadeLines(mut o Overlay, k i64, left i64, right i64):
	fw = o.frame.width
	for y in (k - 1)..o.frame.height step k:
		for x in left..right:
			p = o.frame.cells[y * fw + x]
			o.frame.cells[y * fw + x] = image.Rgba8(
				(i64(p.r) * lineShade) >> 8,
				(i64(p.g) * lineShade) >> 8,
				(i64(p.b) * lineShade) >> 8,
				255
			)
