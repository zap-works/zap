# glTF 2.0 models read in Zap: a .glb (its JSON and its binary chunk) or a .gltf (its buffers
# in files beside it or in data: URIs, base64). What is read: the node tree (each node's rest
# translation, rotation and scale; a matrix is taken apart into them), the triangles of every
# mesh in the default scene with their materials (the base color's factor and texture, an
# emissive factor), the skins, and the animations (translation, rotation and scale; linear,
# step, and cubic splines read through their keys). Everything comes out ready for skinning
# (skin.zap): a vertex follows up to four entries of a palette, each entry a node and the
# inverse of its bind matrix; a mesh without a skin follows its own node's entry, so a sword
# hung on a hand bone moves with the hand. The base color textures are PNG.

import json
import fs
import image

# floats per vertex: position 3, normal 3, the texture place and two flags 4 (u, v, textured,
# emissive), the color 4, the palette entries 4, their weights 4
pub skinVertexFloats = 22

pub type Node:
	name str
	parent i64   # -1: a root
	translation Vec3
	rotation Quat
	scale Vec3

# how one property of one node changes over a clip
pub type Channel:
	node i64
	path Path
	step bool   # held from key to key, not interpolated
	cubic bool   # a cubic spline: its values in threes (in-tangent, value, out-tangent)
	times f32[]
	values f32[]

# the property of a node a channel changes
pub type Path:
	Translation
	Rotation
	Scale

# duration in seconds
pub type Clip:
	name str
	duration f32
	channels Channel[]

# the triangles drawn with one texture (image -1: none)
pub type Part:
	image i64
	indices u32[]

# a glTF file's contents, ready for skinning
pub type Model:
	nodes Node[]
	order i64[]   # every node, parents before their children
	palette i64[]   # the node each palette entry follows
	inverseBinds f32[]   # each entry's inverse bind matrix, 16 floats, column-major
	vertices f32[]   # skinVertexFloats per vertex
	parts Part[]
	images image.Image[]
	clips Clip[]

# what one file holds while it is read
type Source:
	doc json.Doc
	buffers u8[,]
	dir str

# the model in a .glb or .gltf file; stops with the reason when it cannot be read
pub fn loadGltf(path str) Model:
	file = fs.open(path) ?? fail("cannot read the model {path}")
	size = file.len
	head = file.readAt(0, 12) ?? fail("cannot read the model {path}")
	src = Source(
		doc = json.Doc(),
		buffers = [],
		dir = fs.dirOf(path).copy()
	)
	if head.startsWith("glTF"):
		# a .glb: the header, a JSON chunk, a binary chunk, each read where it lies
		at = 12
		bin = []
		while at + 8 <= size:
			chunk = file.readAt(at, 8) ?? fail("{path}: a chunk is cut short")
			n = i64(chunk.u32le(0))
			if chunk.matchesAt(4, "JSON"):
				src.doc = json.parse(
					str(file.readAt(at + 8, n) ?? fail("{path}: the JSON chunk is cut short"))
				) ?? fail
			elif chunk.matchesAt(4, "BIN\0"):
				bin = file.readAt(at + 8, n) ?? fail("{path}: the binary chunk is cut short")
			at += 8 + n
		src.buffers.push(bin)
	else:
		src.doc = json.parse(str(file.readAt(0, size) ?? fail("cannot read the model {path}"))) ??
			fail
	file.close()
	src.readBuffers(path)
	src.readModel()

fn readBuffers(mut src Source, path str):
	if src.doc.get(src.doc.root, "buffers") is list:
		for k in 0..src.doc.count(list):
			b = src.doc.at(list, k)
			uri = src.doc.textOf(b, "uri")
			if uri == "":
				if k >= src.buffers.len:
					fail("{path}: buffer {k} has no data")
			elif k < src.buffers.len:
				src.buffers[k] = bytesOfUri(uri, src.dir)
			else:
				src.buffers.push(bytesOfUri(uri, src.dir))

# the bytes a URI names: a data: URI's (base64), else a file's beside the model
fn bytesOfUri(uri str, dir str):
	if uri.startsWith("data:"):
		comma = uri.indexOf(",") ?? fail("a data URI without a comma")
		return decodeBase64(uri[comma + 1..])
	path = fs.join(dir, uri.replace("%20", " "))
	fs.readBytes(path) ?? fail("cannot read {path}")

fn readModel(src Source):
	d = src.doc
	root = d.root
	m = Model(
		nodes = [],
		order = [],
		palette = [],
		inverseBinds = [],
		vertices = [],
		parts = [],
		images = [],
		clips = []
	)
	nodesList = d.get(root, "nodes") ?? fail("a glTF model without nodes")
	n = d.count(nodesList)
	m.nodes = (0..n).map(d.readNode(d.at(nodesList, it)))
	for k in 0..n:
		if d.get(d.at(nodesList, k), "children") is kids:
			for c in 0..d.count(kids):
				m.nodes[i64(d[d.at(kids, c)].number)].parent = k
	for k in 0..n:
		if m.nodes[k].parent < 0:
			d.addInOrder(nodesList, k, m.order)
	# the images, each decoded once
	if d.get(root, "images") is list:
		m.images = (0..d.count(list)).map(src.readImage(d.at(list, it)))
	# the meshes of the nodes in the default scene, their skins' joints as palette entries
	nodeEntry = fill(n, -1)
	skinBase = []
	if d.get(root, "skins") is skins:
		for s in 0..d.count(skins):
			skin = d.at(skins, s)
			skinBase.push(m.palette.len)
			joints = d.get(skin, "joints") ?? fail("a skin without joints")
			count = d.count(joints)
			binds = []
			if d.get(skin, "inverseBindMatrices") is a:
				binds = src.readAccessor(i64(d[a].number))
			for j in 0..count:
				m.palette.push(i64(d[d.at(joints, j)].number))
				for e in 0..16:
					m.inverseBinds.push(
						binds[j * 16 + e] if binds.len >= (j + 1) * 16
						else (1.0 if e % 5 == 0 else 0.0)
					)
	inScene = d.sceneNodes(n, m.nodes)
	for k in 0..n:
		node = d.at(nodesList, k)
		if not inScene[k]: continue
		if d.get(node, "mesh") is meshIndex:
			base = -1
			if d.get(node, "skin") is skinIndex:
				base = skinBase[i64(d[skinIndex].number)]
			else:
				if nodeEntry[k] < 0:
					nodeEntry[k] = m.palette.len
					m.palette.push(k)
					for e in 0..16:
						m.inverseBinds.push(1.0 if e % 5 == 0 else 0.0)
			src.readMesh(i64(d[meshIndex].number), base, nodeEntry[k], m)
	# the animations
	if d.get(root, "animations") is list:
		m.clips = (0..d.count(list)).map(src.readClip(d.at(list, it)))
	m

# the node and those under it, parents first
fn addInOrder(d json.Doc, nodesList json.Node, k i64, mut order i64[]):
	order.push(k)
	if d.get(d.at(nodesList, k), "children") is kids:
		for c in 0..d.count(kids):
			d.addInOrder(nodesList, i64(d[d.at(kids, c)].number), order)

# which nodes the default scene holds (all of them when the file names no scene)
fn sceneNodes(d json.Doc, n i64, nodes Node[]):
	root = d.root
	scenes = d.get(root, "scenes") ?? return fill(n, true)
	scene = d.at(scenes, i64(d.number(root, "scene") ?? 0.0))
	roots = d.get(scene, "nodes") ?? return fill(n, true)
	isRoot = fill(n, false)
	for k in 0..d.count(roots):
		isRoot[i64(d[d.at(roots, k)].number)] = true
	out = fill(n, false)
	for k in 0..n:
		at = k
		while nodes[at].parent >= 0:
			at = nodes[at].parent
		out[k] = isRoot[at]
	out

fn readNode(d json.Doc, node json.Node):
	g = Node(
		name = d.textOf(node, "name"),
		parent = -1,
		translation = Vec3(0.0, 0.0, 0.0),
		rotation = Quat(0.0, 0.0, 0.0, 1.0),
		scale = Vec3(1.0, 1.0, 1.0)
	)
	if d.numbers(node, "matrix") is mat:
		g.takeApart(mat)
		return g
	if d.numbers(node, "translation") is t:
		g.translation = Vec3(f32(t[0]), f32(t[1]), f32(t[2]))
	if d.numbers(node, "rotation") is r:
		g.rotation = Quat(f32(r[0]), f32(r[1]), f32(r[2]), f32(r[3]))
	if d.numbers(node, "scale") is s:
		g.scale = Vec3(f32(s[0]), f32(s[1]), f32(s[2]))
	g

# a node's matrix (column-major) as translation, rotation and scale (no shear)
fn takeApart(mut g Node, m f64[]):
	g.translation = Vec3(f32(m[12]), f32(m[13]), f32(m[14]))
	sx = Vec3(f32(m[0]), f32(m[1]), f32(m[2])).length()
	sy = Vec3(f32(m[4]), f32(m[5]), f32(m[6])).length()
	sz = Vec3(f32(m[8]), f32(m[9]), f32(m[10])).length()
	g.scale = Vec3(sx, sy, sz)
	# the rotation's matrix, its columns divided by the scale
	r00 = f32(m[0]) / sx
	r10 = f32(m[1]) / sx
	r20 = f32(m[2]) / sx
	r01 = f32(m[4]) / sy
	r11 = f32(m[5]) / sy
	r21 = f32(m[6]) / sy
	r02 = f32(m[8]) / sz
	r12 = f32(m[9]) / sz
	r22 = f32(m[10]) / sz
	trace = r00 + r11 + r22
	if trace > 0.0:
		s = (trace + 1.0).sqrt() * 2.0
		g.rotation = Quat((r21 - r12) / s, (r02 - r20) / s, (r10 - r01) / s, 0.25 * s)
	elif r00 > r11 and r00 > r22:
		s = (1.0 + r00 - r11 - r22).sqrt() * 2.0
		g.rotation = Quat(0.25 * s, (r01 + r10) / s, (r02 + r20) / s, (r21 - r12) / s)
	elif r11 > r22:
		s = (1.0 + r11 - r00 - r22).sqrt() * 2.0
		g.rotation = Quat((r01 + r10) / s, 0.25 * s, (r12 + r21) / s, (r02 - r20) / s)
	else:
		s = (1.0 + r22 - r00 - r11).sqrt() * 2.0
		g.rotation = Quat((r02 + r20) / s, (r12 + r21) / s, 0.25 * s, (r10 - r01) / s)

fn readImage(src Source, img json.Node):
	d = src.doc
	fails = "a glTF image that is not a PNG this engine reads ({d.textOf(img, "name")})"
	if d.get(img, "bufferView") is v:
		return image.decodePng(src.viewBytes(i64(d[v].number))) ?? fail("{fails}: {error}")
	image.decodePng(bytesOfUri(d.textOf(img, "uri"), src.dir)) ?? fail("{fails}: {error}")

# the bytes of a buffer view
fn viewBytes(src Source, v i64) ref u8[]:
	d = src.doc
	views = d.get(d.root, "bufferViews") ?? fail("a glTF model without buffer views")
	view = d.at(views, v)
	b = src.buffers[i64(d.number(view, "buffer") ?? 0.0)]
	at = i64(d.number(view, "byteOffset") ?? 0.0)
	b[at..at + i64(d.number(view, "byteLength") ?? 0.0)]

# ---------- accessors ----------

# an accessor's values as floats, its components in a row (an integer one as its number, or
# 0..1 when it is normalized)
fn readAccessor(src Source, a i64):
	d = src.doc
	accessors = d.get(d.root, "accessors") ?? fail("a glTF model without accessors")
	acc = d.at(accessors, a)
	count = i64(d.number(acc, "count") ?? 0.0)
	width = componentsOf(d.textOf(acc, "type"))
	kind = i64(d.number(acc, "componentType") ?? 5126.0)
	normalized = (d.number(acc, "normalized") ?? 0.0) != 0.0
	if d.get(acc, "sparse") != none:
		fail("sparse glTF accessors are not read")
	v = d.get(acc, "bufferView") ?? return fill(count * width, f32(0.0))
	views = d.get(d.root, "bufferViews") ?? fail("a glTF model without buffer views")
	out = fill(count * width, f32(0.0))
	view = d.at(views, i64(d[v].number))
	b = src.buffers[i64(d.number(view, "buffer") ?? 0.0)]
	size = sizeOf(kind)
	stride = i64(d.number(view, "byteStride") ?? f64(size * width))
	start = i64(d.number(view, "byteOffset") ?? 0.0) + i64(d.number(acc, "byteOffset") ?? 0.0)
	for i in 0..count:
		row = start + i * stride
		for c in 0..width:
			out[i * width + c] = component(b, row + c * size, kind, normalized)
	out

fn componentsOf(t str):
	match t:
		"SCALAR": 1
		"VEC2": 2
		"VEC3": 3
		"VEC4", "MAT2": 4
		"MAT3": 9
		"MAT4": 16
		_: fail("a glTF accessor of type {t}")

fn sizeOf(kind i64):
	1 if kind == 5120 or kind == 5121 else 2 if kind == 5122 or kind == 5123 else 4

fn component(b u8[], at i64, kind i64, normalized bool):
	if kind == 5126: return b.f32le(at)
	if kind == 5121:
		v = f32(b[at])
		return v / 255.0 if normalized else v
	if kind == 5123:
		v = f32(b.u16le(at))
		return v / 65535.0 if normalized else v
	if kind == 5125: return f32(b.u32le(at))
	if kind == 5120:
		v = i64(b[at])
		if v >= 128:
			v -= 256
		return (f32(v) / 127.0).max(-1.0) if normalized else f32(v)
	v = b.i16le(at)
	(f32(v) / 32767.0).max(-1.0) if normalized else f32(v)

# ---------- meshes ----------

# The triangles of a mesh into the model: a skinned one follows its skin's entries from `base`,
# another follows its node's entry `rigid`.
fn readMesh(src Source, meshIndex i64, base i64, rigid i64, mut m Model):
	d = src.doc
	meshes = d.get(d.root, "meshes") ?? return
	prims = d.get(d.at(meshes, meshIndex), "primitives") ?? return
	for k in 0..d.count(prims):
		prim = d.at(prims, k)
		if i64(d.number(prim, "mode") ?? 4.0) != 4: continue
		attrs = d.get(prim, "attributes") ?? continue
		positionAt = d.get(attrs, "POSITION") ?? continue
		positions = src.readAccessor(i64(d[positionAt].number))
		count = positions.len / 3
		normals = src.attribute(attrs, "NORMAL")
		uvs = src.attribute(attrs, "TEXCOORD_0")
		joints = src.attribute(attrs, "JOINTS_0") if base >= 0 else []
		weights = src.attribute(attrs, "WEIGHTS_0") if base >= 0 else []
		paint = d.materialOf(prim)
		image = paint.image
		first = m.vertices.len / skinVertexFloats
		for i in 0..count:
			m.vertices.extend(positions[i * 3..i * 3 + 3])
			if normals.len >= (i + 1) * 3:
				m.vertices.extend(normals[i * 3..i * 3 + 3])
			else:
				for c in [0.0, 1.0, 0.0]:
					m.vertices.push(f32(c))
			m.vertices.push(uvs[i * 2] if uvs.len >= (i + 1) * 2 else 0.0)
			m.vertices.push(uvs[i * 2 + 1] if uvs.len >= (i + 1) * 2 else 0.0)
			m.vertices.push(1.0 if image >= 0 else 0.0)
			m.vertices.push(1.0 if paint.emissive else 0.0)
			for c in 0..4:
				m.vertices.push(paint.color[c])
			if joints.len >= (i + 1) * 4 and weights.len >= (i + 1) * 4:
				m.vertices.extend(
					joints[i * 4..i * 4 + 4].map(f32(base + i64(it)))
				)
				m.vertices.extend(weights[i * 4..i * 4 + 4])
			else:
				entry = base if base >= 0 else rigid
				for c in [f32(entry), 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0]:
					m.vertices.push(c)
		# the triangles go to the part of their texture
		part = m.parts.findIndex(.image == image) ?? -1
		if part < 0:
			part = m.parts.len
			m.parts.push(Part(image, indices = []))
		if d.get(prim, "indices") is ia:
			m.parts[part].indices.extend(
				src.readAccessor(i64(d[ia].number)).map(u32(first + i64(it)))
			)
		else:
			m.parts[part].indices.extend((0..count).map(u32(first + it)))

# a primitive's attribute of that name ([] when it has none)
fn attribute(src Source, attrs json.Node, name str) f32[]:
	match src.doc.get(attrs, name):
		a: src.readAccessor(i64(src.doc[a].number))
		none: []

# a primitive's material: its base color (linear), the image of its texture (-1 none), and
# whether it glows (an emissive factor and no texture: the color is the light it gives)
type Paint:
	color f32[4]
	image i64
	emissive bool

fn materialOf(d json.Doc, prim json.Node):
	paint = Paint(color = [1.0, 1.0, 1.0, 1.0], image = -1, emissive = false)
	materials = d.get(d.root, "materials") ?? return paint
	mi = d.get(prim, "material") ?? return paint
	mat = d.at(materials, i64(d[mi].number))
	if d.get(mat, "pbrMetallicRoughness") is pbr:
		if d.numbers(pbr, "baseColorFactor") is f:
			paint.color = [f32(f[0]), f32(f[1]), f32(f[2]), f32(f[3])]
		if d.get(pbr, "baseColorTexture") is t:
			if d.get(d.root, "textures") is textures:
				tex = d.at(textures, i64(d.number(t, "index") ?? 0.0))
				paint.image = i64(d.number(tex, "source") ?? -1.0)
	if paint.image < 0:
		if d.numbers(mat, "emissiveFactor") is e:
			if e[0] + e[1] + e[2] > 0.0:
				paint.color = [f32(e[0]), f32(e[1]), f32(e[2]), 1.0]
				paint.emissive = true
	paint

# ---------- animations ----------

fn readClip(src Source, anim json.Node):
	d = src.doc
	clip = Clip(name = d.textOf(anim, "name"), duration = 0.0, channels = [])
	if d.get(anim, "samplers") is samplers:
		if d.get(anim, "channels") is channels:
			for k in 0..d.count(channels):
				src.readChannel(samplers, d.at(channels, k), clip)
	clip

fn readChannel(src Source, samplers json.Node, ch json.Node, mut clip Clip):
	d = src.doc
	target = d.get(ch, "target") ?? return
	node = d.get(target, "node") ?? return
	path Path = match d.textOf(target, "path"):
		"translation": .Translation
		"rotation": .Rotation
		"scale": .Scale
		_: return
	s = d.at(samplers, i64(d.number(ch, "sampler") ?? 0.0))
	interpolation = d.textOf(s, "interpolation")
	times = src.readAccessor(i64(d.number(s, "input") ?? 0.0))
	values = src.readAccessor(i64(d.number(s, "output") ?? 0.0))
	if not times.isEmpty:
		clip.duration = clip.duration.max(times[len - 1])
	clip.channels.push(Channel(
		node = i64(d[node].number),
		path,
		step = interpolation == "STEP",
		cubic = interpolation == "CUBICSPLINE",
		times,
		values))

# ---------- base64 ----------

fn sextet(c u8) i64:
	if c >= 'A' and c <= 'Z': return c - 'A'
	if c >= 'a' and c <= 'z': return i64(c - 'a') + 26
	if c >= '0' and c <= '9': return i64(c - '0') + 52
	if c == '+' or c == '-': return 62
	if c == '/' or c == '_': return 63
	-1

# the bytes a base64 text stands for (padding and anything else not of the alphabet skipped)
pub fn decodeBase64(text str) u8[]:
	out u8[] = []
	out.reserve(text.len * 3 / 4)
	acc = 0
	bits = 0
	for i in 0..text.len:
		v = sextet(text[i])
		if v < 0: continue
		acc = (acc << 6 | v) & 0xFF_FFFF
		bits += 6
		if bits >= 8:
			bits -= 8
			out.push(acc.bits(bits, 8))
	out
