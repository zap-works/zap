# One recorded draw on the engine: its program set's translation, the targets it writes, its
# first viewport and scissor, its textures and its vertices as triangles.

import engine
import rhi.core
import recomp.switch.maxwell
import recomp.switch.shaders
import recomp.switch.textures

topologyTriangles = 4
topologyStrip = 5
topologyFan = 6
topologyQuads = 7

# the vertex numbers of the draw's triangles, one after another; none for other primitives
fn triangles(topology i64, n i64[]) i64[]?:
	out = []
	match topology:
		4: return n.copy()
		5:
			for k in 2..n.len:
				if k % 2 == 0: out.extend([n[k - 2], n[k - 1], n[k]])
				else: out.extend([n[k - 1], n[k - 2], n[k]])
		6:
			for k in 2..n.len:
				out.extend([n[0], n[k - 1], n[k]])
		7:
			for k in (0..n.len / 4).map(it * 4):
				out.extend([n[k], n[k + 1], n[k + 2], n[k], n[k + 2], n[k + 3]])
		_: return none
	out

# the program of a set, built the first time
fn programOf(mut rp Replayer, key str) engine.Program?:
	if rp.programs.get(key) is p: return p.copy()
	code = try rp.table.code(key)
	p = engine.newProgram(code)
	rp.programs[key.copy()] = p.copy()
	p

fn draw(mut rp Replayer, mut r engine.Renderer, space maxwell.AddressSpace, d maxwell.DrawCall):
	if d.programNames.len != 2: return rp.skip("a program set of {d.programNames.len} stages")
	key = d.programNames.join(" ")
	p = rp.programOf(key) ?? return rp.skip("an untranslated program set")
	targets = (0..d.targetCount).map(d.targets[d.targetMap[it]])
	if targets.isEmpty: return rp.skip("a draw with no target")
	setKey = rp.setOf(targets) ?? return
	n = rp.verticesOf(space, d, "P{d.programNames[0]}") ?? return
	textureList = rp.texturesOf(space, d) ?? return
	r.useTargetSet(rp.sets[setKey].set)
	r.setDepth(false, false, false)
	r.setTargetBlends([])
	if not d.viewports.isEmpty:
		v = d.viewports[0]
		r.setViewport(
			core.Viewport(x = f32(v.x), y = f32(v.y), width = f32(v.width), height = f32(v.height))
		)
	r.setScissor(none)
	rp.table.setParams(p, d.vertexConstants, d.pixelConstants, textureList, [], [])
	r.drawModel(p, n)

# The draw's vertices as a model of the vertex program's Attributes (each a Vec4 of a generic
# attribute, in its fields' order), as triangles.
fn verticesOf(
	mut rp Replayer,
	space maxwell.AddressSpace,
	d maxwell.DrawCall,
	vertexName str
) engine.Model?:
	indices = []
	if d.indexed and d.inlineIndices.isEmpty:
		indices = space.read(d.index.address, (d.index.end - d.index.address).clamp(0, 1 << 24))
	numbers = triangles(d.topology, d.vertexNumbers(indices)) ??
		return rp.skipped("topology {d.topology}")
	if numbers.isEmpty: return none
	order = rp.table.attributes(vertexName)
	bytes = []
	for v in numbers:
		for a in order:
			value = space.attributeAt(d, a, v)
			for c in [value.x, value.y, value.z, value.w]:
				bytes.pushU32le(c.toBits())
	if order.isEmpty: return rp.skipped("a vertex stage with no attributes")
	engine.newModel(bytes, stride = order.len * 16)

# generic attribute `a` of vertex v: from its stream, (0, 0, 0, 1) when not fed
fn attributeAt(space maxwell.AddressSpace, d maxwell.DrawCall, a i64, v i64):
	attribute = d.attributes.find(.index == a) ?? return Vec4(0.0, 0.0, 0.0, 1.0)
	if attribute.constant or attribute.stream >= d.streams.len: return Vec4(0.0, 0.0, 0.0, 1.0)
	s = d.streams[attribute.stream]
	if not s.enabled: return Vec4(0.0, 0.0, 0.0, 1.0)
	at = s.address + v * s.stride + attribute.offset
	attribute.attributeValue(space.read(at, attributeBytes(attribute.size)), 0)

# the draw's textures in the shared Params' array, a blank one where a slot is unused
fn texturesOf(mut rp Replayer, space maxwell.AddressSpace, d maxwell.DrawCall) engine.Texture[]?:
	out = []
	for stage, name in d.programNames:
		constants = d.vertexConstants if stage == 0 else d.pixelConstants
		for use in rp.table.textures("P{name}"):
			if use.kind != .Plain: return rp.skipped("a texture of layers or a shadow map")
			at = d.textureBufferSlot * shaders.bankWords + use.handle
			handle = i64(constants[at]) if at < constants.len else 0
			t = try rp.textureOf(space, d, handle)
			while out.len <= use.slot:
				out.push(rp.blank.texture())
			out[use.slot] = t
	if out.isEmpty: out.push(rp.blank.texture())
	out

# The texture a handle names (TIC index in its low 20 bits): a target drawn earlier when it lies at
# a target's address, else decoded from memory once for its address, size and format.
fn textureOf(
	mut rp Replayer,
	space maxwell.AddressSpace,
	d maxwell.DrawCall,
	handle i64
) engine.Texture?:
	tic = textures.decodeTic(
		space.read(
			d.texturePool.address + (handle & 0xF_FFFF) * textures.entryBytes,
			textures.entryBytes
		)
	)
	if rp.trace: eprint("  texture {handle:x}: {tic.address:x} format {tic.format:x} {tic.width}x{tic.height}")
	if rp.targetAt(tic.address) is (key, k): return rp.sets[key].set.colorTexture(k)
	key = "{tic.address:x}:{tic.format:x}:{tic.width}x{tic.height}"
	if rp.textures.get(key) is known: return known.texture()
	size = tic.textureBytes()
	if size == 0: return rp.skipped("texture format {tic.format:x} (handle {handle:x}, pool {d.texturePool.address:x}, slot {d.textureBufferSlot}, bound {d.constantBuffers.map("{it.kind}:{it.slot}:{it.size:x}").join(",")})")
	img = tic.decodeTexture(space.read(tic.address, size)) ??
		return rp.skipped("texture format {tic.format:x}")
	rp.textures[key.copy()] = img.newTexture()
	rp.textures[key].texture()
