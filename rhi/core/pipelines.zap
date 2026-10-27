# Pipelines kept from one run to the next, beside the program's executable (<exe>.vulkan-pipelines,
# <exe>.d3d12-pipelines): the variants each program was drawn with (its vertex layout, blending,
# targets' formats, Direct3D 12's state bits) and the driver's own cache of them (Vulkan's pipeline
# cache data, Direct3D 12's pipeline library). The next run makes a program's variants as soon as
# the program is made, from the driver's cache (a fraction of a millisecond each), so its first
# frames make none. A file of another driver or device is used without the driver's cache (Vulkan:
# its header names another device; Direct3D 12: the library refuses it), a damaged one not at all.
# The file is written once no pipeline has been made for a while (and when the window closes);
# it keeps the variants of the programs made in that run. pipelinecache=off (ZAP_RUN) keeps none.

import fs

# the frames without a new pipeline after which the file is written
quietFrames = 120
# the most of the driver's cache kept (one past it is dropped: the next run starts a new one)
mostCached = 67_108_864
magic = "ZAPPIPE2"

# a pipeline as a program was drawn with it: what makes it besides the program's own code
pub type PipelineVariant:
	program i64   # the program's code, hashed
	hasLayout bool   # false: the program reads no vertex buffer (layout -1)
	layout VertexLayout
	state PipelineState
	blends TargetBlend[] = []   # the blend set `state` names, [] none
	colorFormat i64
	extraFormats i64 = 0
	depthFormat i64
	samples i64
	bits i64   # the state bits (Direct3D 12's pipelines hold them; 0 for Vulkan)
	turn i64 = 0   # the quarter turns of the screen it draws on (passTurn)

type PipelineFile:
	variants PipelineVariant[]
	blob u8[]

# the variants and the driver's cache kept from run to run
pub type PipelineStore:
	path str   # the file, "" when none is kept
	variants PipelineVariant[]   # as loaded, then those made in this run
	blob u8[]   # the driver's cache as loaded (Direct3D 12's library reads it while it lives)
	programs i64[]   # the programs made in this run (their hashes): whose variants are written
	unsaved bool   # a variant was made since the file was written
	quiet i64   # frames since a pipeline was made
	warmed i64   # pipelines made with their programs (variants of the last run)
	drawn i64   # pipelines made by a draw that needed them
	seconds f64   # spent making pipelines

# a store that keeps nothing (a device not made yet)
pub fn noPipelineStore() PipelineStore:
	PipelineStore(
		path = "",
		variants = [],
		blob = [],
		programs = [],
		unsaved = false,
		quiet = 0,
		warmed = 0,
		drawn = 0,
		seconds = 0.0
	)

fn pipelineCacheWord():
	RunWord("pipelinecache", "pipelinecache=off keeps no pipelines between runs")

# the store of a backend ("vulkan", "d3d12"): its file read, when there is one and it is whole
pub fn openPipelineStore(backend str) PipelineStore:
	asked = pipelineCacheWord().value() ?? ""
	path = "" if asked == "off" else "{exePath()}.{backend}-pipelines"
	s = noPipelineStore()
	text = "" if path == "" else fs.readFile(path) ?? ""
	# checked as text (its hash); the decoding takes bytes of its own
	if text.len >= 16 and text[..8] == magic and
		i64(text.loadWord(8)) == text[16..].hash():
		if PipelineFile.fromBytes(text.bytes()[16..text.len]) is f:
			s.variants = f.variants
			s.blob = f.blob
	s.path = path
	s

# the variants of the last run of the program of this code (hash), noted as made in this one
pub fn variantsOf(mut s PipelineStore, program i64) PipelineVariant[]:
	if program not in s.programs:
		s.programs.push(program)
	s.variants.filter(.program == program)

# a pipeline made (while drawing, or with its program), `seconds` it took: a new variant kept
pub fn notePipeline(mut s PipelineStore, move v PipelineVariant, warm bool, seconds f64):
	s.seconds += seconds
	if warm:
		s.warmed += 1
		return
	s.drawn += 1
	s.quiet = 0
	for known in s.variants:
		if known.isSameVariant(v): return
	s.variants.push(v)
	s.unsaved = true

# a frame ended: whether the file is due (variants made, then none for a while)
pub fn pipelineStoreDue(mut s PipelineStore) bool:
	s.quiet += 1
	s.path != "" and s.unsaved and s.quiet >= quietFrames

# The file written with the driver's cache (`blob`): the variants of the programs made in this
# run, a hash of them; into a file beside it first, then moved over the old one (a run stopped
# halfway leaves the old file).
pub fn writePipelineStore(mut s PipelineStore, move blob u8[]):
	s.unsaved = false
	if s.path == "": return
	kept = s.variants.filter(.program in s.programs)
	payload = PipelineFile(
		variants = kept,
		blob = [] if blob.len > mostCached else blob
	).toBytes()
	body = str(move payload)
	head = magic.bytes().copy()
	head.extend([body.hash()].rawBytes())
	text = str(move head) + body
	partial = "{s.path}.part"
	fs.writeFile(partial, text) ?? return
	_ = fs.moveFile(partial, s.path)

# the pipelines made so far on one line, for ZAP_RUN=gpu
pub fn describePipelines(s PipelineStore) str:
	"pipelines: {s.warmed} made with their programs, {s.drawn} by draws, {(s.seconds * 1000.0):.1} ms; {("none kept" if s.path == "" else "kept in {s.path}")}"

pub fn isSameVariant(a PipelineVariant, b PipelineVariant) bool:
	a.program == b.program and a.hasLayout == b.hasLayout and a.layout.isSameLayout(b.layout) and
		a.state.blend == b.state.blend and
		a.state.alphaToCoverage == b.state.alphaToCoverage and a.state.lines == b.state.lines and
		a.blends == b.blends and a.colorFormat == b.colorFormat and
		a.extraFormats == b.extraFormats and a.depthFormat == b.depthFormat and
		a.samples == b.samples and a.bits == b.bits

# whether two vertex layouts read the same buffers the same way
pub fn isSameLayout(a VertexLayout, b VertexLayout) bool:
	if a.bindings.len != b.bindings.len or a.attributes.len != b.attributes.len: return false
	for i in 0..a.bindings.len:
		if a.bindings[i].stride != b.bindings[i].stride or
			a.bindings[i].perInstance != b.bindings[i].perInstance:
			return false
	for i, x in a.attributes:
		y = b.attributes[i]
		if x.location != y.location or x.binding != y.binding or x.format != y.format or
			x.offset != y.offset:
			return false
	true

# ---------- a program's pipelines ----------

# what a program's pipeline is made for besides the program
pub type PipelineKey:
	layout i64   # a vertex layout, -1 none
	blend i64
	alphaToCoverage bool
	lines bool
	blends i64 = -1   # a blend set, -1 none
	colorFormat i64
	extraFormats i64 = 0   # the formats of the color targets after the first (packFormats)
	depthFormat i64
	samples i64
	bits i64   # the state bits (stateBits) where the pipeline holds them (Direct3D 12's), else 0
	turn i64 = 0   # the quarter turns of the screen it draws on (passTurn), 0 elsewhere

pub type PipelineEntry:
	pipeline i64
	zeroBinding i64   # the binding fed zeros for an input the layout lacks, -1 none

# the pipeline of a program drawn with a layout (-1 none), a state and the state bits (0 where
# they are dynamic) into the current pass's targets
pub fn pipelineFor<B Backend>(
	mut b B,
	program i64,
	layout i64,
	state PipelineState,
	bits i64
) PipelineEntry:
	s mut ref DeviceState = b.deviceState()
	p = s.pass
	key = PipelineKey(
		layout = layout,
		blend = state.blend,
		alphaToCoverage = state.alphaToCoverage,
		lines = state.lines,
		blends = state.blends,
		colorFormat = p.colorFormat,
		extraFormats = p.extraFormats,
		depthFormat = p.depthFormat, samples = p.samples, bits = bits, turn = s.passTurn())
	pipelineOf(b, program, key)

# the program's pipeline for a key: the one made, else made now
pub fn pipelineOf<B Backend>(mut b B, program i64, key PipelineKey) PipelineEntry:
	s mut ref DeviceState = b.deviceState()
	if s.programs[program].pipelines.get(key) is e: return e
	makePipeline(b, program, key, false)

# The program's pipeline for a key made (through the driver's cache) and kept, and noted in the
# pipeline store: `warm` when it is made with its program (a variant of the last run), else by a
# draw that needs it.
fn makePipeline<B Backend>(mut b B, program i64, key PipelineKey, warm bool) PipelineEntry:
	started = clockSeconds()
	s mut ref DeviceState = b.deviceState()
	state = PipelineState(
		blend = key.blend,
		alphaToCoverage = key.alphaToCoverage,
		lines = key.lines,
		blends = key.blends
	)
	# the pipeline store keeps the variant, with a layout of its own
	v = PipelineVariant(
		program = s.programs[program].code,
		hasLayout = key.layout >= 0,
		layout = (s.layouts[key.layout] if key.layout >= 0 else s.noLayout).copy(),
		state = state,
		blends = (s.blendSets[key.blends] if key.blends >= 0 else []).copy(),
		colorFormat = key.colorFormat,
		extraFormats = key.extraFormats,
		depthFormat = key.depthFormat, samples = key.samples, bits = key.bits, turn = key.turn)
	e PipelineEntry = b.newPipeline(program, key, v.layout, v)
	t mut ref DeviceState = b.deviceState()
	t.programs[program].pipelines[key] = e
	notePipeline(t.pipelineStore, v, warm, clockSeconds() - started)
	e

# the pipelines the last run drew a program with, made with it
fn warmPipelines<B Backend>(mut b B, program i64):
	s mut ref DeviceState = b.deviceState()
	variants = variantsOf(s.pipelineStore, s.programs[program].code)
	for k in 0..variants.len:
		t mut ref DeviceState = b.deviceState()
		layout = vertexLayout(t, move variants[k].layout) if variants[k].hasLayout else -1
		blends = -1 if variants[k].blends.isEmpty else blendSet(t, move variants[k].blends)
		v = variants[k]
		_ = makePipeline(b, program, PipelineKey(
			layout = layout,
			blend = v.state.blend,
			alphaToCoverage = v.state.alphaToCoverage,
			lines = v.state.lines,
			blends,
			colorFormat = v.colorFormat,
			extraFormats = v.extraFormats,
			depthFormat = v.depthFormat, samples = v.samples, bits = v.bits, turn = v.turn), true)

# a vertex layout's number: the one already made of the same bindings and attributes, if any
# (pipelines made ahead of the draws name it)
pub fn vertexLayout(mut s DeviceState, move layout VertexLayout) i64:
	for i in 0..s.layouts.len:
		if s.layouts[i].isSameLayout(layout): return i
	s.layouts.push(layout)
	s.layouts.len - 1

# a blend set's number (a blending per color target, PipelineState's blends): the one already
# made of the same blendings, if any
pub fn blendSet(mut s DeviceState, move blends TargetBlend[]) i64:
	for i, blendSet in s.blendSets:
		if blendSet == blends: return i
	s.blendSets.push(blends)
	s.blendSets.len - 1

# the blending of each color target of a pipeline's key: its blend set's, else its mode's
pub fn targetBlends(s DeviceState, key PipelineKey) TargetBlend[]:
	if key.colorFormat == fmtUndefined: return []
	n = key.colorFormats().len
	set = s.blendSets[key.blends] if key.blends >= 0 else []
	(0..n).map(set[it] if it < set.len else presetBlend(key.blend))

# the formats of a pipeline's color targets, in order ([] none)
pub fn colorFormats(key PipelineKey) i64[]:
	if key.colorFormat == fmtUndefined: return []
	formats = [key.colorFormat]
	formats.extend(unpackFormats(key.extraFormats))
	formats
