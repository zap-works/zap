# The supervisor calls by number (switchbrew: SVC): arguments in x0-x7, the result in w0 and
# outputs in x1 and on. Each call takes the kernel and the calling thread's index. A call that
# blocks leaves its thread waiting; whoever wakes it writes its result.

import recomp.switch.cpu.core

# the return addresses up the thread's frames (x30, then the x29 chain): where in the guest the
# call came from
fn callChain(c core.Cpu) str:
	out = ["{c.x[30]:x}"]
	was = core.checking
	core.checking = true
	fp = i64(c.x[29])
	loop 6:
		if fp < core.memory.base or fp + 16 > core.memory.end: break
		lr = i64(core.memory.load(fp + 8, 3))
		fp = i64(core.memory.load(fp, 3))
		if core.memory.faultAt >= 0:
			_ = core.memory.takeFault()
			break
		if lr == 0: break
		out.push("{lr:x}")
	core.checking = was
	out.join(" ")

# long: a dispatch of one line per call
pub fn supervisorCall(mut k Kernel, i i64, number i64):
	if k.traceCalls:
		c = k.threads[i].c
		k.log.push("t{k.threads[i].id} svc {number:x}({c.x[0]:x}, {c.x[1]:x}, {c.x[2]:x}, {c.x[3]:x}) at {c.pc - 4:x} from {callChain(c)}")
	match number:
		0x01: k.setHeapSize(i)
		0x02, 0x03, 0x0D, 0x0F, 0x10, 0x14, 0x19, 0x2C, 0x2D: k.reply(i, resultSuccess)
		0x04: k.mapMemory(i, true)
		0x05: k.mapMemory(i, false)
		0x06: k.queryMemory(i)
		0x07: k.exited = true
		0x08: k.svcCreateThread(i)
		0x09: k.startThread(i)
		0x0A: k.exitThread(i)
		0x0B: k.sleep(i, i64(k.arg(i, 0)))
		0x0C: k.answer(i, u64(k.threads[i].priority))
		0x0E:
			k.answer(i, 0)
			k.output(i, 2, 0xF)
		0x11: k.signalEvent(i)
		0x12, 0x17: k.clearEvent(i)
		0x13: k.mapSharedMemory(i)
		0x15: k.answer(i, u64(k.add(.TransferMemory(i64(k.arg(i, 1)), i64(k.arg(i, 2))))))
		0x16:
			k.objects.remove(k.arg32(i, 0))
			k.reply(i, resultSuccess)
		0x18: k.waitSynchronization(i)
		0x1A: k.arbitrateLock(i)
		0x1B:
			k.unlock(i64(k.arg(i, 0)))
			k.reply(i, resultSuccess)
		0x1C: k.waitConditionVariable(i)
		0x1D: k.signalConditionVariable(i)
		0x1E: k.threads[i].c.x[0] = u64(k.now())
		0x1F: k.connectToNamedPort(i)
		0x21: k.sendSyncRequest(i, k.arg32(i, 0), i64(k.threads[i].c.tpidrro))
		0x22: k.sendSyncRequest(i, k.arg32(i, 2), i64(k.arg(i, 0)))
		0x24: k.answer(i, 0x51)   # the process id
		0x25: k.answer(i, u64(k.threadId(k.arg32(i, 1))))
		0x26: k.breakProcess(i)
		0x27: k.outputDebugString(i)
		0x29: k.getInfo(i)
		0x34: k.waitForAddress(i)
		0x35: k.signalToAddress(i)
		0x45:
			e = k.events.len
			k.events.push(false)
			k.answer(i, u64(k.add(.Event(e))))
			k.output(i, 2, u64(k.add(.Event(e))))
		_:
			k.exited = true
			k.log.push("svc {number:x} is not written, at {k.threads[i].c.pc:x}")

# success, and v in x1
pub fn answer(mut k Kernel, i i64, v u64):
	k.reply(i, resultSuccess)
	k.output(i, 1, v)

fn setHeapSize(mut k Kernel, i i64):
	size = i64(k.arg(i, 1))
	if size > k.space.heapMax or size % 0x20_0000 != 0: return k.reply(i, resultInvalidSize)
	if size > 0: k.space.map(k.space.heapAt, size, typeHeap, permRead | permWrite)
	if size < k.space.heapSize: k.space.unmap(k.space.heapAt + size, k.space.heapSize - size)
	k.space.heapSize = size
	k.answer(i, u64(k.space.heapAt))

# svcMapMemory (src's bytes seen at dst instead, src closed meanwhile) and svcUnmapMemory: one span
# cannot show the same bytes at two addresses, so they move, and move back on the unmap
fn mapMemory(mut k Kernel, i i64, mapping bool):
	dst = i64(k.arg(i, 0))
	src = i64(k.arg(i, 1))
	size = i64(k.arg(i, 2))
	if mapping:
		k.space.map(dst, size, typeStack, permRead | permWrite)
		core.memory.moveBytes(src, dst, size)
		k.space.protect(src, size, 0)
	else:
		core.memory.moveBytes(dst, src, size)
		k.space.unmap(dst, size)
		k.space.protect(src, size, permRead | permWrite)
	k.code.forget(dst if mapping else src, size)
	k.reply(i, resultSuccess)

# svcQueryMemory: the MemoryInfo (base, size, type, attribute, permission, two counts) at x0
fn queryMemory(mut k Kernel, i i64):
	at = i64(k.arg(i, 0))
	r = k.space.query(i64(k.arg(i, 2)))
	core.memory.store(at, 3, u64(r.at))
	core.memory.store(at + 8, 3, u64(r.size))
	core.memory.store(at + 16, 2, u64(r.kind))
	core.memory.store(at + 24, 2, u64(r.perm))
	for o in [20, 28, 32, 36]:
		core.memory.store(at + o, 2, 0)
	k.answer(i, 0)

fn svcCreateThread(mut k Kernel, i i64):
	h = k.createThread(i64(k.arg(i, 1)), k.arg(i, 2), i64(k.arg(i, 3)), k.arg32(i, 4)) ??
		return k.reply(i, resultOutOfMemory)
	k.answer(i, u64(h))

fn startThread(mut k Kernel, i i64):
	t = k.threadOf(k.arg32(i, 0)) ?? return k.reply(i, resultInvalidHandle)
	k.threads[t].started = true
	k.reply(i, resultSuccess)

fn exitThread(mut k Kernel, i i64):
	k.threads[i].exited = true
	k.signalObject(k.threads[i].handle)

# the thread a handle names, by index
fn threadOf(k Kernel, h i64) i64?:
	if k.object(h) is Thread(t): return t
	none

fn threadId(k Kernel, h i64):
	t = k.threadOf(h) ?? return 0
	k.threads[t].id

# svcSleepThread: 0 and below yield; a time waits that many nanoseconds
fn sleep(mut k Kernel, i i64, ns i64):
	k.reply(i, resultSuccess)
	if ns <= 0: return
	k.threads[i].waiting = .Sleep
	k.threads[i].wakeAt = k.now() + ns * 192 / 10_000

fn outputDebugString(mut k Kernel, i i64):
	at = i64(k.arg(i, 0))
	text u8[] = (0..i64(k.arg(i, 1))).map(u8(core.memory.load(at + it, 0)))
	for line in text.text().lines():
		if line != "": k.log.push(line.copy())
	k.reply(i, resultSuccess)

fn breakProcess(mut k Kernel, i i64):
	k.log.push(
		"svcBreak({k.arg(i, 0):x}, {k.arg(i, 1):x}, {k.arg(i, 2):x}) at {k.threads[i].c.pc:x}"
	)
	k.exited = true

fn connectToNamedPort(mut k Kernel, i i64):
	at = i64(k.arg(i, 1))
	name = []
	while name.len < 12:
		b = u8(core.memory.load(at + name.len, 0))
		if b == 0: break
		name.push(b)
	s = k.newService(name.text())
	k.answer(i, u64(k.add(.Session(s))))
