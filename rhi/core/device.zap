# What both backends keep the same way, and the logic over it written once: the frames in
# flight and their rings, the buffers, textures, samplers and programs as the RHI names them (by
# ids), the pass being drawn, the vertex layouts, the draws' counts, the objects retired until
# their frame is done on the GPU. A backend's device holds a DeviceState and makes the API calls
# this logic needs through the Backend bound: each backend's are compiled into it, with no
# dispatch at run time. Nothing here calls an API itself.

pub framesInFlight = 2   # the CPU records one frame while the GPU draws the other
pub ringSize = 1_048_576   # a frame's ring: 1 MB, grown when a frame wants more

# the format of the screen's images on both backends
pub screenFormat = fmtBgra8

# ZAP_RUN's `gpuinfo`, which both backends read
pub fn gpuInfoWord() TraceWord:
	TraceWord(
		"gpuinfo",
		"prints what the pipelines cost when saved, and on Vulkan what the device offers"
	)

# kinds of retired objects both backends have (a backend numbers its own from retiredOwn)
pub retiredBuffer = 1
pub retiredImage = 2   # the image and its memory
pub retiredView = 3
pub retiredColorView = 4   # Direct3D 12's render target view
pub retiredDepthView = 5   # Direct3D 12's depth view
pub retiredOwn = 6   # a backend's own kinds start here

# The calls the logic here needs a backend to make, each the backend's API's way of doing it.
pub bound Backend:
	# the state it keeps the same way as the other backend
	fn deviceState(mut self Backend) mut ref DeviceState
	# a buffer's API object and memory (it becomes the buffers' next id)
	fn newBuffer(mut self Backend, size i64, usage i64, hostVisible bool) Buffer
	# n bytes copied from the ring (its handle, the offset there) into a buffer at `offset`, before the frame's passes
	fn copyFromRing(mut self Backend, ring i64, ringOffset i64, id i64, offset i64, n i64)
	# a texture's API objects and memory (it becomes the textures' next id; its sampler is set after)
	fn newTexture(mut self Backend, desc TextureDesc) Texture
	# a level (w x h) of a texture's layer replaced by the bytes, as its format lays them out
	fn copyLevel(mut self Backend, id i64, level i64, layer i64, w i64, h i64, bytes u8[])
	# a sampler of the description: the handle a texture names it by
	fn newSampler(mut self Backend, desc SamplerDesc) i64
	# a program's API objects (it becomes the programs' next id); what it keeps of the code it may move out
	fn newProgram(mut self Backend, mut code ProgramCode)
	# a compute program's API objects, its pipeline made (it becomes the programs' next id)
	fn newCompute(mut self Backend, mut code ComputeCode)
	# a program's pipeline for a key, the variant the pipeline store knows it as
	fn newPipeline(
		mut self Backend,
		program i64,
		key PipelineKey,
		layout VertexLayout,
		variant PipelineVariant
	) PipelineEntry
	# a draw of the call's counts into the frame's commands: through the index buffer bound, or of
	# the vertices in order
	fn drawDirect(mut self Backend, call DrawCall, indexed bool)
	# a draw of the commands in the call's buffer (drawCount, or as many as its count buffer says)
	fn drawIndirect(mut self Backend, call DrawCall, indexed bool)
	# a timestamp written into the frame's queries
	fn writeTimestamp(mut self Backend, query i64)
	# the uploads recorded so far run and waited for (the ring's staged bytes are done with)
	fn flushUploads(mut self Backend)
	# the GPU's work from frame slot f's last use waited for
	fn waitForFrame(mut self Backend, f i64)
	# the first n timestamps of frame slot f (its work done), [] when they cannot be read
	fn frameTicks(mut self Backend, f i64, n i64) i64[]
	# a retired object freed (its memory range is given back after)
	fn destroyObject(mut self Backend, r Retired)
	# a block of memory given back to the driver
	fn destroyBlock(mut self Backend, memory i64)
	# the driver's cache of the pipelines made, for the pipeline store
	fn pipelineBlob(mut self Backend) u8[]

# a frame in flight as both backends keep it: its ring of memory for what it hands the GPU once
# (vertices, parameters, staging), the objects it retired, the passes it timed (two timestamps
# each, named)
pub type FrameState:
	ring i64   # a buffer id
	ringUsed i64 = 0
	ringShared bool = false   # something other than uploads reads the ring this frame (draws' parameters, vertices)
	ringPlaced i64 = 0   # the bytes the frame placed in its rings, those it outgrew included
	retired Retired[] = []
	timed str[] = []

# what both backends' devices keep the same way
pub type DeviceState:
	width i64
	height i64
	stale bool = false   # the swapchain no longer fits the window
	frames FrameState[] = []
	frame i64 = 0
	timeline i64 = 0   # frames begun
	memory Memory
	buffers Buffer[] = []
	textures Texture[] = []
	samplers SamplerRecord[] = []
	programs ProgramState[] = []
	pass Pass = noPass()
	held i64[] = []   # the textures out of rest (barriers.zap)
	layouts VertexLayout[] = []
	noLayout VertexLayout = VertexLayout(bindings = [], attributes = [])   # the layout of a draw that reads no vertex buffer
	placeholders i64[] = []   # the textures read where a draw names none: white, a white array
	zeros i64 = -1   # a buffer of zeros for the inputs a layout lacks, -1 until needed
	paramsCopies i64[] = []   # the frame's copies of parameters for later draws: buffer handle, offset
	# Direct3D 12 draws a target with y flipped by the vertex stage: the pass's flip (1 the
	# screen, -1 a target) follows the parameters, as these words (Vulkan flips the viewport)
	flipAfterParams bool = false
	flip f32 = 1.0
	flipWords f32[] = [1.0, 0.0, 0.0, 0.0]
	stats DrawStats = DrawStats()   # the frame's so far
	lastStats DrawStats = DrawStats()   # the last frame's
	timer GpuTimer = gpuTimerOff()   # the passes' GPU time (timing.zap)
	nsPerTick f64 = 1.0   # a timestamp's nanoseconds
	passTimed bool = false   # the pass being drawn is timed (its start stamped)
	pipelineStore PipelineStore = noPipelineStore()   # the pipelines kept between runs (pipelines.zap)

# the state of a device not made yet
pub fn noDeviceState() DeviceState:
	DeviceState(width = 0, height = 0, memory = Memory(typeFlags = [], blocks = []))

# The frames in flight, each with its ring.
pub fn addFrames<B Backend>(mut b B):
	loop framesInFlight:
		ring = newBuffer(b, ringSize, ringUsage(), true)
		s mut ref DeviceState = b.deviceState()
		s.frames.push(FrameState(ring = ring))

# what a ring's buffer is read as
fn ringUsage():
	bufVertex | bufIndex | bufUniform | bufStorage | bufTransferSrc

# ---------- frames ----------

# A frame begun on the current slot: no pass yet, no parameters copied, no pass timed.
pub fn startFrame(mut s DeviceState):
	s.timeline += 1
	s.pass = noPass()
	s.paramsCopies.clear()
	s.frames[s.frame].timed.clear()

# The frame's end once its work is submitted: its counts kept as the last frame's, and the next
# frame's slot made ready (the GPU's work from its last use waited for, its retired objects freed,
# its timestamps read, its ring emptied); the pipelines written when they are due.
pub fn finishFrame<B Backend>(mut b B):
	s mut ref DeviceState = b.deviceState()
	s.lastStats = s.stats
	s.stats = DrawStats()
	s.frame = (s.frame + 1) % framesInFlight
	f = s.frame
	b.waitForFrame(f)
	destroyRetired(b, f)
	readTimestamps(b, f)
	# the ring sized for what the slot's last frame placed: made once for a frame that outgrew
	# it (not grown again by every such frame), and a burst's (a level's uploads) given back
	t mut ref DeviceState = b.deviceState()
	ring = t.frames[f].ring
	size = ringFitting(t.buffers[ring].size, t.frames[f].ringPlaced, ringSize)
	if size != t.buffers[ring].size:
		destroyBuffer(t, ring)
		fresh = newBuffer(b, size, ringUsage(), true)
		u mut ref DeviceState = b.deviceState()
		u.frames[f].ring = fresh
	v mut ref DeviceState = b.deviceState()
	v.frames[f].ringUsed = 0
	v.frames[f].ringShared = false
	v.frames[f].ringPlaced = 0
	if pipelineStoreDue(v.pipelineStore):
		savePipelineCache(b)

# the window's new size: the swapchain is made again before the next frame
pub fn resize(mut s DeviceState, width i64, height i64):
	if width != s.width or height != s.height:
		s.width = width
		s.height = height
		s.stale = true

# the screen's size as the swapchain has it
pub fn screenSize(s DeviceState) (i64, i64):
	(s.width, s.height)

# the pass being drawn
pub fn currentPass(s DeviceState) Pass:
	s.pass

# what the last frame's draws bound and uploaded, and what they skipped
pub fn drawStats(s DeviceState) DrawStats:
	s.lastStats

# ---------- retired objects ----------

# frame slot f's retired objects freed (its work is done), their memory given back
pub fn destroyRetired<B Backend>(mut b B, f i64):
	s mut ref DeviceState = b.deviceState()
	retired = move s.frames[f].retired
	for r in retired:
		b.destroyObject(r)
		if r.block >= 0:
			t mut ref DeviceState = b.deviceState()
			if release(t.memory, r.block, r.offset, r.size):
				memory = t.memory.blocks[r.block].memory
				dropBlock(t.memory, r.block)
				b.destroyBlock(memory)

# an object freed once the frames that may use it are done
pub fn retire(mut s DeviceState, r Retired):
	s.frames[s.frame].retired.push(r)

# ---------- the passes' GPU time ----------

# A timestamp written once all the work before it is done: a pass's start (`start`, its targets
# named) or its end, while the frame has room for it.
pub fn stampPass<B Backend>(mut b B, start bool):
	s mut ref DeviceState = b.deviceState()
	f = s.frame
	n = s.frames[f].timed.len
	if start:
		s.passTimed = s.timer.every > 0 and n < mostTimedPasses
		if s.passTimed:
			s.frames[f].timed.push(
				passLabel(s.pass.color, s.pass.depth, s.pass.width, s.pass.height)
			)
			b.writeTimestamp(n * 2)
	elif s.passTimed:
		s.passTimed = false
		b.writeTimestamp(n * 2 - 1)

# the timestamps of frame slot f's last frame (its work done) given to the timer
fn readTimestamps<B Backend>(mut b B, f i64):
	s mut ref DeviceState = b.deviceState()
	n = s.frames[f].timed.len
	if n == 0: return
	ticks i64[] = b.frameTicks(f, n)
	t mut ref DeviceState = b.deviceState()
	if ticks.len > 0:
		addGpuFrame(t.timer, t.frames[f].timed, ticks, t.nsPerTick)
	t.frames[f].timed.clear()

# ---------- the pipelines kept ----------

# The pipelines made so far written beside the executable (the variants and the driver's cache
# of them), when one was made since they last were; ZAP_RUN=gpu prints what they cost. A
# device not made yet (no frames) keeps nothing.
pub fn savePipelineCache<B Backend>(mut b B):
	s mut ref DeviceState = b.deviceState()
	if s.frames.isEmpty: return
	if s.pipelineStore.unsaved:
		blob u8[] = b.pipelineBlob()
		t mut ref DeviceState = b.deviceState()
		writePipelineStore(t.pipelineStore, blob)
	if gpuInfoWord().on():
		u mut ref DeviceState = b.deviceState()
		eprint(describePipelines(u.pipelineStore))
