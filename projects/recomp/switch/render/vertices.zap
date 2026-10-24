# A draw's vertices as a renderer feeds them to a translated vertex stage: the vertex numbers it
# draws (its index buffer's or inline indices, else first to first + count), and each attribute's
# value for a vertex as a Vec4 (the components it lacks 0, w 1). Sizes and types are yuzu's
# (maxwell_3d.h, VertexAttribute::Size and Type).

import recomp.switch.maxwell

typeSnorm = 1
typeUnorm = 2
typeSint = 3
typeUint = 4
typeUscaled = 5
typeSscaled = 6
typeFloat = 7

# a size's components: their bits each (a packed size lists its own)
# long: a table of the sizes
fn componentBits(size i64) i64[]:
	match size:
		0x01: [32, 32, 32, 32]
		0x02: [32, 32, 32]
		0x03: [16, 16, 16, 16]
		0x04: [32, 32]
		0x05: [16, 16, 16]
		0x0A: [8, 8, 8, 8]
		0x0F: [16, 16]
		0x12: [32]
		0x13: [8, 8, 8]
		0x18: [8, 8]
		0x1B: [16]
		0x1D: [8]
		0x30: [10, 10, 10, 2]
		0x32: [8, 8]
		0x33: [8, 8, 8, 8]
		0x34: [8]
		_: []

# an attribute's bytes for one vertex
pub fn attributeBytes(size i64) i64:
	if size == 0x31: return 4
	componentBits(size).sum() / 8

# one component of `bits` read as the attribute's type
fn component(raw i64, bits i64, kind i64):
	top = 1 << (bits - 1)
	signed = raw - (top << 1) if raw >= top else raw
	match kind:
		1: (f32(signed) / f32(top - 1)).max(-1.0)
		2: f32(raw) / f32((top << 1) - 1)
		3, 6: f32(signed)
		7:
			if bits == 32: return f32.fromBits(u32(raw))
			if bits == 16: return halfValue(u32(raw))
			f32(raw)
		_: f32(raw)

# the 11- and 10-bit unsigned floats of B10G11R11 as f32 (by the half float of the same exponent)
fn smallFloat(raw i64, mantissa i64):
	halfValue(u32(raw << (10 - mantissa)))

# `count` bytes at `at` as a little-endian number
fn bytesAt(b u8[], at i64, count i64):
	v = 0
	for i in 0..count:
		v |= i64(b[at + i]) << (8 * i)
	v

# The attribute's value at `at` of the bytes, as a Vec4.
pub fn attributeValue(a maxwell.VertexAttribute, b u8[], at i64) Vec4:
	if a.size == 0x31:
		v = i64(b.u32le(at))
		return Vec4(
			smallFloat(v & 0x7FF, 6),
			smallFloat((v >> 11) & 0x7FF, 6),
			smallFloat(v >> 22, 5),
			1.0
		)
	bits = componentBits(a.size)
	packed = bits.any(it % 8 != 0)
	word = i64(b.u32le(at)) if packed else 0
	out f32[] = [0.0, 0.0, 0.0, 1.0]
	shift = 0
	for k, n in bits:
		raw = (word >> shift) & ((1 << n) - 1) if packed else bytesAt(b, at + shift / 8, n / 8)
		out[k] = component(raw, n, a.kind)
		shift += n
	if a.bgra: out = [out[2], out[1], out[0], out[3]]
	Vec4(out[0], out[1], out[2], out[3])

# The vertex numbers a draw reads, in order: from its inline indices, its index buffer's bytes
# (`indices`, from the buffer's address), or first to first + count.
pub fn vertexNumbers(d maxwell.DrawCall, indices u8[]) i64[]:
	if not d.inlineIndices.isEmpty: return d.inlineIndices.map(it + d.baseVertex)
	if not d.indexed: return (d.first..d.first + d.count).map(it)
	width = [1, 2, 4][d.index.format.clamp(0, 2)]
	out = []
	for k in d.first..d.first + d.count:
		at = k * width
		if at + width > indices.len: break
		out.push(bytesAt(indices, at, width) + d.baseVertex)
	out
