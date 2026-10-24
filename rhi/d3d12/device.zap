# The GPU through Direct3D 12 (the baseline Windows 11 ships, no Agility SDK): a DXGI factory,
# the adapter (a discrete GPU first: the high-performance one), the device, its one direct queue,
# a flip-model swapchain (tearing allowed when frames do not wait for the screen; without a window,
# render targets of its format that nothing presents: offscreen), and the frames
# in flight (two: the CPU records one while the GPU draws the other), each with a command list
# for the uploads it records anywhere in the frame (executed first), one for its passes, a ring
# of upload memory for what it hands the GPU once, and the objects it retired, freed once its
# fence says the GPU is done with it. Descriptors live in heaps: the textures' views in one the
# shaders do not see, copied per draw into a shader-visible ring; samplers in tables made once;
# the texture arrays' views and samplers in ranges of the shader-visible heaps kept from draw to
# draw (taken and given back by first fit, as memory is).

import win
import rhi.core

swapBuffers = 3
srvHeapSize = 131_072   # the shader-visible views: a ring for each frame in flight, then the kept ranges
ringViews = 32_768   # a frame's ring of views
samplerHeapSize = 2048   # the most a shader-visible sampler heap may hold
cpuViews = 16_384   # the textures' views
targetViews = 1024   # render target and depth views

# a frame in flight
pub type Frame:
	commands i64
	commandAllocator i64
	uploads i64
	uploadAllocator i64
	uploading bool   # the uploads list was begun this frame
	fenceValue i64   # what the fence reaches when the frame is done
	viewsUsed i64   # shader-visible views used this frame
	timestamps i64 = 0   # its heap of timestamps (ZAP_RUN=gputime), 0 none...
	readback i64 = 0   # ...the buffer they are resolved into and its address
	stamps i64 = 0

# retired ranges of the kept views and of the samplers (handle: the first slot, size: the count)
retiredViewRange = core.retiredOwn
retiredSamplerRange = core.retiredOwn + 1

pub type Device:
	state core.DeviceState   # what both backends keep the same way (core's device.zap)
	factory i64
	adapter i64
	device i64
	queue i64
	fence i64
	fenceEvent i64
	fenceValue i64
	swapchain i64   # 0: no window, the frames drawn offscreen
	tearing bool   # the swapchain may show a frame before the screen's refresh
	backBuffers i64[]
	backBuffer i64   # the frame's back buffer index, -1 before the frame begins
	blockAddresses i64[]   # per memory block: its buffer's GPU address (0 for a heap)
	vsync bool
	frames Frame[]   # the API's side of the frames in flight (the state's frames the rest)
	programs ProgramRecord[]   # the API's side of the programs (the state's the rest)
	samplerTables {i64: i64}   # a draw's samplers (their ids packed): the table's first slot
	slots core.Memory   # the shader-visible heaps' ranges kept from draw to draw: the views' (block 0, past the rings), the samplers' (block 1)
	srvHeap i64   # shader-visible views
	srvCpuStart i64
	srvGpuStart i64
	samplerHeap i64
	samplerCpuStart i64
	samplerGpuStart i64
	viewHeap i64   # the textures' views (not shader-visible)
	viewCpuStart i64
	rtvHeap i64
	rtvStart i64
	dsvHeap i64
	dsvStart i64
	viewSize i64   # a CBV/SRV/UAV descriptor's size
	samplerSize i64
	rtvSize i64
	dsvSize i64
	destroyViews i64[]
	destroyRtvs i64[]
	destroyDsvs i64[]
	uploadTouched i64[]   # textures (as ids) and buffer blocks (as -1 - block) left for copies in the uploads list
	lastTable i64   # the last draw's view table (its first slot) and what it holds
	lastTableIds i64[]
	boundVertices i64[]   # what the pass's last draw bound: its layout, zero slot, handles and offsets
	boundViews i64   # the view and sampler tables the pass's last draw set (-1 none)
	boundSamplers i64
	boundParams i64 = 0   # the parameters' address the pass's last draw set (0 none)
	boundStorage i64[] = []   # the storage buffers' addresses it set
	boundArrays i64[] = []   # the texture arrays' tables it set (GPU handles: views, samplers, per array)
	# what a draw's bindings are made of, kept from draw to draw (a draw makes no list): the vertex
	# buffers' views
	views VertexBufferView[] = []
	device1 i64 = 0   # the device as ID3D12Device1 (pipeline libraries), 0 none
	library i64 = 0   # the pipeline library of the last run's pipelines, 0 none
	mipProgram i64 = -1   # the program mip levels are made with (mips/), -1 until needed
	mipSampler i64 = -1   # its sampler's slot (linear, clamped), -1 until needed
	mipTarget i64 = -1   # the render target view's slot its draws write their level's view into
	drawSignatures i64[] = []   # the command signatures of indirect draws: of vertices, of indices (made when first needed)
	stored StoredPipeline[] = []   # the pipelines made or loaded in this run, by name

	# Some of the calls rhi/core's logic makes through this backend (core's Backend); the others are
	# methods beside the code they use.
	# shared with the other backend
	pub mut fn deviceState() mut ref core.DeviceState:
		mut ref state

	# a sampler is made where a draw's table holds it: the handle is its description's index
	pub mut fn newSampler(desc core.SamplerDesc) i64:
		_ = desc
		state.samplers.len

	pub mut fn writeTimestamp(query i64):
		listEndQuery(frames[state.frame].commands, frames[state.frame].timestamps, 2, query)

	# the frame's fence waited for, its shader-visible views emptied
	pub mut fn flushUploads():
		self.submitUploads()
		self.waitIdle()

	pub mut fn waitForFrame(f i64):
		self.waitFor(frames[f].fenceValue)
		frames[f].viewsUsed = 0

	pub mut fn destroyBlock(memory i64):
		win.release(memory)

	# the first n timestamps of frame slot f (its fence waited for), as they were resolved
	pub mut fn frameTicks(f i64, n i64) i64[]:
		bytes = win.memoryAt(frames[f].stamps, n * 16).bytes(0, n * 16)
		ticks = []
		for i in 0..n * 2:
			ticks.push(i64(bytes.loadWord(i * 8)))
		ticks

	# A new library of this run's pipeline states serialized (none of another run's left in it), []
	# when the device has no libraries.
	pub mut fn pipelineBlob() u8[]:
		blob u8[] = []
		if library != 0:
			fresh = self.newLibrary([])
			if fresh != 0:
				for s in stored:
					libraryStorePipeline(fresh, s.name, s.pipeline)
				n = libraryGetSerializedSize(fresh)
				blob = zeros(n.max(1))
				if librarySerialize(fresh, blob, n) >= 0:
					blob.truncate(n)
				else:
					blob = []
				win.release(fresh)
		blob

# a pipeline state as a library knows it: its name (UTF-16, ending in 0) and the object
pub type StoredPipeline:
	name u8[]
	pipeline i64

pub fn newDevice(hwnd i64, hinstance i64, width i64, height i64) Device:
	_ = hinstance
	check(CreateDXGIFactory2(0, iidFactory6, out factory), "CreateDXGIFactory2")
	bindFactory(factory)
	adapter, device = pickDevice(factory)
	bindDevice(device)
	check(
		deviceCreateCommandQueue(device, CommandQueueDesc(), iidQueue, out queue),
		"CreateCommandQueue"
	)
	bindQueue(queue)
	check(deviceCreateFence(device, 0, 0, iidFence, out fence), "CreateFence")
	bindFence(fence)
	allowed u32 = 0
	tearing = factoryCheckFeatureSupport(factory, 0, out allowed, 4) >= 0 and allowed != 0   # DXGI_FEATURE_PRESENT_ALLOW_TEARING
	d = emptyDevice()
	d.factory = factory
	d.adapter = adapter
	d.device = device
	d.queue = queue
	d.fence = fence
	d.fenceEvent = win.CreateEventA(0, false, false, 0)
	d.tearing = tearing
	d.state.width = width
	d.state.height = height
	d.state.flipAfterParams = true
	d.state.pipelineStore = core.openPipelineStore("d3d12")
	d.openLibrary()
	d.descriptorHeaps()
	if hwnd != 0:
		d.newSwapchain(hwnd)
	else:
		backBuffers(d)
	d.state.timer = core.newGpuTimer()
	if d.state.timer.every > 0:
		check(queueGetTimestampFrequency(queue, out frequency), "GetTimestampFrequency")
		d.state.nsPerTick = 1000000000.0 / frequency.max(1)
	loop core.framesInFlight:
		d.frames.push(d.newFrame())
		if d.state.timer.every > 0:
			d.timestampHeap(d.frames.len - 1)
	core.addFrames(d)
	core.placeholderTextures(d)
	d

# the adapter to draw with (the high-performance one first: a discrete GPU) and its device
fn pickDevice(factory i64):
	index = 0
	loop:
		if factoryEnumAdapterByGpuPreference(factory, index, 2, iidAdapter1, out adapter) < 0:
			break   # DXGI_ERROR_NOT_FOUND: none left
		bindExtern(adapterGetDesc1, win.method(adapter, 10))
		desc = AdapterDesc1()
		adapterGetDesc1(adapter, desc)
		if (desc.flags & 2) == 0 and D3D12CreateDevice(adapter, 0xb000, iidDevice, out device) >= 0:
			return (adapter, device)   # feature level 11_0
		win.release(adapter)
		index += 1
	fail("rhi: no GPU with Direct3D 12")
	(0, 0)

fn newHeap(d Device, kind i64, count i64, shaderVisible bool):
	check(deviceCreateDescriptorHeap(
		d.device,
		DescriptorHeapDesc(kind = u32(kind), count = u32(count), flags = u32(1 if shaderVisible else 0)),
		iidDescriptorHeap,
		out heap), "CreateDescriptorHeap")
	heap

# the descriptor heaps: shader-visible views and samplers, the textures' views, render target
# and depth views (the swapchain's first)
fn descriptorHeaps(mut d Device):
	d.srvHeap = d.newHeap(0, srvHeapSize, true)
	d.srvCpuStart = heapCpuStart(d.srvHeap)
	d.srvGpuStart = heapGpuStart(d.srvHeap)
	d.samplerHeap = d.newHeap(1, samplerHeapSize, true)
	d.samplerCpuStart = heapCpuStart(d.samplerHeap)
	d.samplerGpuStart = heapGpuStart(d.samplerHeap)
	d.viewHeap = d.newHeap(0, cpuViews, false)
	d.viewCpuStart = heapCpuStart(d.viewHeap)
	d.rtvHeap = d.newHeap(2, targetViews, false)
	d.rtvStart = heapCpuStart(d.rtvHeap)
	d.dsvHeap = d.newHeap(3, targetViews, false)
	d.dsvStart = heapCpuStart(d.dsvHeap)
	d.viewSize = deviceGetDescriptorHandleIncrementSize(d.device, 0)
	d.samplerSize = deviceGetDescriptorHandleIncrementSize(d.device, 1)
	d.rtvSize = deviceGetDescriptorHandleIncrementSize(d.device, 2)
	d.dsvSize = deviceGetDescriptorHandleIncrementSize(d.device, 3)
	views = srvHeapSize - ringViews * core.framesInFlight
	d.slots = core.Memory(typeFlags = [], blocks = [
		core.Block(memory = 0, typeIndex = 0, size = views, mapped = 0, free = [core.Range(offset = 0, size = views)]),
		core.Block(
			memory = 0,
			typeIndex = 1,
			size = samplerHeapSize,
			mapped = 0,
			free = [core.Range(offset = 0, size = samplerHeapSize)]
	)])
	d.destroyViews = slotsDown(0, cpuViews)
	d.destroyRtvs = slotsDown(swapBuffers, targetViews)
	d.destroyDsvs = slotsDown(0, targetViews)

# the slots from `first` to below `end`, the first last (taken first)
fn slotsDown(first i64, end i64):
	out = []
	i = end - 1
	while i >= first:
		out.push(i)
		i -= 1
	out

# a slot taken from a free list
fn takeSlot(mut free i64[], what str):
	free.pop() ?? fail("rhi: out of {what}")

# ---------- the swapchain ----------

fn swapchainFlags(d Device):
	2048 if d.tearing else 0   # DXGI_SWAP_CHAIN_FLAG_ALLOW_TEARING

fn newSwapchain(mut d Device, hwnd i64):
	desc = SwapChainDesc1(
		width = u32(d.state.width.max(1)),
		height = u32(d.state.height.max(1)),
		format = u32(dxgiFormat(core.screenFormat)),
		bufferCount = u32(swapBuffers),
		flags = u32(d.swapchainFlags()))
	check(
		factoryCreateSwapChainForHwnd(d.factory, d.queue, hwnd, desc, 0, 0, out swapchain1),
		"CreateSwapChainForHwnd"
	)
	factoryMakeWindowAssociation(d.factory, hwnd, 2)   # DXGI_MWA_NO_ALT_ENTER
	d.swapchain = queryInterface(swapchain1, iidSwapchain3, "IDXGISwapChain3")
	win.release(swapchain1)
	bindSwapchain(d.swapchain)
	backBuffers(d)

# the swapchain's buffers (offscreen ones without it) and their render target views (the first
# slots of the heap)
fn backBuffers(mut d Device):
	d.backBuffers = []
	for i in 0..swapBuffers:
		buffer = d.offscreenBuffer() if d.swapchain == 0 else d.swapchainBuffer(i)
		d.backBuffers.push(buffer)
		deviceCreateRenderTargetView(d.device, buffer, 0, d.rtvHandle(i))

fn swapchainBuffer(d Device, i i64):
	check(swapchainGetBuffer(d.swapchain, i, iidResource, out buffer), "IDXGISwapChain::GetBuffer")
	buffer

# a render target of the screen's size and format, in the state a swapchain's buffer starts in
fn offscreenBuffer(d Device):
	desc = ResourceDesc(
		dimension = 3,
		width = d.state.width,
		height = u32(d.state.height),
		depthOrArraySize = 1,
		mipLevels = 1,
		format = u32(dxgiFormat(core.screenFormat)),
		sampleCount = 1,
		flags = 1   # ALLOW_RENDER_TARGET
	)
	check(
		deviceCreateCommittedResource(d.device, HeapProperties(kind = 1), 0, desc, statePresent, 0, iidResource, out buffer),
		"CreateCommittedResource (an offscreen buffer)"
	)
	buffer

# the swapchain's buffers made again for the window's size (the GPU idle, the old ones let go)
fn resizeSwapchain(mut d Device):
	d.waitIdle()
	for mut b in d.backBuffers:
		win.release(b)
	d.backBuffers = []
	if d.state.width == 0 or d.state.height == 0:
		d.state.stale = true
		return
	if d.swapchain != 0:
		check(
			swapchainResizeBuffers(d.swapchain, 0, d.state.width, d.state.height, 0, d.swapchainFlags()),
			"IDXGISwapChain::ResizeBuffers"
		)
	backBuffers(d)
	d.state.stale = false

# whether frames wait for the screen's refresh
pub fn setVsync(mut d Device, on bool):
	d.vsync = on

# Direct3D 12 draws into the window it was made for (Windows never takes a window back)
pub fn setWindow(mut d Device, hwnd i64, hinstance i64):
	_ = d
	_ = hwnd
	_ = hinstance
	fail("rhi: Direct3D 12 keeps the window it was made for")

fn rtvHandle(d Device, slot i64):
	d.rtvStart + slot * d.rtvSize

fn dsvHandle(d Device, slot i64):
	d.dsvStart + slot * d.dsvSize

# ---------- frames ----------

fn newFrame(d Device):
	check(
		deviceCreateCommandAllocator(d.device, 0, iidAllocator, out commandAllocator),
		"CreateCommandAllocator"
	)
	check(
		deviceCreateCommandAllocator(d.device, 0, iidAllocator, out uploadAllocator),
		"CreateCommandAllocator"
	)
	bindAllocator(commandAllocator)
	check(
		deviceCreateCommandList(d.device, 0, 0, commandAllocator, 0, iidCommandList, out commands),
		"CreateCommandList"
	)
	check(
		deviceCreateCommandList(d.device, 0, 0, uploadAllocator, 0, iidCommandList, out uploads),
		"CreateCommandList"
	)
	bindCommandList(commands)
	# made open: closed until the frame begins
	check(listClose(commands), "Close")
	check(listClose(uploads), "Close")
	Frame(
		commands,
		commandAllocator,
		uploads,
		uploadAllocator,
		uploading = false,
		fenceValue = 0,
		viewsUsed = 0
	)

# Begins a frame: the swapchain made again when it no longer fits, the frame's pass commands
# begun. False when there is nothing to draw into (a minimized window): the frame is skipped.
pub fn beginFrame(mut d Device) bool:
	if d.state.stale:
		d.resizeSwapchain()
		if d.state.stale: return false
	f = d.state.frame
	# offscreen, a buffer a frame in flight: its last frame is done
	d.backBuffer = swapchainGetCurrentBackBufferIndex(d.swapchain) if d.swapchain != 0 else f
	check(allocatorReset(d.frames[f].commandAllocator), "ID3D12CommandAllocator::Reset")
	cmd = d.frames[f].commands
	check(listReset(cmd, d.frames[f].commandAllocator, 0), "ID3D12GraphicsCommandList::Reset")
	listSetDescriptorHeaps(cmd, 2, [d.srvHeap, d.samplerHeap])
	d.state.startFrame()
	d.lastTableIds.clear()
	true

# the frame's upload commands, begun on first use
fn uploadCommands(mut d Device):
	f = d.state.frame
	if not d.frames[f].uploading:
		check(allocatorReset(d.frames[f].uploadAllocator), "ID3D12CommandAllocator::Reset")
		check(
			listReset(d.frames[f].uploads, d.frames[f].uploadAllocator, 0),
			"ID3D12GraphicsCommandList::Reset"
		)
		d.frames[f].uploading = true
	d.frames[f].uploads

# the GPU's work waited for until the fence reaches `value`
fn waitFor(d Device, value i64):
	if fenceGetCompletedValue(d.fence) < value:
		check(fenceSetEventOnCompletion(d.fence, value, d.fenceEvent), "SetEventOnCompletion")
		win.WaitForSingleObject(d.fenceEvent, -1)

# the uploads list closed (what it left for copies put back to rest) and executed
fn submitUploads(mut d Device):
	f = d.state.frame
	if not d.frames[f].uploading: return
	cmd = d.frames[f].uploads
	d.restUploads(cmd)
	check(listClose(cmd), "ID3D12GraphicsCommandList::Close (uploads)")
	queueExecuteCommandLists(d.queue, 1, [cmd])
	d.frames[f].uploading = false

# Ends a frame: its passes closed, the textures drawn into back at rest, the back buffer made
# presentable (from the state the frame left it in), the uploads and the passes executed, the
# frame shown; then the next frame's slot made ready (core's finishFrame).
fn presentFrame(mut d Device, backBufferState i64):
	f = d.state.frame
	cmd = d.frames[f].commands
	d.transitions(cmd, d.state.restTextures())
	if backBufferState != statePresent:
		transition(cmd, d.backBuffers[d.backBuffer], backBufferState, statePresent)
	n = d.state.frames[f].timed.len
	if n > 0:
		listResolveQueryData(cmd, d.frames[f].timestamps, 2, 0, n * 2, d.frames[f].readback, 0)   # D3D12_QUERY_TYPE_TIMESTAMP
	check(listClose(cmd), "ID3D12GraphicsCommandList::Close")
	d.submitUploads()
	queueExecuteCommandLists(d.queue, 1, [cmd])
	if d.swapchain != 0:
		d.present()
	d.fenceValue += 1
	check(queueSignal(d.queue, d.fence, d.fenceValue), "ID3D12CommandQueue::Signal")
	d.frames[f].fenceValue = d.fenceValue
	d.backBuffer = -1
	core.finishFrame(d)

# the frame shown (waiting for the screen's refresh when vsync is on)
fn present(d Device):
	hr = swapchainPresent(d.swapchain, 1, 0) if d.vsync else swapchainPresent(   # DXGI_PRESENT_ALLOW_TEARING
		d.swapchain,
		0,
		0x200 if d.tearing else 0
	)
	if hr < 0:
		reason = deviceGetDeviceRemovedReason(d.device)
		fail(
			"rhi: Present failed ({win.hresultText(hr)}, device removed: {win.hresultText(reason)})"
		)

pub fn endFrame(mut d Device):
	d.endPass()
	d.presentFrame(stateRenderTarget if d.state.pass.screenTouched else statePresent)

pub fn waitIdle(d Device):
	if d.device == 0: return
	# the next value: the next frame signals it again, which keeps the values in order
	idle = d.fenceValue + 1
	check(queueSignal(d.queue, d.fence, idle), "ID3D12CommandQueue::Signal")
	d.waitFor(idle)

# a device that is not made yet: what the engine holds until its window opens
pub fn emptyDevice() Device:
	Device(
		state = core.noDeviceState(),
		factory = 0,
		adapter = 0,
		device = 0,
		queue = 0,
		fence = 0,
		fenceEvent = 0,
		fenceValue = 0,
		swapchain = 0,
		tearing = false,
		backBuffers = [],
		backBuffer = -1,
		blockAddresses = [],
		vsync = true,
		frames = [],
		programs = [],
		samplerTables = {},
		slots = core.Memory(typeFlags = [], blocks = []),
		srvHeap = 0,
		srvCpuStart = 0,
		srvGpuStart = 0,
		samplerHeap = 0,
		samplerCpuStart = 0,
		samplerGpuStart = 0,
		viewHeap = 0,
		viewCpuStart = 0,
		rtvHeap = 0,
		rtvStart = 0,
		dsvHeap = 0,
		dsvStart = 0,
		viewSize = 0,
		samplerSize = 0,
		rtvSize = 0,
		dsvSize = 0,
		destroyViews = [],
		destroyRtvs = [],
		destroyDsvs = [],
		uploadTouched = [], lastTable = 0, lastTableIds = [], boundVertices = [], boundViews = -1, boundSamplers = -1)

# ---------- formats and states ----------

pub stateCommon = 0
pub statePresent = 0   # the same as common
pub stateRenderTarget = 4
pub stateUnorderedAccess = 8
pub stateDepthWrite = 0x10
pub stateShaderResource = 0xC0   # read by any stage
pub stateBufferRead = 0x2C3   # vertices, indices, constants, indirect commands, read by any stage
pub stateCopyDest = 0x400
pub stateCopySource = 0x800
pub stateResolveDest = 0x1000
pub stateResolveSource = 0x2000
pub stateGenericRead = 0xAC3   # an upload heap's state

# the DXGI format of one of the RHI's (a depth format's for its depth view)
fn dxgiFormat(format i64):
	if format == core.fmtRgba8: return 28
	if format == core.fmtRgba8Srgb: return 29
	if core.isBlockFormat(format):
		return 71 if format == core.fmtBc1
			else 72 if format == core.fmtBc1Srgb
			else 77 if format == core.fmtBc3
			else 78 if format == core.fmtBc3Srgb
			else 80 if format == core.fmtBc4
			else 83 if format == core.fmtBc5
			else 98 if format == core.fmtBc7
			else 99
	if format == core.fmtBgra8: return 87
	if format == core.fmtBgra8Srgb: return 91
	if format == core.fmtRgba16Float: return 10
	if format == core.fmtRg16Float: return 34
	if format == core.fmtR11G11B10Float: return 26
	if format == core.fmtRgb10A2: return 24
	if format == core.fmtR8: return 61
	if format == core.fmtRg8: return 49
	if format == core.fmtD32: return 40
	if format == core.fmtD16: return 55
	if format == core.fmtD24S8: return 45
	if format == core.fmtUndefined: return 0
	# the 32-bit vertex formats: uint, sint, float of 1 to 4 components
	for rows in 1..5:
		k = (rows - 1) * 3
		if format == core.fmtR32Uint + k: return [42, 17, 7, 3][rows - 1]
		if format == core.fmtR32Sint + k: return [43, 18, 8, 4][rows - 1]
		if format == core.fmtR32Float + k: return [41, 16, 6, 2][rows - 1]
	fail("rhi: no DXGI format for {format}")
	0

# a depth texture's resource format (typeless: it is drawn as depth and read as a color)
fn typelessFormat(format i64):
	39 if format == core.fmtD32 else 53 if format == core.fmtD16 else 44 if format == core.fmtD24S8
		else dxgiFormat(format)

# the format a shader reads a texture as
fn readFormat(format i64):
	41 if format == core.fmtD32 else 56 if format == core.fmtD16 else 46 if format == core.fmtD24S8
		else dxgiFormat(format)

# a transition barrier recorded: the whole resource from one state to another
fn transition(cmd i64, resource i64, before i64, after i64):
	if before != after:
		listResourceBarrier(
			cmd,
			1,
			[ResourceBarrier(resource, before = u32(before), after = u32(after))]
		)

# ---------- the passes' GPU time ----------

# frame slot f's heap of timestamps and the readback buffer they are resolved into (mapped)
fn timestampHeap(mut d Device, f i64):
	check(
		deviceCreateQueryHeap(d.device, QueryHeapDesc(count = u32(core.mostTimedPasses * 2)), iidQueryHeap, out heap),
		"CreateQueryHeap"
	)
	desc = ResourceDesc(
		dimension = 1,
		width = core.mostTimedPasses * 16,
		height = 1,
		depthOrArraySize = 1,
		mipLevels = 1,
		format = 0,
		layout = 1
	)
	check(
		deviceCreateCommittedResource(d.device, HeapProperties(kind = 3), 0, desc, stateCopyDest, 0, iidResource, out readback),
		"CreateCommittedResource (timestamps)"
	)
	d.frames[f].timestamps = heap
	d.frames[f].readback = readback
	d.frames[f].stamps = mapResource(readback)

# ---------- the pipeline library ----------

# The pipeline library of what the last run left, its pipelines loaded from it rather than
# compiled: one the driver refuses (another driver's or adapter's, damaged) is replaced by an
# empty one; none when the device has no libraries.
fn openLibrary(mut d Device):
	d.device1 = win.queryInterface(d.device, iidDevice1)
	if d.device1 == 0: return
	bindExtern(deviceCreatePipelineLibrary, win.method(d.device1, 44))
	d.library = d.newLibrary(d.state.pipelineStore.blob)
	if d.library == 0:
		d.library = d.newLibrary([])

# a pipeline library holding the bytes (which stay alive and unchanged while it lives), 0 when refused
fn newLibrary(d Device, blob u8[]):
	library = 0
	if deviceCreatePipelineLibrary(d.device1, blob, blob.len, iidPipelineLibrary, out made) >= 0:
		library = made
		bindLibrary(library)
	library
