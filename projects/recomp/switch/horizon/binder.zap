# IHOSBinderDriver, the relay to the layer's IGraphicBufferProducer (switchbrew: Nvnflinger
# services; Android's BufferQueue): a client sends a transaction code and a parcel of arguments,
# and gets a parcel back. The client allocates the buffers (nvmap memory) and registers them with
# SetPreallocatedBuffer; it dequeues a slot, draws, queues it. Queued buffers wait in
# Display.queue, where the renderer takes them. A queued buffer is on screen at once, and the
# one it replaces is free.

import recomp.switch.maxwell

# IGraphicBufferProducer's transaction codes
txRequestBuffer = 1
txSetBufferCount = 2
txDequeueBuffer = 3
txQueueBuffer = 7
txCancelBuffer = 8
txQuery = 9
txConnect = 10
txDisconnect = 11
txAllocateBuffers = 13
txSetPreallocatedBuffer = 14

# Android's status codes, negated errno values
statusOk = 0
statusInvalidOperation = -38
statusBadValue = -22
statusWouldBlock = -11

slotFree = 0
slotDequeued = 1
slotQueued = 2

# the fence of a buffer nobody else touches: a multi-fence of no fences
fenceSize = 0x24

# the queue keeps this many presented buffers a renderer has not taken
maxQueued = 16

# the pixel format a layer has (RGBA 8888)
formatRgba8888 = 1

pub type Slot:
	graphic u8[] = []   # the client's flattened GraphicBuffer, empty before it is set
	state i64 = 0

# A queued buffer, where a renderer finds it: the nvmap handle and offset of its plane, the
# guest address that is, its layout (0 pitch, 1 tiled, 2 block linear) and block height.
pub type Presented:
	slot i64
	width i64
	height i64
	format i64
	stride i64
	handle i64
	offset i64
	size i64
	pitch i64
	layout i64
	kind i64
	blockHeightLog2 i64
	address i64
	transform i64

pub type Display:
	layers i64[] = []
	nextLayer i64 = 1
	slots Slot[] = []
	front i64 = -1   # the slot on screen
	queue Presented[] = []
	presented i64 = 0   # buffers queued so far
	bufferCount i64 = 0
	vsyncEvent i64 = -1
	vsyncAt i64 = 0

fn binderDriver(mut k Kernel, i i64, req Request, mut res Response):
	if req.command == 0 or req.command == 3: k.transactParcel(req)
	elif req.command == 2:
		_, h = k.newEvent(true)
		res.copied.push(h)
	elif req.command != 1: k.unwritten(i, req)

# a transaction: the producer's answer in the caller's reply buffer
fn transactParcel(mut k Kernel, req Request):
	code = req.arg(4, 4)
	p = readParcel(req.sent(0))
	p.skipToken()
	out = ParcelWriter()
	k.producer(code, p, out)
	req.receive(0).putBuffer(out.finish())

fn producer(mut k Kernel, code i64, mut p ParcelReader, mut out ParcelWriter):
	match code:
		1: k.requestBuffer(p, out)
		2, 13: out.write32(statusOk)
		3: k.dequeueBuffer(out)
		7: k.queueBuffer(p, out)
		8: k.cancelBuffer(p, out)
		9: k.queryProducer(p, out)
		10:
			out.write32(displayWidth)
			out.write32(displayHeight)
			out.write32(0)
			out.write32(0)
			out.write32(statusOk)
		11: k.disconnect(out)
		14: k.setPreallocatedBuffer(p, out)
		_:
			k.log.push("IGraphicBufferProducer #{code}: not written")
			out.write32(statusInvalidOperation)

# whether the slot holds a buffer
fn hasBuffer(k Kernel, slot i64):
	slot >= 0 and slot < k.display.slots.len and not k.display.slots[slot].graphic.isEmpty

fn setPreallocatedBuffer(mut k Kernel, mut p ParcelReader, mut out ParcelWriter):
	slot = p.read32()
	given = p.read32()
	if slot < 0 or slot >= 64: return out.write32(statusBadValue)
	while k.display.slots.len <= slot:
		k.display.slots.push(Slot())
	if given == 1: k.display.slots[slot].graphic = p.flattened()
	k.display.bufferCount = k.display.slots.filter(not .graphic.isEmpty).len
	out.write32(statusOk)

fn requestBuffer(mut k Kernel, mut p ParcelReader, mut out ParcelWriter):
	slot = p.read32()
	if not k.hasBuffer(slot): return out.write32(statusBadValue)
	out.write32(1)
	out.flattened(k.display.slots[slot].graphic)
	out.write32(statusOk)

# The lowest free slot that holds a buffer, with a fence already signaled; would block when
# there is none.
fn dequeueBuffer(mut k Kernel, mut out ParcelWriter):
	for slot in 0..k.display.slots.len:
		if k.hasBuffer(slot) and k.display.slots[slot].state == slotFree:
			k.display.slots[slot].state = slotDequeued
			out.write32(slot)
			out.write32(1)
			out.flattened(zeros(fenceSize))
			return out.write32(statusOk)
	out.write32(statusWouldBlock)

# QueueBuffer: the slot and the flattened QueueBufferInput (the timestamp, crop rectangle,
# scaling mode and transform, then a fence).
fn queueBuffer(mut k Kernel, mut p ParcelReader, mut out ParcelWriter):
	slot = p.read32()
	input = p.flattened()
	if not k.hasBuffer(slot) or k.display.slots[slot].state != slotDequeued:
		return out.write32(statusBadValue)
	shown = presentedOf(
		slot,
		k.display.slots[slot].graphic,
		input.u32le(32) if input.len >= 36 else 0
	)
	shown.address = k.nvmapAddress(shown.handle)
	if shown.address >= 0: shown.address += shown.offset
	k.present(slot, shown)
	out.write32(displayWidth)
	out.write32(displayHeight)
	out.write32(0)
	out.write32(0)
	out.write32(statusOk)

# The buffer on screen, the one it replaces free again; the frame's draws counted.
fn present(mut k Kernel, slot i64, shown Presented):
	if k.display.front >= 0: k.display.slots[k.display.front].state = slotFree
	k.display.slots[slot].state = slotQueued
	k.display.front = slot
	k.display.queue.push(shown)
	if k.display.queue.len > maxQueued: k.display.queue.remove(0)
	k.display.presented += 1
	if k.traceCalls:
		k.log.push(
			"  present #{k.display.presented}: slot {slot}, {k.gpu.stats.drawsThisFrame} draws"
		)
	k.gpu.endFrame()

# the fields of a flattened GraphicBuffer (a GBFR header of ten words, then the NvGraphicBuffer:
# ten words, and three planes of 0x58 bytes)
fn presentedOf(slot i64, graphic u8[], transform i64):
	Presented(
		slot,
		width = graphic.u32le(4),
		height = graphic.u32le(8),
		format = graphic.u32le(0x10),
		stride = graphic.u32le(0x0C),
		handle = graphic.u32le(0x68),
		offset = graphic.u32le(0x6C),
		size = i64(graphic.u64le(0x88)),
		pitch = graphic.u32le(0x64),
		layout = graphic.u32le(0x60),
		kind = graphic.u32le(0x70),
		blockHeightLog2 = graphic.u32le(0x74),
		address = -1,
		transform
	)

fn cancelBuffer(mut k Kernel, mut p ParcelReader, mut out ParcelWriter):
	slot = p.read32()
	if k.hasBuffer(slot) and k.display.slots[slot].state == slotDequeued:
		k.display.slots[slot].state = slotFree
	out.write32(statusOk)

# Query (NATIVE_WINDOW_*): the size, the format, how many buffers the consumer holds back (one).
fn queryProducer(mut k Kernel, mut p ParcelReader, mut out ParcelWriter):
	what = p.read32()
	values = {
		0: displayWidth,
		1: displayHeight,
		2: formatRgba8888,
		3: 1,
		6: displayWidth,
		7: displayHeight
	}
	out.write32(values.get(what) ?? 0)
	out.write32(statusOk)

# Disconnect: the buffers are the client's again; the screen keeps nothing of them.
fn disconnect(mut k Kernel, mut out ParcelWriter):
	for slot in 0..k.display.slots.len:
		k.display.slots[slot].state = slotFree
	k.display.front = -1
	out.write32(statusOk)
