# Set 0 on a device without push descriptors (Android's emulator, many phones): what a push
# writes goes into a set of the frame's own pools, bound in its place. The pools are emptied when
# the frame's slot begins again (its GPU work is done then); one that is full is followed by
# another, kept for the frames after.

# what a pool holds: sets, and the descriptors of each kind they may take
setsPerPool = 256

fn poolSizes():
	[
		DescriptorPoolSize(kind = u32(descSampledImage), count = 1024),
		DescriptorPoolSize(kind = u32(descStorageImage), count = 256),
		DescriptorPoolSize(kind = u32(descStorageBuffer), count = 512),
		DescriptorPoolSize(kind = u32(descUniformBuffer), count = 256)
	]

# VK_ERROR_OUT_OF_POOL_MEMORY and VK_ERROR_FRAGMENTED_POOL: the pool can give no more
outOfPool = -1_000_069_000
fragmentedPool = -12

extern "vulkan-1.dll" fn vkResetDescriptorPool(device i64, pool i64, flags i64) i32
# (vkUpdateDescriptorSets of push-like writes, found through the device: newSetPool)
extern loaded "vkUpdateDescriptorSets" fn updateSet(
	device i64,
	writeCount i64,
	writes WriteDescriptorSet[],
	copyCount i64,
	copies i64
)

# The writes a push would make, into a set of the frame's pools, bound at the bind point (0
# graphics, 1 compute) as set 0 of the layout.
fn bindWrittenSet(
	mut d Device,
	cmd i64,
	bindPoint i64,
	program i64,
	mut writes WriteDescriptorSet[]
):
	set = d.frameSet(d.programs[program].setLayout)
	for mut write in writes:
		write.set = set
	updateSet(d.device, writes.len, writes, 0, 0)
	vkCmdBindDescriptorSets(cmd, bindPoint, d.programs[program].layout, 0, 1, [set], 0, 0)

# a set of the layout from the frame's pools, a new pool made when the last is full
fn frameSet(mut d Device, layout i64):
	f = d.state.frame
	layouts = [layout]
	loop:
		used = d.frames[f].setPoolsUsed.max(1)
		d.frames[f].setPoolsUsed = used
		if used > d.frames[f].setPools.len:
			d.frames[f].setPools.push(d.newSetPool())
		result = vkAllocateDescriptorSets(
			d.device,
			DescriptorSetAllocateInfo(next = none, pool = d.frames[f].setPools[used - 1], layouts),
			out set
		)
		if result == 0: return set
		if result != outOfPool and result != fragmentedPool:
			check(result, "vkAllocateDescriptorSets")
		d.frames[f].setPoolsUsed = used + 1

fn newSetPool(d Device):
	sizes = poolSizes()
	info = DescriptorPoolCreateInfo(
		flags = 0,
		maxSets = u32(setsPerPool),
		sizeCount = u32(sizes.len),
		sizes
	)
	check(vkCreateDescriptorPool(d.device, info, 0, out pool), "vkCreateDescriptorPool")
	bindExtern(updateSet, deviceFunction(d.device, "vkUpdateDescriptorSets"))
	pool

# the frame's pools emptied, its slot beginning again
fn resetFrameSets(mut d Device):
	f = d.state.frame
	for pool in d.frames[f].setPools:
		check(vkResetDescriptorPool(d.device, pool, 0), "vkResetDescriptorPool")
	d.frames[f].setPoolsUsed = 0
