# Vulkan's memory for the RHI's blocks (core's memory.zap): the memory types the device has, a
# block allocated from one of them (mapped when host-visible) and ranges of it handed out.

import rhi.core

pub fn newMemory(physical i64) core.Memory:
	props = MemoryProperties()
	vkGetPhysicalDeviceMemoryProperties(physical, props)
	core.Memory(
		typeFlags = (0..i64(props.typeCount)).map(i64(props.types[it].flags)),
		blocks = []
	)

# the first memory type allowed by `bits` with every one of the `wanted` properties
fn memoryType(m core.Memory, bits i64, wanted i64):
	for i, typeFlag in m.typeFlags:
		if bits.bits(i, 1) == 1 and (typeFlag & wanted) == wanted: return i
	-1

# memory for a resource of these requirements: device-local, or host-visible and coherent
pub fn allocate(mut d Device, size i64, alignment i64, bits i64, hostVisible bool) core.Allocation:
	wanted = memHostVisible | memHostCoherent if hostVisible else memDeviceLocal
	t = d.state.memory.memoryType(bits, wanted)
	if t < 0 and not hostVisible:
		t = d.state.memory.memoryType(bits, 0)
	if t < 0:
		fail("rhi: no memory type for a resource")
	if d.state.memory.rangeIn(t, size, alignment) is a: return a
	bytes = size.max(core.blockSize)
	made = vkAllocateMemory(
		d.device,
		MemoryAllocateInfo(size = bytes, typeIndex = u32(t)),
		0,
		out memory
	)
	if made != 0:
		fail("rhi: vkAllocateMemory failed ({made}) for {bytes} bytes; {d.state.memoryText()}")
	mapped = 0
	if hostVisible:
		check(vkMapMemory(d.device, memory, 0, bytes, 0, out at), "vkMapMemory")
		mapped = at
	d.state.memory.rangeInNew(memory, t, bytes, mapped, size)
