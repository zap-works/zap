# The morphs of a head that move it as the game moves it while a line is said and between lines: a
# lip track's targets (skyrim.lipTarget: the phonemes, then the blinks, brows and squints) are
# morphs of the head parts' TRI files, each moving some of a shape's vertices. A shape is matched
# to its head part by name (the baked FaceGen head's shapes carry their head parts' editor ids)
# and to its TRI by vertex count; the deltas are kept sparse in the model's space, the vertex
# numbers those of the body's vertex buffer.

import engine.gltf
import skyrim
import skyrim.esm
import skyrim.nif

# a delta shorter than this moves nothing
tinyDelta f32 = 1.0e-4

# one lip target's morph of a shape: the vertices it moves and their deltas at full weight
pub type LipMorph:
	target i64   # the place in skyrim.lipTarget's order
	vertices i64[]
	deltas f32[]   # three a vertex

# the morphs of a head shape, whose vertices are `count` from `first` of the body's
pub type FaceShape:
	first i64
	count i64
	morphs LipMorph[]

fn lipMorphOf(tris Tri[], part nif.Part, first i64, target i64) LipMorph?:
	want = skyrim.lipTarget(target).lower()
	for t in tris:
		m = t.morphs.find(.name.lower() == want) ?? continue
		out = LipMorph(target, vertices = [], deltas = [])
		for v, delta in m.deltas:
			d = part.transform.applyDirection(delta)
			if d.length() < tinyDelta: continue
			out.vertices.push(first + v)
			out.deltas.extend([d.x, d.y, d.z])
		if not out.vertices.isEmpty: return out
	none

# the shape's morphs, none when no head part's TRI moves it
fn faceShapeOf(i skyrim.Install, headParts esm.Record[], part nif.Part, first i64) FaceShape?:
	name = part.name.lower()
	record = try headParts.find(esm.textOf(.body, .fields, "EDID").lower() == name)
	tris = []
	for key in record.headPartTris():
		if i.readTriKey(key) is t and t.positions.len == part.positions.len: tris.push(t)
	out = FaceShape(first, count = part.positions.len, morphs = [])
	for target in 0..skyrim.lipPhonemes.len + skyrim.lipModifiers.len:
		if lipMorphOf(tris, part, first, target) is m: out.morphs.push(m)
	out if not out.morphs.isEmpty else none

# The lip morphs of the worn models' shapes that have any, the head parts being the actor's.
pub fn faceShapes(i skyrim.Install, headParts esm.Record[], worn BodyPart[]) FaceShape[]:
	out = []
	first = 0
	for b in worn:
		for p in b.parts:
			if i.faceShapeOf(headParts, p, first) is shape: out.push(shape)
			first += p.positions.len
	out

# The shape's vertices as the floats `rest` (its own, gltf.skinVertexFloats a vertex) are moved by
# the weights of the lip targets together.
pub fn shapeMoved(s FaceShape, rest f32[], weights f32[]) f32[]:
	out = rest.copy()
	for m in s.morphs:
		w = weights[m.target] if m.target < weights.len else 0.0
		if w.abs() < 0.001: continue
		for k, v in m.vertices:
			at = (v - s.first) * gltf.skinVertexFloats
			out[at] += m.deltas[k * 3] * w
			out[at + 1] += m.deltas[k * 3 + 1] * w
			out[at + 2] += m.deltas[k * 3 + 2] * w
	out
