# A pass as a backend keeps it: its targets, their size, formats and samples, and what its draws
# last set (a draw sets only what changes). The state a draw's pipeline needs besides its
# program and layout is packed in bits, the same for every backend.

# the pass being drawn, and what its draws last set
pub type Pass:
	active bool
	color i64   # a texture, screenTarget, or noTarget
	extraColors i64[] = []   # the textures of a set's color targets after the first
	depth i64   # a texture, or noTarget
	width i64
	height i64
	colorFormat i64
	extraFormats i64 = 0   # the extra colors' formats, 8 bits each from the lowest
	depthFormat i64
	samples i64
	screenTouched bool   # the swapchain image was drawn into this frame
	pipeline i64 = 0   # what the pass's draws last set
	index i64 = 0   # the index buffer (a backend's handle, 0 none)
	layout i64 = 0   # the pipeline layout or root signature they last set
	topology i64 = -1
	state i64 = -1   # the state bits (stateBits)
	rects bool = false   # the last draw set a viewport or scissor of its own

pub fn noPass() Pass:
	Pass(
		active = false,
		color = noTarget,
		depth = noTarget,
		width = 0,
		height = 0,
		colorFormat = fmtUndefined,
		depthFormat = fmtUndefined,
		samples = 1,
		screenTouched = false
	)

# The state of a draw into the pass, in bits: culling (bit 0), front faces counter-clockwise
# (bit 1 clear: the screen's) or clockwise (a target's: the same faces seen without the
# screen's flip; the other way for a draw whose front faces are clockwise), the depth test (2),
# the depth write (3), the depth bias (bits 4-5: 1 a shadow map's, pushed back; 2 a decal's,
# pulled forward), the depth comparison (bits 6-8), the front faces culled in place of the back
# ones (bit 9).
pub fn stateBits(p Pass, call DrawCall) i64:
	withDepth = p.depth != noTarget
	r = call.raster
	cull = 1 if call.cull else 0
	front = (0 if p.color == screenTarget else 1) ^ (1 if r.frontClockwise else 0)
	test = 1 if call.depthTest and withDepth else 0
	write = 1 if call.depthWrite and withDepth else 0
	bias = 1 if call.depthBias else 2 if call.decal else 0
	cullFront = 1 if r.cullFront else 0
	cull | front << 1 | test << 2 | write << 3 | bias << 4 | r.depthCompare << 6 | cullFront << 9

# the faces state bits cull: 1 the back ones, 3 the front ones, 0 or 2 none
pub fn cullOf(bits i64) i64:
	bits & 1 | bits.bits(9, 1) << 1

# the formats of a pass's color targets after the first, 8 bits each from the lowest
pub fn packFormats(formats i64[]) i64:
	packed = 0
	for i, f in formats:
		packed |= f << (i * 8)
	packed

# the formats packFormats packed
pub fn unpackFormats(packed i64) i64[]:
	formats = []
	rest = packed
	while rest != 0:
		formats.push(rest & 0xFF)
		rest >>= 8
	formats

# a draw's viewport in a w x h target: its own, else the whole target
pub fn viewportOf(r RasterState, w i64, h i64) Viewport:
	r.viewport ?? Viewport(x = 0.0, y = 0.0, width = f32(w), height = f32(h))

# a draw's scissor in a w x h target: its own, else the whole target
pub fn scissorOf(r RasterState, w i64, h i64) Scissor:
	r.scissor ?? Scissor(x = 0, y = 0, width = w, height = h)

# the color targets of a pass into one (a texture, the screen) or none
pub fn colorsOf(color i64) i64[]:
	[] if color == noTarget else [color]

# Whether a draw sets the viewport and scissor: it has its own, or the draw before had (then the
# whole target's again). Noted for the next draw.
pub fn drawSetsRects(mut s DeviceState, call DrawCall) bool:
	own = call.raster.viewport != none or call.raster.scissor != none
	sets = own or s.pass.rects
	s.pass.rects = own
	sets

# the most color targets a pass draws into
pub mostColorTargets = 8

# the constant and the slope of a depth bias kind (bits 4-5 of the state)
pub fn depthBiasOf(kind i64) (f32, f32):
	if kind == 1: return (2.0, 4.0)
	if kind == 2: return (-2.0, -2.0)
	(0.0, 0.0)

# the pixels of a capture as r, g, b, a from the screen's (b, g, r on a screen of BGRA; its alpha
# opaque: the screen shows no see-through, its alpha is what blending left)
pub fn rgbaOf(move screen u8[], pixels i64) u8[]:
	rgba = screen
	swap = screenFormat == fmtBgra8
	for i in 0..pixels:
		if swap:
			blue = rgba[i * 4]
			rgba[i * 4] = rgba[i * 4 + 2]
			rgba[i * 4 + 2] = blue
		rgba[i * 4 + 3] = 255
	rgba

# The pass into the color targets (textures, up to mostColorTargets; the screen alone; or none)
# and the depth target (a texture or none): their size, formats and samples, open. Targets of
# different sizes or samples stop the program.
pub fn openPass(s DeviceState, colors i64[], depth i64) Pass:
	if colors.len > mostColorTargets:
		fail("rhi: a pass into {colors.len} color targets (at most {mostColorTargets})")
	p = noPass()
	p.active = true
	p.color = colors[0] if not colors.isEmpty else noTarget
	p.depth = depth
	p.screenTouched = s.pass.screenTouched or p.color == screenTarget
	if p.color == screenTarget:
		p.width = s.width
		p.height = s.height
		p.colorFormat = screenFormat
		return p
	extra = []
	for i, id in colors:
		t = s.textures[id]
		if i == 0:
			p.colorFormat = t.format
		else:
			p.extraColors.push(id)
			extra.push(t.format)
		p.takeSize(t)
	p.extraFormats = packFormats(extra)
	if depth >= 0:
		t = s.textures[depth]
		p.depthFormat = t.format
		p.takeSize(t)
	p

# a pass's size and samples those of a target of it, the same as those of the targets before
fn takeSize(mut p Pass, t Texture):
	if p.width > 0 and (t.width != p.width or t.height != p.height or t.samples != p.samples):
		fail("rhi: a pass's targets of different sizes or samples")
	p.width = t.width
	p.height = t.height
	p.samples = t.samples

# Whether a draw draws anything (its counts are not 0), counted when it does. A draw outside a
# pass stops the program.
pub fn drawReady(mut s DeviceState, call DrawCall) bool:
	if not s.pass.active:
		fail("rhi: a draw outside a pass")
	if call.indirect < 0 and (call.count <= 0 or call.instances <= 0) or
		call.indirect >= 0 and call.drawCount <= 0:
		return false
	s.stats.draws += 1
	true

# Whether a draw binds its pipeline and its index buffer (0 none): each when it differs from what
# the pass's last draw bound, which it becomes. Counted.
pub fn drawBinds(mut s DeviceState, pipeline i64, index i64) (bool, bool):
	bindsPipeline = pipeline != s.pass.pipeline
	s.pass.pipeline = pipeline
	s.stats.pipelineBinds += 1 if bindsPipeline else 0
	s.stats.pipelinesSkipped += 0 if bindsPipeline else 1
	if index == 0: return (bindsPipeline, false)
	bindsIndex = index != s.pass.index
	s.pass.index = index
	s.stats.indexBinds += 1 if bindsIndex else 0
	s.stats.indexSkipped += 0 if bindsIndex else 1
	(bindsPipeline, bindsIndex)

# The draw recorded as its kind is: of the call's counts or of a buffer of commands, indexed when
# it names an index buffer.
pub fn recordDraw<B Backend>(mut b B, call DrawCall):
	indexed = call.indexBuffer != 0
	if call.indirect >= 0:
		b.drawIndirect(call, indexed)
	else:
		b.drawDirect(call, indexed)
