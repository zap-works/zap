# Moving textures (moving_texture.c): surfaces the game's code makes every frame instead of a
# display list. A water quad is four corners at the water's height whose texture turns about
# its middle (`rotSpeed` a frame, its texture repeating `scale` times across); a list of
# triangles (a waterfall) has its texture slide along s (`speed` a frame, in 10.5 units).

pub type MovQuad:
	rotSpeed i64
	scale i64
	clockwise bool
	alpha i64
	xs i64[]
	zs i64[]

pub type MovTris:
	speed i64
	vertices i64[]   # x, y, z, s, t each (s and t: whole repeats of the texture)
	triangles i64[]   # three vertex indices each

# the quads of a list at `at`: a count, then each quad (rot, speed, scale, four corners, its
# turn, its alpha, its texture)
pub fn readMovQuads(s Segments, at i64) MovQuad[]:
	out = []
	n = s.s16At(at)
	for i in 0..n:
		q = at + 2 + i * 28
		xs = []
		zs = []
		for k in 0..4:
			xs.push(s.s16At(q + 6 + k * 4))
			zs.push(s.s16At(q + 8 + k * 4))
		out.push(
			MovQuad(
				rotSpeed = s.s16At(q + 2),
				scale = s.s16At(q + 4),
				clockwise = s.s16At(q + 22) == 0,
				alpha = s.s16At(q + 24),
				xs,
				zs
			)
		)
	out

# the `count` vertices of a triangle list at `at` (its speed first) and its triangles, read
# from the display list at `dl` (one G_TRI1 a triangle)
pub fn readMovTris(s Segments, at i64, count i64, dl i64) MovTris:
	vertices = (0..count * 5).map(s.s16At(at + 2 + it * 2))
	triangles = []
	c = dl
	while s.u8At(c) == 0xBF:
		w1 = s.u32At(c + 4)
		triangles.push(w1.bits(16, 8) / 10)
		triangles.push(w1.bits(8, 8) / 10)
		triangles.push((w1 & 0xFF) / 10)
		c += 8
	MovTris(speed = s.s16At(at), vertices, triangles)

# a quad's angle at `frames` frames after the level began (a 16-bit angle, as the game keeps it;
# it first turns on the area's second frame)
fn quadAngle(q MovQuad, frames i64):
	((q.rotSpeed * (frames - 1).max(0)) % 0x1_0000 + 0x1_0000) % 0x1_0000

fn sinAt(a i64):
	f32((a * pi / 32768.0).sin())

fn cosAt(a i64):
	f32((a * pi / 32768.0).cos())

# The quad's two triangles (corners 0 1 2, 0 2 3) at height y, `frames` frames after the level
# began, as vertices for the engine (vertexFloats each): white, at the quad's alpha, its texture
# turned (coordinates as f3d.zap makes them: texels / 32, half a texel on for smoothing).
pub fn quadVertices(q MovQuad, y f32, frames i64, mut out f32[]):
	rot = q.quadAngle(frames)
	offsets = [0, 16_384, -32_768, -16_384] if q.clockwise else [0, -16_384, -32_768, 16_384]
	reach = 32.0 * (32.0 * f32(q.scale) - 1.0)
	for k in [0, 1, 2, 0, 2, 3]:
		a = rot + offsets[k]
		s = i64(i16.wrap(i64(reach * sinAt(a))))
		t = i64(i16.wrap(i64(reach * cosAt(a))))
		out.extend(
			[
				f32(q.xs[k]),
				y,
				f32(q.zs[k]),
				1.0,
				1.0,
				1.0,
				(f32(s) / 32.0 + 0.5) / 32.0,
				(f32(t) / 32.0 + 0.5) / 32.0,
				f32(q.alpha) / 255.0,
				0.0
			]
		)

# the triangle list `frames` frames after the level began: its texture slid along s
pub fn trisVertices(m MovTris, alpha i64, frames i64, mut out f32[]):
	# the slide kept as the game keeps it: one step a frame from the area's second, back by 1024 at 1024
	base = 0
	if m.speed != 0:
		base = (m.speed * (frames - 1).max(0)) % 1024
	for i in m.triangles:
		k = i * 5
		s = i64(i16.wrap(base if i == 0 else base + m.vertices[k + 3] * 1024))
		t = i64(i16.wrap(0 if i == 0 else m.vertices[k + 4] * 1024))
		for v in [
			f32(m.vertices[k]),
			f32(m.vertices[k + 1]),
			f32(m.vertices[k + 2]),
			1.0,
			1.0,
			1.0,
			(f32(s) / 32.0 + 0.5) / 32.0,
			(f32(t) / 32.0 + 0.5) / 32.0,
			f32(alpha) / 255.0, 0.0]:
				out.push(v)
