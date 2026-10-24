# The GPU as the engine sees it: a Vulkan 1.4 instance and device (1.3 where the driver has no
# 1.4, push descriptors then from VK_KHR_push_descriptor, else sets of the frame's pools: sets.zap)
# on the window's surface, its one graphics queue (which also presents), the swapchain (without a
# window, images of its format that nothing presents: offscreen), and the frames in flight (two:
# the CPU records one while the GPU draws the other). A frame owns a command buffer for the uploads
# it records anywhere in the frame (submitted first), one for its passes, a ring of host-visible
# memory for what it hands the GPU once (vertices, parameters, staging), and the objects it
# retired, freed once the GPU is done with it.

import rhi.core

# a frame in flight
pub type Frame:
	commands i64
	uploads i64
	uploading bool   # the uploads buffer was begun this frame
	fence i64
	acquired i64   # signaled when the swapchain image is ready
	timestamps i64 = 0   # its pool of timestamps (ZAP_RUN=gputime), 0 none
	setPools i64[] = []   # without push descriptors: the pools its sets 0 come from (sets.zap)
	setPoolsUsed i64 = 0   # how many of them it drew from, the last one in use

# a texture arrays' table retired: its descriptor pool
retiredPool = core.retiredOwn

pub type Device:
	state core.DeviceState   # what both backends keep the same way (core's device.zap)
	support Support   # what the device offers past Vulkan 1.3, and whether the RHI uses it
	instance i64
	physical i64
	device i64
	queue i64
	family i64
	surface i64   # 0: no window, the frames drawn offscreen
	swapchain i64
	offscreen core.Texture[] = []   # without a window: an image a frame in flight
	swapImages i64[]
	swapViews i64[]
	presented i64[]   # per swapchain image: signaled when its drawing is done
	vsync bool
	turned bool = false   # the system turns the images (they are SUBOPTIMAL for that alone)
	frames Frame[]   # the API's side of the frames in flight (the state's frames the rest)
	image i64   # the swapchain image of the frame, -1 before it is acquired
	programs ProgramRecord[]   # the API's side of the programs (the state's the rest)
	# what the frame's commands last bound, so that a draw binds only what differs: the
	# descriptors pushed (the layout, then what each binding names), the vertex buffers (the
	# zero binding, handles and offsets)
	pushed i64[] = []
	boundArrays i64[] = []   # the texture arrays' table bound: the pipeline layout and the set
	boundVertices i64[] = []
	# what a push is made of, kept from push to push (a draw makes no list): the images and buffers
	# described, the writes that point at them; the zero binding's buffer and offset
	pushImages DescriptorImageInfo[] = []
	pushBuffers DescriptorBufferInfo[] = []
	pushWrites WriteDescriptorSet[] = []
	zeroHandles i64[] = []
	zeroOffsets i64[] = []
	pipelineCache i64   # the VkPipelineCache every pipeline is made through (0 before the device)

	# Some of the calls rhi/core's logic makes through this backend (core's Backend); the others are
	# methods beside the code they use.
	# shared with the other backend
	pub mut fn deviceState() mut ref core.DeviceState:
		mut ref state

	pub mut fn writeTimestamp(query i64):
		vkCmdWriteTimestamp(
			frames[state.frame].commands,
			stageBottom,
			frames[state.frame].timestamps,
			query
		)

	pub mut fn flushUploads():
		f = state.frame
		if not frames[f].uploading: return
		memoryBarrier(
			frames[f].uploads,
			stageTransfer,
			accessTransferWrite,
			bufferReaders,
			bufferReads
		)
		check(vkEndCommandBuffer(frames[f].uploads), "vkEndCommandBuffer")
		frames[f].uploading = false
		noHandles i64[] = []
		stages u32[] = []
		buffers = [frames[f].uploads]
		submit = SubmitInfo(
			waitCount = 0,
			waits = noHandles,
			waitStages = stages,
			bufferCount = 1,
			buffers,
			signalCount = 0,
			signals = noHandles
		)
		check(vkQueueSubmit(queue, 1, submit, 0), "vkQueueSubmit")
		_ = vkDeviceWaitIdle(device)

	pub mut fn waitForFrame(f i64):
		check(vkWaitForFences(device, 1, [frames[f].fence], 1, -1), "vkWaitForFences")

	pub mut fn destroyBlock(memory i64):
		vkFreeMemory(device, memory, 0)

	# the first n timestamps of frame slot f's pool (its fence waited for), [] when they cannot be read
	pub mut fn frameTicks(f i64, n i64) i64[]:
		ticks = zeros(n * 2)
		if vkGetQueryPoolResults(device, frames[f].timestamps, 0, n * 2, n * 16, ticks, 8, 1) != 0:   # 64-bit
			ticks.clear()
		ticks

	# the pipeline cache's data (its pipelines as the driver keeps them), [] when it gives none
	pub mut fn pipelineBlob() u8[]:
		size = Size()
		blob u8[] = []
		if pipelineCacheSize(device, pipelineCache, size, 0) == 0:
			blob = zeros(size.n.max(1))
			if vkGetPipelineCacheData(device, pipelineCache, size, blob) == 0:
				blob.truncate(size.n)
			else:
				blob = []
		blob

fn hostCopyWord():
	RunWord(
		"hostcopy",
		"Vulkan: hostcopy=on or hostcopy=off turns the host image copy of textures on or off (default: on where it fits)"
	)

pub fn newDevice(hwnd i64, hinstance i64, width i64, height i64) Device:
	instance = newInstance()
	surface = newSurface(instance, hwnd, hinstance) if hwnd != 0 else 0
	physical, family = pickDevice(instance, surface)
	support = querySupport(physical)
	device = newLogicalDevice(physical, family, support)
	bindDeviceFunctions(device, support)
	asked = hostCopyWord().value() ?? ""
	support.hostCopy = support.hostImageCopy and
		(asked == "on" or (asked != "off" and hostCopyRoomy(physical, device)))
	if support.hostCopy:
		bindExtern(vkCopyMemoryToImage, deviceFunction(device, "vkCopyMemoryToImage"))
		bindExtern(vkTransitionImageLayout, deviceFunction(device, "vkTransitionImageLayout"))
	if core.gpuInfoWord().on():
		eprint(support.describeSupport())
	vkGetDeviceQueue(device, family, 0, out queue)
	state = core.noDeviceState()
	state.memory = newMemory(physical)
	state.width = width
	state.height = height
	state.pipelineStore = core.openPipelineStore("vulkan")
	state.timer = core.newGpuTimer()
	state.nsPerTick = timestampPeriod(physical)
	d = Device(state, support, instance, physical, device, queue, family, surface,
		swapchain = 0, swapImages = [], swapViews = [], presented = [], vsync = true, frames = [], image = -1, programs = [], pipelineCache = 0)
	d.pipelineCache = d.newPipelineCache()
	if surface != 0:
		d.newSwapchain()
	else:
		d.state.stale = true   # the offscreen images made by the first frame, which records their uploads
	loop core.framesInFlight:
		d.frames.push(d.newFrame())
		if d.state.timer.every > 0:
			check(
				vkCreateQueryPool(device, QueryPoolCreateInfo(count = u32(core.mostTimedPasses * 2)), 0, out pool),
				"vkCreateQueryPool"
			)
			d.frames[len - 1].timestamps = pool
	core.addFrames(d)
	core.placeholderTextures(d)
	d

# The device's functions past Vulkan 1.1 and its push descriptors (when it has them), found
# through it (Android's loader exports none past 1.1).
fn bindDeviceFunctions(device i64, s Support):
	if s.pushDescriptor:
		push = "vkCmdPushDescriptorSet" if s.v14 else "vkCmdPushDescriptorSetKHR"
		bindExtern(vkCmdPushDescriptorSet, deviceFunction(device, push))
	bindExtern(
		vkGetDeviceImageMemoryRequirements,
		deviceFunction(device, "vkGetDeviceImageMemoryRequirements")
	)
	bindExtern(
		vkCmdDrawIndexedIndirectCount,
		deviceFunction(device, "vkCmdDrawIndexedIndirectCount")
	)
	bindExtern(vkCmdBeginRendering, deviceFunction(device, "vkCmdBeginRendering"))
	bindExtern(vkCmdEndRendering, deviceFunction(device, "vkCmdEndRendering"))
	bindExtern(vkCmdDrawIndirectCount, deviceFunction(device, "vkCmdDrawIndirectCount"))
	bindExtern(vkCmdSetCullMode, deviceFunction(device, "vkCmdSetCullMode"))
	bindExtern(vkCmdSetFrontFace, deviceFunction(device, "vkCmdSetFrontFace"))
	bindExtern(vkCmdSetDepthTestEnable, deviceFunction(device, "vkCmdSetDepthTestEnable"))
	bindExtern(vkCmdSetDepthWriteEnable, deviceFunction(device, "vkCmdSetDepthWriteEnable"))
	bindExtern(vkCmdSetDepthCompareOp, deviceFunction(device, "vkCmdSetDepthCompareOp"))
	bindExtern(vkCmdSetDepthBiasEnable, deviceFunction(device, "vkCmdSetDepthBiasEnable"))

# the address of the device's function, the program stopped when the driver has none
fn deviceFunction(device i64, name str):
	address = vkGetDeviceProcAddr(device, "{name}\0")
	if address == 0:
		fail("rhi: the driver has no {name}")
	address

fn check(result i32, what str):
	if result != 0:
		fail("rhi: {what} failed ({result})")

# ---------- instance, surface, device ----------

fn newInstance():
	app = ApplicationInfo(   # VK_API_VERSION_1_4
		name = "zap\0",
		version = 1,
		engineName = "zap\0",
		engineVersion = 1,
		apiVersion = u32(1 << 22 | 4 << 12)
	)
	surface = "{surfaceExtension()}\0"
	names = [Name(text = "VK_KHR_surface\0"), Name(text = surface)]
	info = InstanceCreateInfo(app, extensionCount = u32(names.len), extensions = names)
	result = vkCreateInstance(info, 0, out instance)
	if result == incompatibleDriver:
		fail("rhi: this system's Vulkan is 1.0, and the engine needs 1.3")
	check(result, "vkCreateInstance")
	instance

# VK_ERROR_INCOMPATIBLE_DRIVER: a loader of Vulkan 1.0 asked for a later version
incompatibleDriver = -9

# the instance's extension that makes a surface of the system's window
fn surfaceExtension():
	"VK_KHR_win32_surface"

fn newSurface(instance i64, hwnd i64, hinstance i64):
	info = Win32SurfaceCreateInfo(hinstance, hwnd)
	check(vkCreateWin32SurfaceKHR(instance, info, 0, out surface), "vkCreateWin32SurfaceKHR")
	surface

# What a device offers past Vulkan 1.3: Vulkan 1.4 itself, or on a 1.3 device the extensions
# that bring the same (push descriptors are required either way); ZAP_RUN=gpu prints it.
pub type Support:
	name str
	api i64   # the device's Vulkan version, as VK_MAKE_API_VERSION packs it
	driver i64   # the driver's version, packed as its vendor does
	vendor i64
	v14 bool   # Vulkan 1.4: the device is made for it
	pushDescriptor bool
	maintenance5 bool   # offered (reported only: nothing here is simpler with them)
	maintenance6 bool
	hostImageCopy bool   # the feature, and RGBA8 textures copied into from the CPU as fast to sample
	hostCopy bool   # textures' pixels copied in by the CPU with it (else staged)
	bindless bool   # descriptor indexing as texture arrays need it (Vulkan 1.2's features)
	maxTextures i64   # the most textures a texture array's table may hold
	multiDraw bool = false   # indirect draws of many commands, each from its first instance
	blocks bool = false   # textures of BC blocks (textureCompressionBC)
	countedDraw bool = false   # indirect draws counted by the GPU (Vulkan 1.2's drawIndirectCount)

fn noSupport():
	Support(
		name = "",
		api = 0,
		driver = 0,
		vendor = 0,
		v14 = false,
		pushDescriptor = false,
		maintenance5 = false,
		maintenance6 = false,
		hostImageCopy = false,
		hostCopy = false,
		bindless = false, maxTextures = 0)

# major.minor.patch
pub fn apiText(api i64) str:
	"{api >> 22 & 0x7F}.{api >> 12 & 0x3FF}.{api & 0xFFF}"

# a driver's version as its vendor writes it (NVIDIA's: major.minor)
fn driverText(vendor i64, v i64):
	"{v >> 22 & 0x3FF}.{(v >> 14 & 0xFF):0>2}" if vendor == 0x10DE else apiText(v)

fn querySupport(pd i64):
	props = DeviceProperties()
	vkGetPhysicalDeviceProperties(pd, props)
	api = i64(props.apiVersion)
	s = Support(
		name = cText(props.name),
		api,
		driver = props.driverVersion,
		vendor = props.vendor,
		v14 = false,
		pushDescriptor = false,
		maintenance5 = false, maintenance6 = false, hostImageCopy = false, hostCopy = false, bindless = false, maxTextures = 0)
	bindless, maxTextures = querySupportForArrays(pd)
	s.bindless = bindless
	s.maxTextures = maxTextures
	multiDraw, countedDraw = querySupportForIndirect(pd)
	s.multiDraw = multiDraw
	s.countedDraw = countedDraw
	s.blocks = querySupportForBlocks(pd)
	if api.bits(12, 10) >= 4 or api.bits(22, 7) > 1:
		v14 = Vulkan14Features()
		v13 = Vulkan13Features(next = v14)
		v12 = Vulkan12Features(next = v13)
		f = Features2(next = v12, features = zeros(55))
		vkGetPhysicalDeviceFeatures2(pd, f)
		s.v14 = true
		s.pushDescriptor = v14.pushDescriptor != 0
		s.maintenance5 = v14.maintenance5 != 0
		s.maintenance6 = v14.maintenance6 != 0
		s.hostImageCopy = v14.hostImageCopy != 0 and hostCopyFits(pd)
	else:
		s.pushDescriptor = hasExtension(pd, "VK_KHR_push_descriptor")
		s.maintenance5 = hasExtension(pd, "VK_KHR_maintenance5")
		s.maintenance6 = hasExtension(pd, "VK_KHR_maintenance6")
	s

# Whether texture arrays may be bound (descriptor indexing: sampled images indexed non-uniformly,
# runtime arrays, bindings partially bound, of a variable count and updated after they are bound),
# and the most textures an array's table may hold (the device's limits, 65536 at most).
fn querySupportForArrays(pd i64):
	v12 = Vulkan12Features()
	f = Features2(next = v12, features = zeros(55))
	vkGetPhysicalDeviceFeatures2(pd, f)
	on = v12.descriptorIndexing != 0 and v12.shaderSampledImageArrayNonUniformIndexing != 0 and
		v12.runtimeDescriptorArray != 0 and
		v12.descriptorBindingPartiallyBound != 0 and
		v12.descriptorBindingVariableDescriptorCount != 0 and
		v12.descriptorBindingSampledImageUpdateAfterBind != 0
	limits = DescriptorIndexingProperties()
	props = Properties2(next = limits, properties = DeviceProperties())
	vkGetPhysicalDeviceProperties2(pd, props)
	most = [
		limits.maxPerStageSamplers,
		limits.maxPerStageSampledImages,
		limits.maxSetSamplers,
		limits.maxSetSampledImages
	]
		.map(i64(it))
		.min() ??
		0
	(on, most.min(65_536))

# Whether indirect draws may read many commands, each from its first instance (Vulkan 1.0's
# multiDrawIndirect and drawIndirectFirstInstance), and be counted by the GPU (1.2's
# drawIndirectCount).
fn querySupportForIndirect(pd i64):
	v12 = Vulkan12Features()
	f = Features2(next = v12, features = zeros(55))
	vkGetPhysicalDeviceFeatures2(pd, f)
	(f.features[9] != 0 and f.features[10] != 0, v12.drawIndirectCount != 0)

# whether textures may be of BC blocks (Vulkan 1.0's textureCompressionBC)
fn querySupportForBlocks(pd i64):
	f = Features2(next = none, features = zeros(55))
	vkGetPhysicalDeviceFeatures2(pd, f)
	f.features[22] != 0

# Whether RGBA8 textures (what the engine uploads) may be copied into from the CPU: the format
# allows it and a texture that allows it is as fast for the GPU as one that does not.
fn hostCopyFits(pd i64):
	features = FormatProperties3()
	format = FormatProperties2(next = features)
	vkGetPhysicalDeviceFormatProperties2(pd, core.fmtRgba8, format)
	if (features.optimalTiling & u64(formatHostTransfer)) == 0: return false
	performance = HostImageCopyPerformance()
	properties = ImageFormatProperties2(next = performance)
	usage = imgSampled | imgTransferSrc | imgTransferDst | imgHostTransfer
	if vkGetPhysicalDeviceImageFormatProperties2(
		pd,
		ImageFormatInfo2(format = u32(core.fmtRgba8), usage = u32(usage)),
		properties
	) !=
		0:
		return false
	performance.optimalDeviceAccess != 0

# Whether host-copied textures have room: the memory an RGBA8 texture the CPU copies into may
# live in is device-local in a heap of 1 GB or more (an integrated GPU's, or all of a discrete
# one's video memory seen through a resizable BAR). Without resizable BAR a discrete GPU puts it
# in the 256 MB window of video memory the CPU sees, which textures should not fill, and the CPU
# writes it across the bus several times slower than it stages (Zapnarok's 58 MB on a GTX 1650:
# 32 ms against 7). hostcopy=on or hostcopy=off (ZAP_RUN) says yes or no instead.
fn hostCopyRoomy(physical i64, device i64):
	usage = imgSampled | imgTransferSrc | imgTransferDst | imgHostTransfer
	image = ImageCreateInfo(
		format = u32(core.fmtRgba8),
		width = 256,
		height = 256,
		levels = 1,
		layers = 1,
		samples = 1,
		usage = u32(usage)
	)
	req = MemoryRequirements2()
	vkGetDeviceImageMemoryRequirements(device, DeviceImageMemoryRequirements(info = image), req)
	props = MemoryProperties()
	vkGetPhysicalDeviceMemoryProperties(physical, props)
	for i in 0..i64(props.typeCount):
		t = props.types[i]
		if i64(req.typeBits).bits(i, 1) == 1 and (t.flags & memDeviceLocal) != 0 and
			props.heaps[t.heap].size >= 1 << 30:
			return true
	false

# the device's support on one line, for ZAP_RUN=gpu
pub fn describeSupport(s Support) str:
	"{s.name}: Vulkan {apiText(s.api)}, driver {driverText(s.vendor, s.driver)}; made for {"1.4" if s.v14 else "1.3"}: push descriptors {s.pushDescriptor}, maintenance5 {s.maintenance5}, maintenance6 {s.maintenance6}, host image copy {s.hostImageCopy} (textures {"copied by the CPU" if s.hostCopy else "staged"}), texture arrays {s.bindless} (up to {s.maxTextures}), multi-draw indirect {s.multiDraw}, counted {s.countedDraw}, BC textures {s.blocks}"

# the physical device to draw with (a discrete GPU first) and its queue family that draws
# and presents to the surface
fn pickDevice(instance i64, surface i64):
	room = 16
	devices i64[] = []
	loop:
		count = Count(n = u32(room))
		devices = zeros(room)
		result = vkEnumeratePhysicalDevices(instance, count, devices)
		if result != resultIncomplete:
			check(result, "vkEnumeratePhysicalDevices")
			devices.truncate(i64(count.n))
			break
		room *= 2
	best = -1
	bestFamily = -1
	bestScore = -1
	found = []   # each device passed over and why, for the message when none fits
	for pd in devices:
		props = DeviceProperties()
		vkGetPhysicalDeviceProperties(pd, props)
		api = i64(props.apiVersion)
		named = "{cText(props.name)} (Vulkan {apiText(api)})"
		if api.bits(12, 10) < 3 and (api >> 22) <= 1:
			found.push("{named}: older than 1.3")
			continue
		family = presentFamily(pd, surface)
		if family < 0:
			found.push("{named}: no queue that draws and presents")
			continue
		kind = props.deviceType   # 2 discrete, 1 integrated
		score = 2 if kind == 2 else 1 if kind == 1 else 0
		if score > bestScore:
			best = pd
			bestFamily = family
			bestScore = score
	if best == 0 or best == -1:
		fail("rhi: no GPU with Vulkan 1.3 and a queue that presents; {found.join("; ") if not found.isEmpty else "none found"}")
	(best, bestFamily)

fn presentFamily(pd i64, surface i64):
	count = Count(n = 64)
	families = fill(64, QueueFamily())
	vkGetPhysicalDeviceQueueFamilyProperties(pd, count, families)
	for f in 0..i64(count.n):
		supported u32 = 1
		if surface != 0:
			vkGetPhysicalDeviceSurfaceSupportKHR(pd, f, surface, out supported)
		if (families[f].flags & 1) != 0 and supported != 0: return f
	-1

fn hasExtension(pd i64, name str):
	room = 256
	loop:
		count = Count(n = u32(room))
		extensions = fill(room, ExtensionProperties())
		result = vkEnumerateDeviceExtensionProperties(pd, 0, count, extensions)
		if result == resultIncomplete:
			room *= 2
			continue
		return extensions[..i64(count.n)].any(cText(.name) == name)

# the text of a C string held in a fixed array (up to its \0)
fn cText(chars u8[256]) str:
	s = []
	for c in chars:
		if c == 0: break
		s.push(c)
	str(move s)

# The device: Vulkan 1.4's push descriptors and host image copy (when it has them) on 1.3's
# dynamic rendering and synchronization2, 1.2's descriptor indexing (for texture arrays) and
# counted indirect draws, 1.0's anisotropy and multi-draw indirect (each when it has them); on a
# 1.3 device, push descriptors from their extension.
fn newLogicalDevice(physical i64, family i64, s Support):
	priorities = [f32(1.0)]
	queue = DeviceQueueCreateInfo(family = u32(family), priorities)
	core u32[55] = zeros(55)
	core[19] = 1   # samplerAnisotropy
	core[9] = u32(1 if s.multiDraw else 0)   # multiDrawIndirect
	core[10] = u32(1 if s.multiDraw else 0)   # drawIndirectFirstInstance
	core[22] = u32(1 if s.blocks else 0)   # textureCompressionBC
	# a 1.3 device has no 1.4 features to chain: its push descriptors come from the extension,
	# when it has it
	v14 = Vulkan14Features(
		pushDescriptor = 1 if s.pushDescriptor else 0,
		hostImageCopy = 1 if s.hostImageCopy else 0
	)
	v13 = Vulkan13Features(next = v14, synchronization2 = 1, dynamicRendering = 1) if s.v14
		else Vulkan13Features(synchronization2 = 1, dynamicRendering = 1)
	on = u32(1 if s.bindless else 0)
	v12 = Vulkan12Features(
		next = v13,
		descriptorIndexing = on,
		shaderSampledImageArrayNonUniformIndexing = on,
		runtimeDescriptorArray = on,
		descriptorBindingPartiallyBound = on,
		descriptorBindingVariableDescriptorCount = on,
		descriptorBindingSampledImageUpdateAfterBind = on,
		drawIndirectCount = u32(1 if s.countedDraw else 0))
	features = Features2(next = v12, features = core)
	names = [Name(text = "VK_KHR_swapchain\0")] if s.v14 or not s.pushDescriptor
		else [Name(text = "VK_KHR_swapchain\0"), Name(text = "VK_KHR_push_descriptor\0")]
	info = DeviceCreateInfo(
		next = features,
		queue,
		extensionCount = u32(names.len),
		extensions = names
	)
	check(vkCreateDevice(physical, info, 0, out device), "vkCreateDevice")
	device

# ---------- the swapchain ----------

# The swapchain for the window's size: as many images as the surface allows past its least (one
# more, at most three), its images and their views; the old one retired first.
fn newSwapchain(mut d Device):
	vkDeviceWaitIdle(d.device)
	if d.surface == 0:
		d.newOffscreen()
		return
	caps = SurfaceCapabilities()
	check(
		vkGetPhysicalDeviceSurfaceCapabilitiesKHR(d.physical, d.surface, caps),
		"surface capabilities"
	)
	if caps.currentWidth != 0xFFFF_FFFF:
		d.state.width = caps.currentWidth
		d.state.height = caps.currentHeight
	count = (i64(caps.minImageCount) + 1).max(2)
	if caps.maxImageCount > 0:
		count = count.min(i64(caps.maxImageCount))
	if d.state.width == 0 or d.state.height == 0:
		d.state.stale = true
		return   # a minimized window: nothing to draw into
	mode = 2 if d.vsync else d.presentModeWithout()   # FIFO, or MAILBOX / IMMEDIATE
	# the images as the window stands (IDENTITY), the system turning them with the screen (an
	# app's wide window on a phone held upright by nature)
	transform = u32(1) if (caps.transforms & 1) != 0 else caps.currentTransform
	d.turned = transform != caps.currentTransform
	old = d.swapchain
	# SRGB_NONLINEAR (the shaders write gamma themselves), opaque, clipped
	info = SwapchainCreateInfo(
		surface = d.surface,
		minImageCount = u32(count),
		format = u32(core.screenFormat),
		width = u32(d.state.width),
		height = u32(d.state.height),
		usage = u32(
			imgColorAttachment | imgTransferSrc | imgTransferDst
		), transform, presentMode = u32(mode), old)
	check(vkCreateSwapchainKHR(d.device, info, 0, out swapchain), "vkCreateSwapchainKHR")
	for v in d.swapViews:
		vkDestroyImageView(d.device, v, 0)
	if old != 0:
		vkDestroySwapchainKHR(d.device, old, 0)
	d.swapchain = swapchain
	imageCount = Count(n = 16)
	images = zeros(16)
	check(
		vkGetSwapchainImagesKHR(d.device, swapchain, imageCount, images),
		"vkGetSwapchainImagesKHR"
	)
	images.truncate(i64(imageCount.n))
	d.swapImages = []
	d.swapViews = []
	for image in images:
		d.swapImages.push(image)
		d.swapViews.push(d.newView(image, core.screenFormat, aspectColor, false, 1, 1))
	while d.presented.len < images.len:
		d.presented.push(d.newSemaphore())
	d.state.stale = false

# Without a window: the images the frames draw into, of the screen's format and size, one a frame
# in flight (a frame's drawing then never waits for another's); the old ones retired.
fn newOffscreen(mut d Device):
	for t in d.offscreen:
		d.state.retire(
			core.Retired(kind = core.retiredView, handle = t.view, block = -1, offset = 0, size = 0)
		)
		d.state.retire(
			core.Retired(
				kind = core.retiredImage,
				handle = t.image,
				block = t.alloc.block,
				offset = t.alloc.offset,
				size = t.alloc.size
			)
		)
	d.offscreen = []
	d.swapImages = []
	d.swapViews = []
	loop core.framesInFlight:
		t = d.newTexture(core.TextureDesc(
			width = d.state.width,
			height = d.state.height,
			layers = 1,
			levels = 1,
			format = core.screenFormat,
			samples = 1,
			array = false,
			target = true))
		d.swapImages.push(t.image)
		d.swapViews.push(t.view)
		d.offscreen.push(t)
	d.state.stale = false

# the present mode without waiting for the screen: IMMEDIATE when there is one, else MAILBOX
fn presentModeWithout(d Device):
	count = Count(n = 16)
	modes = fill(16, u32(0))
	vkGetPhysicalDeviceSurfacePresentModesKHR(d.physical, d.surface, count, modes)
	found = 2
	for i in 0..i64(count.n):
		m = modes[i]
		if m == 0:
			found = 0   # IMMEDIATE: shown as soon as made
		elif m == 1 and found == 2:
			found = 1   # MAILBOX
	found

# whether frames wait for the screen's refresh
pub fn setVsync(mut d Device, on bool):
	if d.vsync != on:
		d.vsync = on
		if d.surface != 0:
			d.state.stale = true

# The frames shown in another window of the system (an app's, made again when it comes back to
# the screen): the swapchain and the surface of the old one destroyed, the new swapchain made by
# the next frame. A device without a window keeps drawing offscreen.
pub fn setWindow(mut d Device, hwnd i64, hinstance i64):
	if d.surface == 0: return
	vkDeviceWaitIdle(d.device)
	for v in d.swapViews:
		vkDestroyImageView(d.device, v, 0)
	d.swapViews = []
	d.swapImages = []
	if d.swapchain != 0:
		vkDestroySwapchainKHR(d.device, d.swapchain, 0)
	d.swapchain = 0
	vkDestroySurfaceKHR(d.instance, d.surface, 0)
	d.surface = newSurface(d.instance, hwnd, hinstance)
	d.state.stale = true

# an image view of the image: 2D, or the layers of an array
pub fn newView(
	d Device,
	image i64,
	format i64,
	aspect i64,
	array bool,
	levels i64,
	layers i64
) i64:
	# VK_IMAGE_VIEW_TYPE_2D_ARRAY or 2D, the identity swizzle
	info = ImageViewCreateInfo(
		image,
		viewType = 5 if array else 1,
		format = u32(format),
		swizzle = zeros(4),
		range = ImageSubresourceRange(
			aspect = u32(aspect),
			levels = u32(levels),
			layers = u32(layers)
	))
	check(vkCreateImageView(d.device, info, 0, out view), "vkCreateImageView")
	view

# ---------- frames ----------

fn newFrame(d Device):
	Frame(
		commands = d.newCommandBuffer(),
		uploads = d.newCommandBuffer(),
		uploading = false,
		fence = d.newFence(true),
		acquired = d.newSemaphore()
	)

fn newCommandBuffer(d Device):
	poolInfo = CommandPoolCreateInfo(flags = 2, family = u32(d.family))   # RESET_COMMAND_BUFFER
	check(vkCreateCommandPool(d.device, poolInfo, 0, out pool), "vkCreateCommandPool")
	check(
		vkAllocateCommandBuffers(d.device, CommandBufferAllocateInfo(pool), out buffer),
		"vkAllocateCommandBuffers"
	)
	buffer

fn newFence(d Device, signaled bool):
	check(
		vkCreateFence(d.device, FenceCreateInfo(flags = 1 if signaled else 0), 0, out fence),
		"vkCreateFence"
	)
	fence

fn newSemaphore(d Device):
	check(vkCreateSemaphore(d.device, SemaphoreCreateInfo(), 0, out semaphore), "vkCreateSemaphore")
	semaphore

fn beginCommands(buffer i64):
	check(vkResetCommandBuffer(buffer, 0), "vkResetCommandBuffer")
	check(vkBeginCommandBuffer(buffer, CommandBufferBeginInfo(flags = 1)), "vkBeginCommandBuffer")   # ONE_TIME_SUBMIT

# Begins a frame: its slot's previous work waited for and its retired objects freed, the
# swapchain image acquired (the swapchain made again when it no longer fits). False when there
# is nothing to draw into (a minimized window): the frame is skipped.
pub fn beginFrame(mut d Device) bool:
	if d.state.stale:
		d.newSwapchain()
		if d.state.stale: return false
	f = d.state.frame
	if d.surface == 0:
		d.image = f
	else:
		result = vkAcquireNextImageKHR(
			d.device,
			d.swapchain,
			-1,
			d.frames[f].acquired,
			0,
			out index
		)
		if result == resultOutOfDate:
			d.state.stale = true
			return false
		d.image = index
	d.state.startFrame()
	d.resetFrameSets()
	beginCommands(d.frames[f].commands)
	if d.frames[f].timestamps != 0:
		vkCmdResetQueryPool(
			d.frames[f].commands,
			d.frames[f].timestamps,
			0,
			core.mostTimedPasses * 2
		)
	d.pushed.clear()
	d.boundArrays.clear()
	d.boundVertices.clear()
	true

# the frame's upload commands, begun on first use: their copies after the work before them (its
# reads done, its writes visible), and what reads a buffer or a texture after them
fn uploadCommands(mut d Device):
	f = d.state.frame
	if not d.frames[f].uploading:
		beginCommands(d.frames[f].uploads)
		memoryBarrier(
			d.frames[f].uploads,
			stageAllCommands,
			writeAccess,
			stageTransfer,
			transferAccess
		)
		d.frames[f].uploading = true
	d.frames[f].uploads

# Ends a frame: its passes closed, the swapchain image made presentable, the uploads and the
# passes submitted, the image presented (an offscreen one is not); then the next frame's slot made
# ready (core's finishFrame).
pub fn endFrame(mut d Device):
	f = d.state.frame
	d.endPass()
	cmd = d.frames[f].commands
	d.barrier(cmd, d.state.restTextures(), 0, 0, [])
	imageBarrier(
		cmd,
		d.swapImages[d.image],
		d.layoutUndefinedOr(),
		layoutPresent if d.surface != 0 else layoutGeneral,
		aspectColor,
		1,
		1
	)
	check(vkEndCommandBuffer(cmd), "vkEndCommandBuffer")
	buffers = []
	if d.frames[f].uploading:
		memoryBarrier(
			d.frames[f].uploads,
			stageTransfer,
			accessTransferWrite,
			bufferReaders,
			bufferReads
		)
		check(vkEndCommandBuffer(d.frames[f].uploads), "vkEndCommandBuffer")
		buffers.push(d.frames[f].uploads)
	buffers.push(cmd)
	d.frames[f].uploading = false
	check(vkResetFences(d.device, 1, [d.frames[f].fence]), "vkResetFences")
	presents = d.surface != 0
	waits = [d.frames[f].acquired]
	stages = [u32(stageAllCommands)]
	signals = [d.presented[d.image]] if presents else []
	submit = SubmitInfo(
		waitCount = 1 if presents else 0,
		waits,
		waitStages = stages,
		bufferCount = u32(buffers.len),
		buffers,
		signalCount = u32(signals.len),
		signals
	)
	check(vkQueueSubmit(d.queue, 1, submit, d.frames[f].fence), "vkQueueSubmit")
	if presents:
		d.present(signals)
	d.image = -1
	core.finishFrame(d)

# the frame's image presented once its drawing signals
fn present(mut d Device, signals i64[]):
	swapchains = [d.swapchain]
	indices = [u32(d.image)]
	info = PresentInfo(waitCount = 1, waits = signals, swapchainCount = 1, swapchains, indices)
	result = vkQueuePresentKHR(d.queue, info)
	if result == resultOutOfDate or (result == resultSuboptimal and not d.turned):
		d.state.stale = true

# the swapchain image's layout as the frame left it: drawn into (a pass on the screen), or
# untouched
fn layoutUndefinedOr(d Device):
	layoutColorAttachment if d.state.pass.screenTouched else layoutUndefined

pub fn waitIdle(d Device):
	_ = vkDeviceWaitIdle(d.device)

# a device that is not made yet: what the engine holds until its window opens
pub fn emptyDevice() Device:
	Device(
		state = core.noDeviceState(),
		support = noSupport(),
		instance = 0,
		physical = 0,
		device = 0,
		queue = 0,
		family = 0,
		surface = 0,
		swapchain = 0,
		swapImages = [],
		swapViews = [], presented = [], vsync = true, frames = [], image = -1, programs = [], pipelineCache = 0)

# ---------- the passes' GPU time ----------

# a timestamp's nanoseconds (the device's limits: timestampPeriod, 720 bytes into its properties)
fn timestampPeriod(physical i64) f64:
	props = DeviceProperties()
	vkGetPhysicalDeviceProperties(physical, props)
	at = 720 - 292   # into `rest`, which starts after the cache's UUID
	bits = props.rest[at] | u32(props.rest[at + 1]) << 8 | u32(props.rest[at + 2]) << 16 | u32(props.rest[
		at + 3
	]) << 24
	f64(f32.fromBits(bits))

# ---------- the pipeline cache ----------

# The pipeline cache, holding what the last run left (its pipelines made again from it, not
# compiled) when that is this device's: its header (32 bytes) names the vendor, the device and the
# cache's UUID of this driver. Another's is left out (the cache starts empty).
fn newPipelineCache(d Device):
	props = DeviceProperties()
	vkGetPhysicalDeviceProperties(d.physical, props)
	blob ref u8[] = d.state.pipelineStore.blob
	fits = blob.len >= 32 and (blob.loadWord(0) & 0xFFFF_FFFF) == 32 and
		(blob.loadWord(0) >> 32) == 1 and
		(blob.loadWord(8) & 0xFFFF_FFFF) == u64(props.vendor) and
		(blob.loadWord(8) >> 32) == props.device
	for i in 0..16:
		fits = fits and blob[16 + i] == props.uuid[i]
	# (a size of 0: the bytes are not read)
	check(
		vkCreatePipelineCache(d.device, PipelineCacheCreateInfo(size = blob.len if fits else 0, data = blob), 0, out cache),
		"vkCreatePipelineCache"
	)
	bindExtern(pipelineCacheSize, vkGetDeviceProcAddr(d.device, "vkGetPipelineCacheData\0"))
	cache
