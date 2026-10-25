# What each method does: the channel's own (bind an object to a subchannel, semaphores,
# syncpoints) and the classes' (inline-to-memory uploads, DMA copies, the 3D and compute
# engines' semaphores and draws). Every method also lands in its engine's register array.

# the channel's methods (switchbrew: GPFIFO class), by their word index
methodSetObject = 0
methodSemaphoreHigh = 4
methodSemaphoreLow = 5
methodSemaphorePayload = 6
methodSemaphoreOperation = 7
methodSyncpointPayload = 0x1C
methodSyncpointOperation = 0x1D

semaphoreAcquire = 1
semaphoreRelease = 2
semaphoreAcquireGreaterEqual = 4
semaphoreAcquireMask = 8

# the 3D engine's syncpoint increment, draw end, report semaphore and macro upload registers
reg3dSyncInfo = 0xB2
reg3dDrawEnd = 0x585
reg3dReportAddressHigh = 0x6C0
reg3dReportOperation = 0x6C3
reg3dMacroCode = 0x46
reg3dMacroStart = 0x48
reg3dFirmwareCall4 = 0x8C4
reg3dFirmwareArgs = 0xD00

# the inline-to-memory registers (also in the compute class), and compute's launch
regUploadLineLength = 0x60
regUploadLineCount = 0x61
regUploadAddressHigh = 0x62
regUploadAddressLow = 0x63
regUploadPitch = 0x64
regUploadExec = 0x6C
regUploadData = 0x6D
regComputeLaunch = 0xAF

# the DMA copy engine's registers
regCopySemaphoreHigh = 0x90
regCopySemaphorePayload = 0x92
regCopyLaunch = 0xC0
regCopyInHigh = 0x100
regCopyOutHigh = 0x102
regCopyPitchIn = 0x104
regCopyPitchOut = 0x105
regCopyLineLength = 0x106
regCopyLineCount = 0x107

# One method written: the channel's below 0x40, else the register of the engine on the subchannel.
pub fn call(mut g Gpu, c i64, sub i64, method i64, arg i64):
	g.stats.methods += 1
	if method >= macroMethods: return g.macroWord(c, sub, method, arg)
	g.flushMacro(c, sub)
	if method < channelMethods: return g.channelMethod(c, sub, method, arg)
	g.channels[c].engines[sub].regs[method] = arg
	class = g.channels[c].engines[sub].class
	if class == classThreeD: g.threeD(c, sub, method, arg)
	elif class == classCompute:
		if method == regComputeLaunch: g.stats.dispatches += 1
		else: g.inlineToMemory(c, sub, method, arg)
	elif class == classInline: g.inlineToMemory(c, sub, method, arg)
	elif class == classCopy: g.copyEngine(c, sub, method, arg)
	elif class != classTwoD and class != classChannel:
		g.note("method {method:x} on subchannel {sub}, which holds no class")

fn channelMethod(mut g Gpu, c i64, sub i64, method i64, arg i64):
	g.channels[c].regs[method] = arg
	if method == methodSetObject: g.bindObject(c, sub, arg & 0xFFFF)
	elif method == methodSemaphoreOperation: g.channelSemaphore(c, arg)
	elif method == methodSyncpointOperation: g.syncpointOperation(c, arg)

fn bindObject(mut g Gpu, c i64, sub i64, class i64):
	known = [classChannel, classThreeD, classCompute, classCopy, classTwoD, classInline]
	if not (class in known):
		ch = g.channels[c]
		where = "entry {ch.entryAt:x} word {ch.wordAt}, headers before: {ch.recentHeaders.map("{it:08x}").join(" ")}"
		g.note("class {class:x} bound to subchannel {sub} ({where})")
	g.channels[c].engines[sub].class = class

# the address space of a channel, -1 with a note when it has none
fn spaceOf(mut g Gpu, c i64):
	s = g.channels[c].space
	if s < 0: g.note("channel {c} touched memory without an address space")
	s

# A syncpoint operation (yuzu's FenceAction): bit 0 set increments the syncpoint (bits 8 and
# up), else waits for the value in the payload method, which has long passed.
fn syncpointOperation(mut g Gpu, c i64, arg i64):
	id = (arg >> 8) & 0xFF_FFFF
	if arg & 1 == 1: g.incrementSyncpoint(id)
	elif not g.hasReachedSyncpoint(id, g.channels[c].regs[methodSyncpointPayload]):
		g.note("a wait on syncpoint {id} that never reaches its value")

# The value a semaphore at `at` is released with: 4 bytes of payload, or a 64-bit payload and a
# 64-bit timestamp.
fn releaseSemaphore(mut g Gpu, s i64, at i64, payload i64, short bool):
	g.stats.semaphores += 1
	if short: return g.spaces[s].writeWord(at, payload)
	bytes = []
	bytes.pushU64le(payload)
	bytes.pushU64le(g.timestamp)
	g.spaces[s].write(at, bytes)

fn channelSemaphore(mut g Gpu, c i64, op i64):
	s = g.spaceOf(c)
	if s < 0: return
	high = g.channels[c].regs[methodSemaphoreHigh] & 0xFF
	at = high << 32 | g.channels[c].regs[methodSemaphoreLow]
	payload = g.channels[c].regs[methodSemaphorePayload] & 0xFFFF_FFFF
	kind = op & 0xF
	if kind == semaphoreRelease: return g.releaseSemaphore(s, at, payload, (op >> 24) & 1 == 1)
	if kind != semaphoreAcquire and kind != semaphoreAcquireGreaterEqual and
		kind != semaphoreAcquireMask:
		return g.note("semaphore operation {op:x}")
	g.stats.semaphores += 1
	value = g.spaces[s].readWord(at)
	met = value == payload
	if kind == semaphoreAcquireGreaterEqual: met = hasReachedValue(value, payload)
	if kind == semaphoreAcquireMask: met = value & payload != 0
	if not met: g.note("an acquire at {at:x} that never reaches {payload}")

fn threeD(mut g Gpu, c i64, sub i64, method i64, arg i64):
	# the firmware's fourth call answers by setting the macros' first firmware argument, which a
	# macro waits on (yuzu's ProcessFirmwareCall4)
	if method == reg3dFirmwareCall4: g.channels[c].engines[sub].regs[reg3dFirmwareArgs] = 1
	if method == reg3dSyncInfo: g.incrementSyncpoint(arg & 0xFFFF)   # once the work before it is done
	elif method == reg3dDrawEnd: g.drawEnded(c, sub)
	elif isDrawBeginEnd(method): g.drawBeginEnd(c, sub, method, arg)
	elif isInlineIndex(method): g.pushInlineIndices(c, sub, method, arg)
	elif isConstantBind(method): g.bindConstantBuffer(c, sub, method, arg)
	elif method == reg3dIndexBufferCount: g.channels[c].engines[sub].drawIndexed = true
	elif method == reg3dReportOperation: g.reportSemaphore(c, sub, arg)
	elif method == reg3dClearSurface: g.clearSurface(c, sub, arg)
	elif method >= reg3dConstantData and method < reg3dConstantData + constantDataWords:
		g.constantData(c, sub, arg)
	elif method >= reg3dMacroCodePointer and method <= reg3dMacroStart:
		g.macroUpload(c, sub, method, arg)

# The 3D engine's report semaphore (operation 0 releases the payload, 2 reports a counter, here
# zero): bit 28 says a single word.
fn reportSemaphore(mut g Gpu, c i64, sub i64, arg i64):
	s = g.spaceOf(c)
	if s < 0: return
	r = reg3dReportAddressHigh
	at = (g.channels[c].engines[sub].regs[r] & 0xFF) << 32 | g.channels[c].engines[sub].regs[r + 1]
	op = arg & 3
	if op != 0 and op != 2: return g.note("report semaphore operation {op}")
	payload = g.channels[c].engines[sub].regs[r + 2] & 0xFFFF_FFFF if op == 0 else 0
	g.releaseSemaphore(s, at, payload, (arg >> 28) & 1 == 1)

fn inlineToMemory(mut g Gpu, c i64, sub i64, method i64, arg i64):
	if method == regUploadExec: g.channels[c].engines[sub].uploaded = 0
	elif method == regUploadData: g.uploadWord(c, sub, arg)

# A word of an inline upload stored at the destination: the lines one after the other, `pitch`
# apart.
fn uploadWord(mut g Gpu, c i64, sub i64, w i64):
	s = g.spaceOf(c)
	if s < 0: return
	length = g.channels[c].engines[sub].regs[regUploadLineLength]
	total = length * g.channels[c].engines[sub].regs[regUploadLineCount]
	done = g.channels[c].engines[sub].uploaded
	high = g.channels[c].engines[sub].regs[regUploadAddressHigh] & 0xFF
	at = high << 32 | g.channels[c].engines[sub].regs[regUploadAddressLow]
	pitch = g.channels[c].engines[sub].regs[regUploadPitch]
	if length <= 0 or done >= total: return
	step = (total - done).min(4)
	for k in 0..step:
		line = (done + k) / length
		column = (done + k) % length
		g.spaces[s].write(
			at + line * (pitch if pitch > 0 else length) + column,
			[(w >> (8 * k)) & 0xFF]
		)
	g.channels[c].engines[sub].uploaded = done + step
	if done + step == total: g.stats.inlineUploads += 1

fn copyEngine(mut g Gpu, c i64, sub i64, method i64, arg i64):
	if method == regCopyLaunch: g.launchCopy(c, sub, arg)

# A DMA launch (bits 0-1: the transfer, 3-4: a semaphore to release, 7 and 8: whether the source
# and destination are pitch linear, 9: several lines). Block linear surfaces are copied as bytes
# in order.
fn launchCopy(mut g Gpu, c i64, sub i64, launch i64):
	s = g.spaceOf(c)
	if s < 0: return
	regs = g.channels[c].engines[sub].regs.copy()
	src = (regs[regCopyInHigh] & 0xFF) << 32 | regs[regCopyInHigh + 1]
	dst = (regs[regCopyOutHigh] & 0xFF) << 32 | regs[regCopyOutHigh + 1]
	length = regs[regCopyLineLength]
	lines = regs[regCopyLineCount] if (launch >> 9) & 1 == 1 else 1
	linear = (launch >> 7) & 1 == 1 and (launch >> 8) & 1 == 1
	if launch & 3 != 0:
		g.stats.copies += 1
		if not linear: g.stats.blockLinearCopies += 1
		stepIn = regs[regCopyPitchIn] if linear and lines > 1 else length
		stepOut = regs[regCopyPitchOut] if linear and lines > 1 else length
		for line in 0..lines:
			g.spaces[s].write(dst + line * stepOut, g.spaces[s].read(src + line * stepIn, length))
	semaphore = (launch >> 3) & 3
	if semaphore != 0:
		at = (regs[regCopySemaphoreHigh] & 0xFF) << 32 | regs[regCopySemaphoreHigh + 1]
		g.releaseSemaphore(s, at, regs[regCopySemaphorePayload] & 0xFFFF_FFFF, semaphore == 1)
