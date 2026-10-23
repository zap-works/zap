# How a GPU tensor stores its numbers past f32: halves two to a word, and blocks of 32 integers
# sharing a scale. The conversions of a number are the CPU's and the GPU's both (the kernels read
# a stored number with the runtime's halfValue and bfloatValue).

import gpu

blockSize = 32

# the bf16 nearest x (ties to even), as its 16 bits
pub fn bfloatBits(x f32) u32:
	b = x.toBits()
	if (b & 0x7F80_0000) == 0x7F80_0000 and (b & 0x7F_FFFF) != 0: return 0x7FC0
	wide = u64(b) + 0x7FFF + u64((b >> 16) & 1)
	u32(wide >> 16) & 0xFFFF

# the number a bf16's 16 bits hold
pub fn bfloatValue(h u32) f32:
	f32.fromBits(h << 16)

# halves two to a word, the first in the low half
fn packedHalves(shape i64[], halves u32[], format Format):
	words = fill((halves.len + 1) / 2, u32(0))
	for i, h in halves:
		words[i / 2] |= h << (16 * u32(i % 2))
	b = gpu.newBuffer(words.len * 4)
	b.upload(words)
	Tensor(shape = shape.copy(), buffer = b, format)

fn unpackHalves(words u32[], n i64, format Format):
	(0..n).map(i:
		h = (words[i / 2] >> (16 * u32(i % 2))) & 0xFFFF
		halfValue(h) if format == .F16 else bfloatValue(h)
	)

# GGUF's Q8_0 and Q4_0, made of f32s: a block's scale and its integers' bytes (Q4: the first 16
# numbers in the low nibbles, the next 16 in the high ones)
fn quantized(shape i64[], values f32[], format Format):
	if values.len % blockSize != 0:
		fail("tensor: {format} stores blocks of {blockSize} numbers, given {values.len}")
	blocks = values.len / blockSize
	scales = []
	bytes = []
	for k in 0..blocks:
		block = values[k * blockSize..(k + 1) * blockSize]
		if format == .Q8:
			most f32 = 0.0
			for x in block:
				most = most.max(x.abs())
			d = most / 127.0
			inverse = 1.0 / d if d != 0.0 else 0.0
			scales.push(d)
			for x in block:
				bytes.push(u8.wrap(i64((x * inverse).round())))
		else:
			most f32 = 0.0
			for x in block:
				if x.abs() > most.abs():
					most = x
			d = most / -8.0
			inverse = 1.0 / d if d != 0.0 else 0.0
			scales.push(d)
			for j in 0..16:
				lo = i64(block[j] * inverse + 8.5).clamp(0, 15)
				hi = i64(block[j + 16] * inverse + 8.5).clamp(0, 15)
				bytes.push(u8(lo | hi << 4))
	quantizedFrom(shape, format, scales, bytes)

# A GPU tensor of blocks already quantized (read from a GGUF file): each block's scale and its
# bytes, 32 for Q8, 16 for Q4.
pub fn quantizedFrom(shape i64[], format Format, scales f32[], bytes u8[]) Tensor:
	per = 32 if format == .Q8 else 16
	if scales.len * blockSize != shapeCount(shape) or bytes.len != scales.len * per:
		fail("tensor: {scales.len} blocks of {format} for a {shapeText(shape)} tensor")
	b = gpu.newBuffer(bytes.len)
	b.upload(bytes)
	s = gpu.newBuffer(scales.len * 4)
	s.upload(scales)
	Tensor(shape = shape.copy(), buffer = b, scales = s, format)

fn dequantized(t Tensor):
	blocks = t.count() / blockSize
	per = 32 if t.format == .Q8 else 16
	bytes = fill(blocks * per, u8(0))
	gpu.download(t.storage(), bytes)
	scales = fill(blocks, f32(0))
	gpu.download(t.scaleStorage(), scales)
	out f32[] = []
	out.reserve(t.count())
	for k in 0..blocks:
		d = scales[k]
		if t.format == .Q8:
			for j in 0..32:
				q = i64(bytes[k * 32 + j])
				out.push(f32(q - 256 if q >= 128 else q) * d)
		else:
			for j in 0..32:
				q = i64(bytes[k * 16 + j % 16])
				nibble = q & 15 if j < 16 else q >> 4
				out.push(f32(nibble - 8) * d)
	out

# The numbers as a layer of Q8 or Q4 weights reads them on the GPU (llama.cpp's way): each block
# of 32 quantized as Q8_0 (its largest magnitude over 127 the scale, kept as an f16, each number
# over it rounded) and given back. A CPU tensor's, to check the GPU's products by.
pub fn blockQuantized(tensor Tensor) Tensor:
	out = tensor.values.copy()
	for b in 0..tensor.values.len / blockSize:
		most f32 = 0.0
		for j in 0..blockSize:
			most = most.max(tensor.values[b * blockSize + j].abs())
		d = most / 127.0
		inverse = 1.0 / d if d != 0.0 else 0.0
		kept = halfValue(halfBits(d))
		for j in 0..blockSize:
			out[b * blockSize + j] = (tensor.values[b * blockSize + j] * inverse).round() * kept
	Tensor(shape = tensor.shape.copy(), values = out)
