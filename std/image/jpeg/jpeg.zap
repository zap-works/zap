# JPEG, baseline (sequential, Huffman-coded), as Ragnarok's water textures and Flash's bitmaps
# store it: one or three components with any sampling, quantisation tables of 8 or 16 bits and
# restart markers. The blocks are decoded, dequantised and turned back by a separable inverse DCT;
# the chroma planes are spread over the pixels they cover and YCbCr becomes RGB. Progressive files
# are refused. `import image.jpeg`, then `jpeg.decodeJpeg(bytes)`.

import image

type HuffTable:
	lookup {i64: i64}   # (length << 16 | code) -> symbol
	present bool

type JpegComponent:
	id i64
	h i64
	v i64
	quant i64
	dcTable i64
	acTable i64
	pred i64
	plane Grid<f32>   # the decoded samples

type BitReader:
	d ref u8[]
	at i64
	bits i64
	count i64

	fn bit():
		if count == 0:
			b = 0
			if at < d.len:
				b = d[at]
				if b == 255:
					next = i64(d[at + 1]) if at + 1 < d.len else 0
					if next == 0:
						at += 2
					else:
						b = 0   # a marker: zeros from here on
				else:
					at += 1
			bits = b
			count = 8
		count -= 1
		bits.bits(count, 1)

	mut fn take(n i64):
		v = 0
		loop n:
			v = (v << 1) | bit()
		v

	# past a restart marker: the bits left in the byte dropped, the marker skipped
	fn restart():
		count = 0
		while at + 1 < d.len and not (d[at] == 255 and d[at + 1] >= 0xD0 and d[at + 1] <= 0xD7):
			at += 1
		at += 2

zigzag = [
	0,
	1,
	8,
	16,
	9,
	2,
	3,
	10,
	17,
	24,
	32,
	25,
	18,
	11,
	4,
	5,
	12,
	19,
	26,
	33,
	40,
	48,
	41,
	34,
	27,
	20,
	13,
	6,
	7,
	14,
	21,
	28,
	35,
	42,
	49,
	56,
	57,
	50,
	43,
	36,
	29,
	22, 15, 23, 30, 37, 44, 51, 58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63]

fn decodeSymbol(mut r BitReader, t HuffTable):
	code = 0
	for length in 1..17:
		code = (code << 1) | r.bit()
		if t.lookup.get((length << 16) | code) is s: return s
	0

# a coefficient of `n` bits as JPEG codes it (the lower half negative)
fn extend(v i64, n i64):
	0 if n == 0 else v - (1 << n) + 1 if v < (1 << (n - 1)) else v

# cos((2x + 1) u pi / 16) * c(u) / 2, by x * 8 + u
fn idctTable():
	t = Grid<f32>(8, 8)
	for x in 0..8:
		for u in 0..8:
			cu = 0.7071067811865476 if u == 0 else 1.0
			t[u, x] = f32(((2.0 * x + 1.0) * u * pi / 16.0).cos()) * f32(cu) * 0.5
	t

# the image a baseline JPEG file holds, or why it cannot be read
pub fn decodeJpeg(d u8[]) image.Image ? str:
	if d.len < 4 or d[0] != 255 or d[1] != 0xD8: return "not a JPEG file"
	quants f32[,] = [[], [], [], []]
	tables = []
	loop 8:
		tables.push(HuffTable(lookup = {}, present = false))
	comps = []
	width = 0
	height = 0
	interval = 0
	at = 2
	while at + 4 <= d.len:
		if d[at] != 255:
			at += 1
			continue
		marker = i64(d[at + 1])
		if marker == 0xD8 or marker == 0xFF or (marker >= 0xD0 and marker <= 0xD7):
			at += 1 if marker == 0xFF else 2
			continue
		length = i64(d.u16be(at + 2))
		body = at + 4
		end = at + 2 + length
		if end > d.len: return "a JPEG segment runs past the end"
		if marker == 0xDB:
			decodeJpegQuant(d, body, end, quants)
		elif marker == 0xC0 or marker == 0xC1:
			width, height = decodeJpegFrame(d, body, comps)
		elif marker >= 0xC2 and marker <= 0xCF and marker != 0xC4 and marker != 0xC8 and
			marker != 0xCC:
			return "a progressive or lossless JPEG"
		elif marker == 0xC4:
			decodeJpegHuffman(d, body, end, tables)
		elif marker == 0xDD:
			interval = d.u16be(body)
		elif marker == 0xDA:
			if width == 0 or comps.isEmpty: return "a JPEG scan before its frame"
			decodeJpegScan(d, body, end, width, height, comps, quants, tables, interval)
			break
		elif marker == 0xD9:
			break
		at = end
	if width == 0 or comps.isEmpty or comps[0].plane.cells.isEmpty:
		return "a JPEG without a frame or a scan"
	decodeJpegPixels(width, height, comps)

fn decodeJpegQuant(
	d u8[],
	body i64,
	end i64,
	mut quants f32[,]
):
	p = body
	while p < end:
		precision = i64(d[p]) >> 4
		id = i64(d[p]) & 3
		p += 1
		q f32[] = zeros(64)
		for k in 0..64:
			v = i64(d[p]) if precision == 0 else d.u16be(p)
			p += 1 if precision == 0 else 2
			q[zigzag[k]] = f32(v)
		quants[id] = q

fn decodeJpegFrame(
	d u8[],
	body i64,
	mut comps JpegComponent[]
) (i64, i64):
	height = d.u16be(body + 1)
	width = d.u16be(body + 3)
	n = i64(d[body + 5])
	for k in 0..n:
		p = body + 6 + k * 3
		comps.push(JpegComponent(
			id = d[p],
			h = i64(d[p + 1]) >> 4,
			v = i64(d[p + 1]) & 15,
			quant = i64(d[p + 2]) & 3,
			dcTable = 0,
			acTable = 4,
			pred = 0, plane = Grid(0, 0)))
	(width, height)

fn decodeJpegHuffman(
	d u8[],
	body i64,
	end i64,
	mut tables HuffTable[]
):
	p = body
	while p < end:
		class = i64(d[p]) >> 4
		id = i64(d[p]) & 3
		counts i64[] = []
		for k in 0..16:
			counts.push(d[p + 1 + k])
		p += 17
		t = HuffTable(lookup = {}, present = true)
		code = 0
		for length in 1..17:
			loop counts[length - 1]:
				t.lookup[(length << 16) | code] = d[p]
				p += 1
				code += 1
			code <<= 1
		tables[class * 4 + id] = t

fn decodeJpegScan(
	d u8[],
	body i64,
	end i64,
	width i64,
	height i64,
	mut comps JpegComponent[],
	quants f32[,],
	tables HuffTable[],
	interval i64
):
	n = i64(d[body])
	order = []
	for k in 0..n:
		id = i64(d[body + 1 + k * 2])
		sel = i64(d[body + 2 + k * 2])
		for c, mut comp in comps:
			if comp.id == id:
				comp.dcTable = sel >> 4
				comp.acTable = 4 + (sel & 15)
				order.push(c)
	decodeScan(d, end, width, height, comps, order, quants, tables, interval)

fn decodeJpegPixels(
	width i64,
	height i64,
	comps JpegComponent[]
):
	hmax = comps.map(.h).max() ?? 1
	vmax = comps.map(.v).max() ?? 1
	out = image.Image(width, height, fill = image.Rgba8(0, 0, 0, 255))
	for y in 0..out.height:
		for x in 0..out.width:
			yy = comps[0].sample(x, y, hmax, vmax)
			if comps.len >= 3:
				cb = comps[1].sample(x, y, hmax, vmax) - 128.0
				cr = comps[2].sample(x, y, hmax, vmax) - 128.0
				out[x, y] = image.Rgba8(
					channel(yy + 1.402 * cr),
					channel(yy - 0.344136 * cb - 0.714136 * cr),
					channel(yy + 1.772 * cb),
					255
				)
			else:
				gray = channel(yy)
				out[x, y] = image.Rgba8(gray, gray, gray, 255)
	out

fn sample(c JpegComponent, x i64, y i64, hmax i64, vmax i64):
	c.plane[x * c.h / hmax, y * c.v / vmax]

fn channel(v f32) u8:
	u8(i64(v.round().clamp(0.0, 255.0)))

# the entropy-coded blocks of one interleaved scan, decoded into each component's plane
fn decodeScan(
	d u8[],
	start i64,
	width i64,
	height i64,
	mut comps JpegComponent[],
	order i64[],
	quants f32[,],
	tables HuffTable[],
	interval i64):
		hmax = comps.map(.h).max() ?? 1
		vmax = comps.map(.v).max() ?? 1
		mcusX = (width + 8 * hmax - 1) / (8 * hmax)
		mcusY = (height + 8 * vmax - 1) / (8 * vmax)
		for mut comp in comps:
			comp.plane = Grid<f32>(mcusX * comp.h * 8, mcusY * comp.v * 8)
		table = idctTable()
		r = BitReader(d, at = start, bits = 0, count = 0)
		coef = Grid<f32>(8, 8)
		tmp = Grid<f32>(8, 8)
		done = 0
		for my in 0..mcusY:
			for mx in 0..mcusX:
				if interval > 0 and done > 0 and done % interval == 0:
					r.restart()
					for mut comp in comps:
						comp.pred = 0
				done += 1
				for c in order:
					for by in 0..comps[c].v:
						for bx in 0..comps[c].h:
							for k in 0..64:
								coef.cells[k] = 0.0
							q = quants[comps[c].quant]
							s = r.decodeSymbol(tables[comps[c].dcTable])
							comps[c].pred += extend(r.take(s), s)
							coef.cells[0] = f32(comps[c].pred) * (q[0] if q.len == 64 else 1.0)
							k = 1
							while k < 64:
								rs = r.decodeSymbol(tables[comps[c].acTable])
								run = rs >> 4
								size = rs & 15
								if size == 0:
									if run != 15: break
									k += 16
									continue
								k += run
								if k > 63: break
								z = zigzag[k]
								coef.cells[z] = f32(extend(r.take(size), size)) *
									(q[z] if q.len == 64 else 1.0)
								k += 1
							# the inverse DCT: rows, then columns
							for y in 0..8:
								for x in 0..8:
									sum = 0.0
									for u in 0..8:
										sum += table[u, x] * coef[u, y]
									tmp[x, y] = sum
							ox = (mx * comps[c].h + bx) * 8
							oy = (my * comps[c].v + by) * 8
							for x in 0..8:
								for y in 0..8:
									sum = 0.0
									for v in 0..8:
										sum += table[v, y] * tmp[x, v]
									comps[c].plane[ox + x, oy + y] = sum + 128.0
