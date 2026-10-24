# /dev/nvhost-ctrl, the host's syncpoints and their events (switchbrew: NV services#nvhost-ctrl):
# a syncpoint counts what the GPU finished; a client reads it, waits for a value, or has an event
# signaled when it gets there. The GPU's work completes when it is submitted, so a wait on a
# value some job will reach later is answered with a time out, and the event is signaled by
# `signalSyncpointEvents` after the work that reaches it.

import recomp.switch.maxwell

slotCount = 64

# the event slot's state: the syncpoint and value it waits for while armed
pub type NvSlot:
	event i64 = -1
	syncpoint i64 = 0
	threshold i64 = 0
	armed bool = false
	signaled bool = false

fn ctrlIoctl(mut k Kernel, cmd i64, mut io u8[]) i64:
	k.makeSlots()
	match cmd:
		0x0014:   # SYNCPT_READ
			put32(io, 4, k.gpu.syncpoints[get32(io, 0) % 192])
			nvOk
		0x0015:   # SYNCPT_INCR
			k.gpu.incrementSyncpoint(get32(io, 0))
			k.signalSyncpointEvents()
			nvOk
		0x0016, 0x0019: k.syncpointWait(io)   # SYNCPT_WAIT, SYNCPT_WAITEX
		0x001A:   # SYNCPT_READ_MAX
			put32(io, 4, k.gpu.syncpoints[get32(io, 0) % 192])
			nvOk
		0x001C: k.clearSlot(get32(io, 0))   # SYNCPT_CLEAR_EVENT_WAIT
		0x001D, 0x001E: k.eventWait(cmd == 0x001E, io)   # SYNCPT_WAIT_EVENT, _EX
		0x001F, 0x0020, 0x0021, 0x0022: nvOk   # ALLOC_EVENT, FREE_EVENT, FREE_EVENT_BATCH, GET_SHIFT
		0x0017, 0x0018: nvOk   # MODULE_MUTEX, MODULE_REGRDWR
		_: nvNotImplemented

# the event slots made on the first ioctl
fn makeSlots(mut k Kernel):
	while k.nv.slots.len < slotCount:
		k.nv.slots.push(NvSlot())

fn syncpointWait(mut k Kernel, mut io u8[]):
	id = get32(io, 0)
	if k.gpu.hasReachedSyncpoint(id, get32(io, 4)):
		put32(io, 12, k.gpu.syncpoints[id])
		return nvOk
	nvTimeout

# A wait for a syncpoint to reach a value, on an event slot (the slot in the value for the
# extended form, else the first not armed): done at once when it has, else the slot is armed
# and the value says which event to wait on (EventSlot | SyncptId << 16 | 1 << 28).
fn eventWait(mut k Kernel, extended bool, mut io u8[]):
	id = get32(io, 0)
	threshold = get32(io, 4)
	slot = get32(io, 12) & 0x3F if extended else k.freeSlot()
	if k.gpu.hasReachedSyncpoint(id, threshold):
		put32(io, 12, k.gpu.syncpoints[id])
		k.nv.slots[slot].signaled = true
		if k.nv.slots[slot].event >= 0: k.setEvent(k.nv.slots[slot].event, true)
		return nvOk
	k.nv.slots[slot].syncpoint = id
	k.nv.slots[slot].threshold = threshold
	k.nv.slots[slot].armed = true
	k.nv.slots[slot].signaled = false
	if k.nv.slots[slot].event >= 0: k.setEvent(k.nv.slots[slot].event, false)
	put32(io, 12, slot | (id & 0xFFF) << 16 | 1 << 28)
	nvTimeout

# the first slot that is not armed
fn freeSlot(k Kernel):
	for s in 0..slotCount:
		if not k.nv.slots[s].armed: return s
	0

fn clearSlot(mut k Kernel, slot i64):
	if slot < 0 or slot >= slotCount: return nvBadParameter
	k.nv.slots[slot].signaled = false
	if k.nv.slots[slot].event >= 0: k.setEvent(k.nv.slots[slot].event, false)
	nvOk

# The slot an event id of QueryEvent names: EventSlot | SyncptId << 16 | 1 << 28, or the old
# EventSlot | SyncptId << 4; -1 for one out of range.
fn ctrlSlotOfEvent(mut k Kernel, id i64):
	k.makeSlots()
	slot = id & 0xFFFF if (id >> 28) & 1 == 1 else id & 0xF
	-1 if slot >= slotCount else slot

# a handle to the slot's event, made signaled when the slot is
fn slotEventHandle(mut k Kernel, slot i64) i64:
	if k.nv.slots[slot].event < 0:
		e, h = k.newEvent(k.nv.slots[slot].signaled)
		k.nv.slots[slot].event = e
		return h
	k.add(.Event(k.nv.slots[slot].event))

# The slots armed for a syncpoint value that was reached: signaled.
fn signalSyncpointEvents(mut k Kernel):
	for s in 0..k.nv.slots.len:
		if k.nv.slots[s].armed and
			k.gpu.hasReachedSyncpoint(k.nv.slots[s].syncpoint, k.nv.slots[s].threshold):
			k.nv.slots[s].armed = false
			k.nv.slots[s].signaled = true
			if k.nv.slots[s].event >= 0: k.setEvent(k.nv.slots[s].event, true)
