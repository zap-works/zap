# A program as the compiler built it (`shader(...)`): the binaries of its two stages for each
# backend and what it reads, laid out as the compiler's shader module writes them (its
# shader.zap): the parameter block (each parameter struct a part of it), the textures, the
# storage buffers, the vertex inputs and the strides of their streams. Both backends make their
# bindings from this; the engine sets the parameters' words (the struct's packer writes them)
# and makes the vertex layouts.

import win

pub paramsBinding = 32   # the parameter block's binding (Vulkan's)
pub bufferBase = 16   # a storage buffer's binding: this past the shader's

pub samplerKind2D = 1
pub samplerKindArray = 2
pub samplerKindShadow = 3   # a depth texture read with comparisons
pub samplerKindShadowArray = 4   # a depth texture's layers read with comparisons

# whether a sampler kind reads an array's layers
pub fn isLayeredKind(kind i64) bool:
	kind == samplerKindArray or kind == samplerKindShadowArray

# a parameter struct's part of the block: its name (module.Struct), its first byte, and the
# textures, storage buffers and texture arrays its fields are (the first binding and how many)
pub type ProgramPart:
	name str
	offset i64
	firstTexture i64
	textures i64
	firstBuffer i64
	buffers i64
	firstArray i64
	arrays i64

# kind: samplerKind...
pub type SamplerSlot:
	binding u32
	kind n32

# a vertex input: its location, its component type, its size, its stream (0 the vertex's, 1 the
# instance's) and its offset in that stream's element
pub type VertexInput:
	location u32
	base u32   # 2 int, 3 uint, 4 float
	rows u32
	stream u32
	offset u32

# a texture array: its binding (set 1), its textures' kind, its length (0 unbounded)
pub type TextureArraySlot:
	binding u32
	kind n32
	count u32

# what the compiler built of a program
pub type ProgramCode:
	paramBytes i64
	parts ProgramPart[]
	samplers SamplerSlot[]
	buffers i64[]   # the storage buffers' bindings (bufferBase + the shader's)
	inputs VertexInput[]
	vertexStride i64   # a vertex's bytes (0: the program reads no vertex buffer)
	instanceStride i64   # an instance's bytes (0: none)
	vertexSpirv str
	fragmentSpirv str
	vertexDxil str
	fragmentDxil str
	arrays TextureArraySlot[]

# what the compiler built of a compute program (compute(...)): its parameters, textures and
# storage buffers as a program's (whether the stage writes each buffer), the size of its groups,
# its binaries
pub type ComputeCode:
	paramBytes i64
	parts ProgramPart[]
	samplers SamplerSlot[]
	buffers i64[]
	written bool[]   # per storage buffer
	groupSize i64[]   # x, y, z
	spirv str
	dxil str
	arrays TextureArraySlot[]

# a run of bytes after its length, padded to whole words
fn bytesNext(mut r Reader) str:
	n = i64(r.u32())
	run = r.bytes(n)
	r.skip((n + 3) / 4 * 4 - n)
	str(move run)

# what a program's code holds
pub fn readProgram(code str) ProgramCode:
	if code.len < 8 or code[..4] != "ZSH2":
		fail("rhi: not a program built by shader(...) (or one built by an older compiler)")
	codeBytes = code.bytes()
	r = Reader(d = codeBytes, at = 4)
	paramBytes = r.u32()
	parts = r.partsNext()
	samplers = SamplerSlot[].fromBytes(r)
	buffers = u32[].fromBytes(r).map(i64(it))
	inputs = VertexInput[].fromBytes(r)
	vertexStride = r.u32()
	instanceStride = r.u32()
	vertexSpirv = r.bytesNext()
	fragmentSpirv = r.bytesNext()
	vertexDxil = r.bytesNext()
	fragmentDxil = r.bytesNext()
	arrays = TextureArraySlot[].fromBytes(r)
	ProgramCode(paramBytes, parts, samplers, buffers, inputs, vertexStride, instanceStride,
		vertexSpirv, fragmentSpirv, vertexDxil, fragmentDxil, arrays)

# what a compute program's code holds (compute(...)'s "ZSC1": its parameters' parts and textures
# as a program's, each storage buffer's binding and whether the stage writes it, the groups'
# size, the SPIR-V and the DXIL, the texture arrays)
pub fn readCompute(code str) ComputeCode:
	if code.len < 8 or code[..4] != "ZSC1":
		fail(
			"rhi: not a compute program built by compute(...) (or one built by an older compiler)"
		)
	codeBytes = code.bytes()
	r = Reader(d = codeBytes, at = 4)
	paramBytes = r.u32()
	parts = r.partsNext()
	samplers = SamplerSlot[].fromBytes(r)
	buffers = []
	written = []
	loop r.u32():
		buffers.push(i64(r.u32()))
		written.push(r.u32() == 1)
	groupSize i64[] = [r.u32(), r.u32(), r.u32()]
	spirv = r.bytesNext()
	dxil = r.bytesNext()
	arrays = TextureArraySlot[].fromBytes(r)
	ComputeCode(paramBytes, parts, samplers, buffers, written, groupSize, spirv, dxil, arrays)

# the parameter block's parts: each its name, its first byte, its textures', storage buffers' and
# texture arrays' first bindings and counts
fn partsNext(mut r Reader):
	parts = []
	loop r.u32():
		name = r.bytesNext()
		parts.push(ProgramPart(
			name,
			offset = r.u32(),
			firstTexture = r.u32(),
			textures = r.u32(),
			firstBuffer = r.u32(),
			buffers = r.u32(),
			firstArray = r.u32(), arrays = r.u32()))
	parts

# ---------- parameters ----------

# The block's words set to `values` (as many as both hold): whether one changed (a block set to
# what it holds needs no new upload).
pub fn writeParams(mut words u32[], values u32[]) bool:
	n = words.len.min(values.len)
	changed = false
	for i in 0..n:
		if words[i] != values[i]:
			words[i] = values[i]
			changed = true
	changed

# ---------- texture arrays ----------

# A program's texture arrays as the RHI binds them (descriptor set 1, space 1 + binding): each
# array's slot and the texture ids its parameters list (as the packer wrote them), and a version
# raised whenever an id changes or a texture they name is destroyed or sampled otherwise, so a
# backend writes its tables again only then.
pub type TextureLists:
	slots TextureArraySlot[]
	ids i64[,]
	version i64 = 0

# no ids set yet
pub fn newTextureLists(move slots TextureArraySlot[]) TextureLists:
	ids i64[,] = fill(slots.len, [])
	TextureLists(slots, ids)

# the arrays' ids set (as many arrays as both hold): whether one changed
pub fn setTextureLists(mut l TextureLists, ids i64[,]) bool:
	changed = false
	for k in 0..l.ids.len.min(ids.len):
		if l.ids[k] != ids[k]:
			l.ids[k] = ids[k].copy()
			changed = true
	if changed:
		l.version += 1
	changed

# a texture that changed (destroyed, or sampled otherwise): the tables that hold it are stale
pub fn touchTexture(mut l TextureLists, id i64):
	for ids in l.ids:
		if id in ids:
			l.version += 1
			return

# how many textures an array's table holds: its length, or for one without a length its ids
# rounded up to a power of two (at least 64), so that a list that grows a little keeps its table
pub fn tableRoom(l TextureLists, k i64) i64:
	if l.slots[k].count > 0: return l.slots[k].count
	room = 64
	while room < l.ids[k].len:
		room *= 2
	room

# ---------- a device's programs ----------

# a program as both backends keep it beside its API objects: its code's hash (what the pipeline
# store knows it by), what it reads, its parameters' words and its pipelines
pub type ProgramState:
	code i64
	lists TextureLists
	samplers SamplerSlot[]
	buffers i64[]
	inputs VertexInput[]
	params u32[]   # the parameter block's words
	pipelines {PipelineKey: PipelineEntry}
	written bool[] = []   # a compute program's: per storage buffer, whether its stage writes it
	# where the parameters (and the y flip after them) were last copied into a frame's ring:
	# reused while they are unchanged in the same frame (uploadFrame: the device's timeline then)
	paramsChanged bool = true
	uploadFrame i64 = -1
	uploadFlip f32 = 0.0
	uploadBuffer i64 = 0
	uploadOffset i64 = 0

# The program of the compiler's code for it (shader(...)), and the pipelines the last run drew
# it with made now (from the driver's cache) rather than by its first draws.
pub fn newProgram<B Backend>(mut b B, code str) i64:
	p = readProgram(code)
	b.newProgram(p)
	params = fill((p.paramBytes + 3) / 4, u32(0))
	s mut ref DeviceState = b.deviceState()
	s.programs.push(ProgramState(
		code = code.hash(),
		lists = newTextureLists(move p.arrays),
		samplers = move p.samplers,
		buffers = move p.buffers,
		inputs = move p.inputs,
		params = params, pipelines = {}))
	id = s.programs.len - 1
	warmPipelines(b, id)
	id

# The compute program of the compiler's code for it (compute(...)), its pipeline made now: a
# program as a draw's is (its parameters, textures and storage buffers set the same way).
pub fn newCompute<B Backend>(mut b B, code str) i64:
	c = readCompute(code)
	b.newCompute(c)
	params = fill((c.paramBytes + 3) / 4, u32(0))
	s mut ref DeviceState = b.deviceState()
	s.programs.push(ProgramState(
		code = code.hash(),
		lists = newTextureLists(move c.arrays),
		samplers = move c.samplers,
		buffers = move c.buffers,
		inputs = [],
		params = params,
		pipelines = {},
		written = move c.written))
	s.programs.len - 1

# the parameter block's words set (as the parameter structs' packers wrote them)
pub fn setParams(mut s DeviceState, program i64, words u32[]):
	rec = mut ref s.programs[program]
	if writeParams(rec.params, words):
		rec.paramsChanged = true

# the texture ids each of the program's texture arrays lists (as its parameters' packers wrote
# them): its tables are written again before a draw reads them when one changed
pub fn setTextureArrays(mut s DeviceState, program i64, ids i64[,]):
	s.programs[program].lists.setTextureLists(ids)

# The program's parameters (and the pass's y flip after them, where it follows them) in this
# frame's ring: copied there when they changed since their last copy, the flip differs or that
# copy was an earlier frame's, else the last copy. The ring's buffer handle and the offset there.
pub fn uploadParams<B Backend>(mut b B, program i64) (i64, i64):
	s mut ref DeviceState = b.deviceState()
	last = s.programs[program]
	if not last.paramsChanged and last.uploadFrame == s.timeline and last.uploadFlip == s.flip:
		s.stats.paramsSkipped += 1
		return (last.uploadBuffer, last.uploadOffset)
	n = last.params.len * 4
	tail = 16 if s.flipAfterParams else 0
	ring, offset, at = transient(b, n + tail, 256)
	t mut ref DeviceState = b.deviceState()
	room = win.memoryAt(at, n + tail)
	if n > 0:
		room.write(0, t.programs[program].params)
	if tail > 0:
		room.write(n, t.flipWords)
	t.stats.paramUploads += 1
	t.stats.bytesUploaded += n + tail
	t.programs[program].paramsChanged = false
	t.programs[program].uploadFrame = t.timeline
	t.programs[program].uploadFlip = t.flip
	t.programs[program].uploadBuffer = ring
	t.programs[program].uploadOffset = offset
	(ring, offset)

# The parameters a draw reads: the copy it names (DrawCall's paramsCopy, -1 none), else the
# program's as they are now; (0, 0) for a program that reads none.
pub fn paramsOf<B Backend>(mut b B, program i64, paramsCopy i64) (i64, i64):
	s mut ref DeviceState = b.deviceState()
	if paramsCopy >= 0: return (s.paramsCopies[paramsCopy * 2], s.paramsCopies[paramsCopy * 2 + 1])
	reads = s.programs[program].params.len > 0 or s.flipAfterParams
	uploadParams(b, program) if reads else (0, 0)

# A program's parameters as they are now copied for a draw made later in this frame's current
# pass (DrawCall's paramsCopy): the copy's number.
pub fn copyParams<B Backend>(mut b B, program i64) i64:
	buffer, offset = paramsOf(b, program, -1)
	s mut ref DeviceState = b.deviceState()
	s.paramsCopies.push(buffer)
	s.paramsCopies.push(offset)
	s.paramsCopies.len / 2 - 1
