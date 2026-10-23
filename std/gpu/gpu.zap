# Compute on the GPU without a window: a module of the standard library (`import gpu`). The
# kernels are Zap, functions of a module's `.gpu.zap` files built by `compute(kernels.sum, 64)`
# (spec 11, *Compute*); this module runs them on the machine's GPU through Vulkan.
#
#   if gpu.available():
#       values = gpu.newBuffer(n * 4)
#       gpu.upload(values, xs)
#       gpu.run(compute(kernels.sum, 64), kernels.Sums(values = [], totals = [], count = n),
#           [values.handle, totals.handle], groups)
#       gpu.download(totals, sums)
#
# The work is recorded in order and runs when something waits for it (download, finish): each
# kernel sees what the work before it wrote. A kernel's parameters are a value of the struct its
# entry takes, its numbers written by the packer the compiler gave the struct; its storage buffers
# are named apart, as buffers of the device (their lists in the struct stay empty), in the order
# the struct declares them. A buffer let go returns to the device, which hands it out again at once
# to a buffer of the same size. A barrier comes between two pieces of work only where the later
# reads what the earlier wrote or writes what it read or wrote.

import win

# what a struct of a program's parameters has: the packer the shader compiler writes for it
pub bound GpuParams:
	fn gpuName(self GpuParams) str
	fn gpuWrite(
		self GpuParams,
		mut words u32[],
		at i64,
		mut textures i64[],
		textureAt i64,
		mut buffers u8[,],
		bufferAt i64,
		mut arrays i64[,],
		arrayAt i64
	)

# A storage buffer in the GPU's own memory, `bytes` long; `handle` names it to a kernel.
pub type Buffer:
	handle i64 = 0
	memory i64 = 0
	bytes i64 = 0

	# a buffer let go is handed out again at once: the work after its next owner's reaches it after
	# a barrier when the work before read or wrote it
	mut fn drop():
		if handle != 0:
			if dev.spare.get(bytes) == none:
				dev.spare[bytes] = []
			dev.spare[bytes].push(Block(bytes, handle, memory))

	fn copy():
		b = newBuffer(bytes)
		record([handle], [b.handle])
		vkCmdCopyBuffer(
			dev.commands,
			handle,
			b.handle,
			1,
			BufferCopy(src = 0, dst = 0, size = bytes)
		)
		b

# a buffer's Vulkan objects
type Block:
	bytes i64
	handle i64
	memory i64

# a buffer the CPU writes and reads where the GPU sees it, mapped at `mapped`
type HostBuffer:
	handle i64 = 0
	memory i64 = 0
	bytes i64 = 0
	mapped i64 = 0

# a kernel's Vulkan objects and what its code says of it
type KernelRecord:
	setLayout i64
	layout i64
	pipeline i64
	paramBytes i64
	bindings i64[]
	written bool[]   # per storage buffer: whether the stage writes it

type Device:
	state i64 = 0   # 0 not tried, 1 ready, 2 none
	why str = ""
	name str = ""
	instance i64 = 0
	device i64 = 0
	queue i64 = 0
	memoryFlags i64[] = []
	commandPool i64 = 0
	commands i64 = 0   # the command buffer being recorded
	commandList i64[] = []   # the command buffers made, those before `submitted` sent
	submitted i64 = 0
	sinceSubmit i64 = 0   # the work recorded in `commands`
	writtenSince {i64: bool} = {}   # the buffers written since the last barrier, by handle
	readSince {i64: bool} = {}   # and those read
	fence i64 = 0
	pool i64 = 0
	recording bool = false
	sets i64 = 0   # descriptor sets taken from the pool since it was reset
	ring HostBuffer = HostBuffer()   # parameter blocks and uploads of the work recorded
	ringAt i64 = 0
	readback HostBuffer = HostBuffer()
	kernels KernelRecord[] = []
	kernelOf {i64: i64[]} = {}   # a code's key (codeKey): the kernels of codes of that key
	kernelCodes str[] = []
	spare {i64: Block[]} = {}   # buffers let go, ready, by size
	dispatches i64 = 0   # counted since the program began

mut dev = Device()

ringBytes = 64 << 20
submitEvery = 40   # the dispatches and copies a command buffer holds before it is sent

# a code's key: its length and a few of its words, read at once (the whole code is compared when
# two share a key)
fn codeKey(code str):
	key = code.len
	step = (code.len / 16).max(1)
	at = 0
	while at < code.len:
		key = key * 31 + i64(code[at])
		key &= 0xFFFF_FFFF_FFFF
		at += step
	key
maxSets = 4096
uniformAlign = 256

fn check(result i32, what str):
	if result != 0:
		fail("gpu: {what} failed ({result})")

# whether the machine has a GPU this module can run kernels on (Vulkan 1.2 with a compute queue);
# the first call finds it
pub fn available() bool:
	if dev.state == 0:
		dev.state = 2
		dev.why = start()
		if dev.why.isEmpty:
			dev.state = 1
	dev.state == 1

# why available() is false, empty when it is true
pub fn unavailableReason() str:
	available()
	dev.why.copy()

# the GPU's name as its driver gives it
pub fn deviceName() str:
	available()
	dev.name.copy()

# the kernels dispatched since the program began
pub fn dispatchCount() i64:
	dev.dispatches

fn ready():
	if not available():
		fail("gpu: no GPU to run on ({dev.why})")

mut loader = 0

# the Vulkan loader's file, NUL-ended (std/gpu/linux/gpu.zap has Linux's)
fn vulkanLibrary():
	"vulkan-1.dll\0"

fn vulkanFunction(name str):
	getInstanceProc = win.GetProcAddress(loader, "vkGetInstanceProcAddr\0")
	bindExtern(vkGetInstanceProcAddr, getInstanceProc)
	vkGetInstanceProcAddr(dev.instance, "{name}\0")

extern loaded fn vkGetInstanceProcAddr(instance i64, name str) i64

# the device made: the instance, the GPU (a discrete one first), its compute queue, the objects
# work is recorded with; the reason when there is none
fn start():
	loader = win.LoadLibraryA(vulkanLibrary())
	if loader == 0: return "no {vulkanLibrary().replace("\0", "")}"
	bindExtern(vkCreateInstance, vulkanFunction("vkCreateInstance"))
	app = ApplicationInfo(   # VK_API_VERSION_1_2
		name = "zap\0",
		version = 1,
		engineName = "zap\0",
		engineVersion = 1,
		apiVersion = u32(1 << 22 | 3 << 12)
	)
	if vkCreateInstance(InstanceCreateInfo(app), 0, out instance) != 0: return "no Vulkan instance"
	dev.instance = instance
	bindExterns(vulkanFunction)
	physical, family = pickDevice()
	if physical == 0: return "no GPU with Vulkan 1.2 and a compute queue"
	props = MemoryProperties()
	vkGetPhysicalDeviceMemoryProperties(physical, props)
	dev.memoryFlags = (0..i64(props.typeCount)).map(i64(props.types[it].flags))
	priorities f32[] = [1.0]
	queueInfo = DeviceQueueCreateInfo(family = u32(family), priorities)
	check(
		vkCreateDevice(physical, DeviceCreateInfo(queue = queueInfo), 0, out device),
		"vkCreateDevice"
	)
	dev.device = device
	vkGetDeviceQueue(device, family, 0, out queue)
	dev.queue = queue
	poolInfo = CommandPoolCreateInfo(flags = 2, family = u32(family))   # RESET_COMMAND_BUFFER
	check(vkCreateCommandPool(device, poolInfo, 0, out commandPool), "vkCreateCommandPool")
	dev.commandPool = commandPool
	check(vkCreateFence(device, FenceCreateInfo(), 0, out fence), "vkCreateFence")
	dev.fence = fence
	sizes = [
		DescriptorPoolSize(kind = u32(descStorageBuffer), count = u32(maxSets * 8)),
		DescriptorPoolSize(kind = u32(descUniformBuffer), count = u32(maxSets))
	]
	descriptorInfo = DescriptorPoolCreateInfo(maxSets = u32(maxSets), sizeCount = 2, sizes)
	check(vkCreateDescriptorPool(device, descriptorInfo, 0, out pool), "vkCreateDescriptorPool")
	dev.pool = pool
	dev.ring = newHostBuffer(ringBytes, usageUniform | usageTransferSrc)
	""

# the GPU work runs on: a discrete one before an integrated one, before any other, with Vulkan
# 1.2 and a queue family that computes; (0, -1) when there is none
fn pickDevice():
	count = Count(n = 16)
	devices i64[] = zeros(16)
	check(vkEnumeratePhysicalDevices(dev.instance, count, devices), "vkEnumeratePhysicalDevices")
	devices.truncate(i64(count.n))
	best = 0
	bestFamily = -1
	bestScore = -1
	for pd in devices:
		props = DeviceProperties()
		vkGetPhysicalDeviceProperties(pd, props)
		api = i64(props.apiVersion)
		if (api >> 22) == 1 and api.bits(12, 10) < 2: continue
		family = computeFamily(pd)
		if family < 0: continue
		kind = props.deviceType   # 2 discrete, 1 integrated
		score = 2 if kind == 2 else 1 if kind == 1 else 0
		if score > bestScore:
			best = pd
			bestFamily = family
			bestScore = score
			dev.name = cText(props.name)
	(best, bestFamily)

fn computeFamily(pd i64):
	count = Count(n = 64)
	families = fill(64, QueueFamily())
	vkGetPhysicalDeviceQueueFamilyProperties(pd, count, families)
	for i in 0..i64(count.n):
		if (families[i].flags & queueCompute) != 0: return i
	-1

fn cText(chars u8[256]) str:
	s = []
	for c in chars:
		if c == 0: break
		s.push(c)
	str(move s)

# ---------- memory ----------

# the first memory type allowed by `bits` with every one of the `wanted` properties, -1 none
fn memoryType(bits i64, wanted i64):
	for i, flags in dev.memoryFlags:
		if bits.bits(i, 1) == 1 and (flags & wanted) == wanted: return i
	-1

# a buffer and its memory, bound: (buffer, memory)
fn newVulkanBuffer(bytes i64, usage i64, wanted i64, fallback i64):
	info = BufferCreateInfo(size = bytes.max(16), usage = u32(usage))
	check(vkCreateBuffer(dev.device, info, 0, out handle), "vkCreateBuffer")
	req = MemoryRequirements()
	vkGetBufferMemoryRequirements(dev.device, handle, req)
	t = memoryType(req.typeBits, wanted)
	if t < 0:
		t = memoryType(req.typeBits, fallback)
	if t < 0:
		fail("gpu: no memory type for a buffer of {bytes} bytes")
	allocation = MemoryAllocateInfo(size = req.size, typeIndex = u32(t))
	check(
		vkAllocateMemory(dev.device, allocation, 0, out memory),
		"vkAllocateMemory of {bytes} bytes"
	)
	check(vkBindBufferMemory(dev.device, handle, memory, 0), "vkBindBufferMemory")
	(handle, memory)

fn newHostBuffer(bytes i64, usage i64):
	coherent = memHostVisible | memHostCoherent
	handle, memory = newVulkanBuffer(bytes, usage, coherent | memHostCached, coherent)
	check(vkMapMemory(dev.device, memory, 0, bytes, 0, out mapped), "vkMapMemory")
	HostBuffer(handle, memory, bytes, mapped)

# a buffer of `bytes` bytes in the GPU's memory, what it holds unknown (one let go of that size,
# or a new one)
pub fn newBuffer(bytes i64) Buffer:
	ready()
	size = bytes.max(16)
	if dev.spare.get(size) is free:
		if free.last is b:
			handle = b.handle
			memory = b.memory
			dev.spare[size].pop()
			return Buffer(handle, memory, bytes = size)
	usage = usageStorage | usageTransferSrc | usageTransferDst
	handle, memory = newVulkanBuffer(size, usage, memDeviceLocal, 0)
	Buffer(handle, memory, bytes = size)

# a buffer of `bytes` bytes, every byte 0
pub fn zeroBuffer(bytes i64) Buffer:
	b = newBuffer(bytes)
	record([], [b.handle])
	vkCmdFillBuffer(dev.commands, b.handle, 0, b.bytes, 0)
	b

# ---------- recording ----------

# the command buffer open for work, every write before what is recorded next seen by it
fn record(reads i64[], writes i64[]):
	if dev.recording and dev.sinceSubmit >= submitEvery:
		# the GPU starts on what is recorded while the rest is: sent, a new buffer begun
		check(vkEndCommandBuffer(dev.commands), "vkEndCommandBuffer")
		buffers = [dev.commands]
		check(vkQueueSubmit(dev.queue, 1, SubmitInfo(buffers), 0), "vkQueueSubmit")
		dev.submitted += 1
		dev.recording = false
	dev.sinceSubmit += 1
	if not dev.recording:
		if dev.submitted == dev.commandList.len:
			info = CommandBufferAllocateInfo(pool = dev.commandPool)
			check(vkAllocateCommandBuffers(dev.device, info, out made), "vkAllocateCommandBuffers")
			dev.commandList.push(made)
		dev.commands = dev.commandList[dev.submitted]
		check(vkResetCommandBuffer(dev.commands, 0), "vkResetCommandBuffer")
		check(   # ONE_TIME_SUBMIT
			vkBeginCommandBuffer(dev.commands, CommandBufferBeginInfo(flags = 1)),
			"vkBeginCommandBuffer"
		)
		dev.recording = true
		dev.sinceSubmit = 1
	# what follows waits for the writes before it reads or writes again, and for the reads before
	# it writes (in this buffer or one sent before it); other work runs on without a barrier
	hazard = reads.any(dev.writtenSince.get(it) != none) or
		writes.any(dev.writtenSince.get(it) != none or dev.readSince.get(it) != none)
	if hazard:
		barrier = MemoryBarrier(
			srcAccess = u32(accessMemoryWrite),
			dstAccess = u32(accessMemoryRead | accessMemoryWrite)
		)
		vkCmdPipelineBarrier(
			dev.commands,
			stageAllCommands,
			stageAllCommands,
			0,
			1,
			[barrier],
			0,
			0,
			0,
			0
		)
		dev.writtenSince.clear()
		dev.readSince.clear()
	for h in reads:
		dev.readSince[h] = true
	for h in writes:
		dev.writtenSince[h] = true

# the work recorded run, and waited for; the ring and the descriptor sets free again
pub fn finish():
	if dev.state != 1: return
	if dev.recording:
		check(vkEndCommandBuffer(dev.commands), "vkEndCommandBuffer")
		buffers = [dev.commands]
		check(vkQueueSubmit(dev.queue, 1, SubmitInfo(buffers), dev.fence), "vkQueueSubmit")
		check(vkWaitForFences(dev.device, 1, [dev.fence], 1, -1), "vkWaitForFences")
		check(vkResetFences(dev.device, 1, [dev.fence]), "vkResetFences")
		check(vkResetDescriptorPool(dev.device, dev.pool, 0), "vkResetDescriptorPool")
		dev.recording = false
		dev.submitted = 0
		dev.writtenSince.clear()
		dev.readSince.clear()
		dev.sets = 0
		dev.ringAt = 0

# room for n bytes in the ring at an offset aligned to `align`, the work recorded run first when
# it is full
fn ringRoom(n i64, align i64):
	if n > ringBytes:
		fail("gpu: {n} bytes do not fit the ring")
	at = (dev.ringAt + align - 1) / align * align
	if at + n > ringBytes:
		finish()
		at = 0
	dev.ringAt = at + n
	at

# the values' bytes copied into the buffer from byte `at`, in order with the work recorded
pub fn upload<T Copy>(b Buffer, values T[], at i64 = 0):
	ready()
	total = values.byteSize
	if at < 0 or at + total > b.bytes:
		fail("gpu: {total} bytes from byte {at} do not fit a buffer of {b.bytes}")
	size = total / values.len.max(1)
	chunk = (ringBytes / 2 / size.max(1)).max(1)
	first = 0
	while first < values.len:
		end = (first + chunk).min(values.len)
		part = values[first..end]
		n = part.byteSize
		ringAt = ringRoom(n, 16)
		win.memoryAt(dev.ring.mapped, ringBytes).write(ringAt, part)
		record([], [b.handle])
		region = BufferCopy(src = ringAt, dst = at + first * size, size = n)
		vkCmdCopyBuffer(dev.commands, dev.ring.handle, b.handle, 1, region)
		first = end

# `into` filled with the buffer's bytes from byte `at`, once the work recorded is done
pub fn download<T Copy>(b Buffer, mut into T[], at i64 = 0):
	ready()
	n = into.byteSize
	if at < 0 or at + n > b.bytes:
		fail("gpu: {n} bytes from byte {at} are not in a buffer of {b.bytes}")
	if n == 0: return
	if dev.readback.bytes < n:
		finish()
		dev.readback = newHostBuffer(n.max(1 << 20), usageTransferDst)
	record([b.handle], [])
	vkCmdCopyBuffer(
		dev.commands,
		b.handle,
		dev.readback.handle,
		1,
		BufferCopy(src = at, dst = 0, size = n)
	)
	finish()
	win.memoryAt(dev.readback.mapped, dev.readback.bytes).read(0, into)

# n bytes of buffer `from` from byte `fromAt` copied into `to` from byte `toAt`, in order
pub fn copyBytes(from Buffer, fromAt i64, to Buffer, toAt i64, n i64):
	if fromAt < 0 or toAt < 0 or fromAt + n > from.bytes or toAt + n > to.bytes:
		fail("gpu: a copy of {n} bytes past a buffer's end")
	if n == 0: return
	record([from.handle], [to.handle])
	vkCmdCopyBuffer(
		dev.commands,
		from.handle,
		to.handle,
		1,
		BufferCopy(src = fromAt, dst = toAt, size = n)
	)

# ---------- kernels ----------

# the kernel of compute(...)'s code, made the first time it is run
fn kernelOf(code str):
	key = codeKey(code)
	if dev.kernelOf.get(key) is ks:
		for k in ks:
			if dev.kernelCodes[k] == code: return k
	if code.len < 8 or code[..4] != "ZSC1":
		fail("gpu: not a compute program built by compute(...)")
	r = CodeReader(code, at = 4)
	paramBytes = r.word()
	loop r.word():   # the parts: their names and places, read by the packer
		nameBytes = r.word()
		r.at += (nameBytes + 3) / 4 * 4 + 28
	if r.word() != 0:
		fail("gpu: a kernel that samples textures")
	bindings = []
	written = []
	loop r.word():
		bindings.push(r.word())
		written.push(r.word() == 1)
	r.at += 12   # the groups' size, the code's own
	spirvBytes = r.word()
	spirv = code[r.at..r.at + spirvBytes].copy()
	layoutBindings = bindings.map(
		DescriptorSetLayoutBinding(binding = u32(it), kind = u32(descStorageBuffer))
	)
	if paramBytes > 0:
		layoutBindings.push(DescriptorSetLayoutBinding(binding = 32, kind = u32(descUniformBuffer)))
	setInfo = DescriptorSetLayoutCreateInfo(
		count = u32(layoutBindings.len),
		bindings = layoutBindings
	)
	check(
		vkCreateDescriptorSetLayout(dev.device, setInfo, 0, out setLayout),
		"vkCreateDescriptorSetLayout"
	)
	sets = [setLayout]
	check(
		vkCreatePipelineLayout(dev.device, PipelineLayoutCreateInfo(sets), 0, out layout),
		"vkCreatePipelineLayout"
	)
	moduleInfo = ShaderModuleCreateInfo(codeSize = spirv.len, code = spirv)
	check(vkCreateShaderModule(dev.device, moduleInfo, 0, out module), "vkCreateShaderModule")
	info = ComputePipelineCreateInfo(module, name = "main\0", layout)
	check(
		vkCreateComputePipelines(dev.device, 0, 1, info, 0, out pipeline),
		"vkCreateComputePipelines"
	)
	dev.kernels.push(KernelRecord(setLayout, layout, pipeline, paramBytes, bindings, written))
	k = dev.kernels.len - 1
	if dev.kernelOf.get(key) == none:
		dev.kernelOf[key] = []
	dev.kernelOf[key].push(k)
	dev.kernelCodes.push(code.copy())
	k

type CodeReader:
	code ref str
	at i64

fn word(mut r CodeReader):
	w = r.code[r.at] | i64(r.code[r.at + 1]) << 8 | i64(r.code[r.at + 2]) << 16 | i64(
		r.code[r.at + 3]
	) << 24
	r.at += 4
	w

# The kernel of compute(...)'s code run in x by y by z groups, after the work recorded: `params`
# its parameters, `buffers` the handles of its storage buffers in the order its struct names them.
pub fn run<P GpuParams>(code str, params P, buffers i64[], x i64, y i64 = 1, z i64 = 1):
	ready()
	k = kernelOf(code)
	if buffers.len != dev.kernels[k].bindings.len:
		fail("gpu: the kernel reads {dev.kernels[k].bindings.len} storage buffers, given {buffers.len}")
	paramBytes = dev.kernels[k].paramBytes
	if dev.sets >= maxSets:
		finish()
	infos = buffers.map(DescriptorBufferInfo(buffer = it, offset = 0, range = -1))
	if paramBytes > 0:
		words = fill(paramBytes / 4, u32(0))
		textures i64[] = []
		bytes u8[,] = fill(buffers.len, [])
		arrays i64[,] = []
		params.gpuWrite(words, 0, textures, 0, bytes, 0, arrays, 0)
		at = ringRoom(paramBytes, uniformAlign)
		win.memoryAt(dev.ring.mapped, ringBytes).write(at, words)
		infos.push(DescriptorBufferInfo(buffer = dev.ring.handle, offset = at, range = paramBytes))
	layouts = [dev.kernels[k].setLayout]
	check(
		vkAllocateDescriptorSets(dev.device, DescriptorSetAllocateInfo(pool = dev.pool, layouts), out set),
		"vkAllocateDescriptorSets"
	)
	dev.sets += 1
	writes = []
	for i, info in infos:
		binding = dev.kernels[k].bindings[i] if i < buffers.len else 32
		kind = descStorageBuffer if i < buffers.len else descUniformBuffer
		writes.push(
			WriteDescriptorSet(set, binding = u32(binding), kind = u32(kind), buffer = info)
		)
	vkUpdateDescriptorSets(dev.device, writes.len, writes, 0, 0)
	reads i64[] = []
	changed i64[] = []
	for i, h in buffers:
		if dev.kernels[k].written[i]:
			changed.push(h)
		else:
			reads.push(h)
	record(reads, changed)
	vkCmdBindPipeline(dev.commands, bindCompute, dev.kernels[k].pipeline)
	vkCmdBindDescriptorSets(dev.commands, bindCompute, dev.kernels[k].layout, 0, 1, [set], 0, 0)
	vkCmdDispatch(dev.commands, x, y, z)
	dev.dispatches += 1
