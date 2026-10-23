# The controls painted once and laid over each frame after: painting blends a pixel toward greys
# (paint.zap), so what it does to any pixel is a share kept and a grey added, found by painting
# the controls over black and over white. Painted again when what they show changes (the frame's
# size, the pad shown or hidden, a button held or let go).

import image

type Ink:
	key str = ""
	at i64[] = []     # the frame's pixels the controls touch
	keep i64[] = []   # how much of each stays, in 256ths
	add i64[] = []    # and the grey added to it

fn layInk(mut o Overlay, cs Control[]):
	key = o.controlsKey(cs)
	if key != o.ink.key: o.ink = o.paintInk(cs, key)
	for j in 0..o.ink.at.len:
		i = o.ink.at[j]
		p = o.frame.cells[i]
		keep = o.ink.keep[j]
		add = o.ink.add[j]
		o.frame.cells[i] = image.Rgba8(
			u8(((i64(p.r) * keep >> 8) + add).min(255)),
			u8(((i64(p.g) * keep >> 8) + add).min(255)),
			u8(((i64(p.b) * keep >> 8) + add).min(255)),
			255
		)

fn paintInk(o Overlay, cs Control[], key str) Ink:
	w = o.frame.width
	h = o.frame.height
	black = image.Image(w, h, fill = image.Rgba8(0, 0, 0, 255))
	white = image.Image(w, h, fill = image.Rgba8(255, 255, 255, 255))
	o.paintControls(black, cs)
	o.paintControls(white, cs)
	ink = Ink(key = key.copy())
	for i in 0..black.cells.len:
		low = i64(black.cells[i].r)
		high = i64(white.cells[i].r)
		if low == 0 and high == 255: continue
		ink.at.push(i)
		ink.keep.push(((high - low) * 256 + 127) / 255)
		ink.add.push(low)
	ink
