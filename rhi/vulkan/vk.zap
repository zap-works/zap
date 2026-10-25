# The Vulkan functions the RHI calls (1.4's, 1.3's on a device that has no 1.4), from the loader
# (vulkan-1.dll), and the constants it passes. A structure goes as its address (an extern type, structs.zap; `mut` where Vulkan
# writes it), an array as a List; a handle is an i64; a VkBool32 an i64 of 0 or 1. A count
# Vulkan reads and writes is a Count, asked with the room of its list (no call passes NULL).
# The functions of a device's version or extensions (push descriptors: 1.4's or
# VK_KHR_push_descriptor's; host image copy: 1.4's), and the device's past 1.1 (Android's loader
# exports no others), are found through the device once it is made.

extern "vulkan-1.dll" fn vkCreateInstance(
	info InstanceCreateInfo,
	allocator i64,
	out instance i64
) i32
extern "vulkan-1.dll" fn vkEnumeratePhysicalDevices(
	instance i64,
	mut count Count,
	devices i64[]
) i32
extern "vulkan-1.dll" fn vkGetPhysicalDeviceProperties(device i64, mut properties DeviceProperties)
extern "vulkan-1.dll" fn vkGetPhysicalDeviceFeatures2(device i64, mut features Features2)
extern "vulkan-1.dll" fn vkGetPhysicalDeviceProperties2(device i64, mut properties Properties2)
extern "vulkan-1.dll" fn vkGetPhysicalDeviceFormatProperties2(
	device i64,
	format i64,
	mut properties FormatProperties2
)
extern "vulkan-1.dll" fn vkGetPhysicalDeviceImageFormatProperties2(
	device i64,
	info ImageFormatInfo2,
	mut properties ImageFormatProperties2
) i32
extern "vulkan-1.dll" fn vkGetPhysicalDeviceQueueFamilyProperties(
	device i64,
	mut count Count,
	properties QueueFamily[]
)
extern "vulkan-1.dll" fn vkGetPhysicalDeviceMemoryProperties(
	device i64,
	mut properties MemoryProperties
)
extern "vulkan-1.dll" fn vkEnumerateDeviceExtensionProperties(
	device i64,
	layer i64,
	mut count Count,
	properties ExtensionProperties[]
) i32
extern "vulkan-1.dll" fn vkCreateWin32SurfaceKHR(
	instance i64,
	info Win32SurfaceCreateInfo,
	allocator i64,
	out surface i64
) i32
extern "vulkan-1.dll" fn vkDestroySurfaceKHR(instance i64, surface i64, allocator i64)
extern "vulkan-1.dll" fn vkGetPhysicalDeviceSurfaceSupportKHR(
	device i64,
	family i64,
	surface i64,
	out supported u32
) i32
extern "vulkan-1.dll" fn vkGetPhysicalDeviceSurfaceCapabilitiesKHR(
	device i64,
	surface i64,
	mut capabilities SurfaceCapabilities
) i32
extern "vulkan-1.dll" fn vkGetPhysicalDeviceSurfacePresentModesKHR(
	device i64,
	surface i64,
	mut count Count,
	modes u32[]
) i32
extern "vulkan-1.dll" fn vkCreateDevice(
	physical i64,
	info DeviceCreateInfo,
	allocator i64,
	out device i64
) i32
extern "vulkan-1.dll" fn vkGetDeviceQueue(device i64, family i64, index i64, out queue i64)
extern "vulkan-1.dll" fn vkGetDeviceProcAddr(device i64, name str) i64
extern "vulkan-1.dll" fn vkDeviceWaitIdle(device i64) i32
extern "vulkan-1.dll" fn vkCreateSwapchainKHR(
	device i64,
	info SwapchainCreateInfo,
	allocator i64,
	out swapchain i64
) i32
extern "vulkan-1.dll" fn vkDestroySwapchainKHR(device i64, swapchain i64, allocator i64)
extern "vulkan-1.dll" fn vkGetSwapchainImagesKHR(
	device i64,
	swapchain i64,
	mut count Count,
	images i64[]
) i32
extern "vulkan-1.dll" fn vkAcquireNextImageKHR(
	device i64,
	swapchain i64,
	timeout i64,
	semaphore i64,
	fence i64,
	out index u32
) i32
extern "vulkan-1.dll" fn vkQueuePresentKHR(queue i64, info PresentInfo) i32
extern "vulkan-1.dll" fn vkQueueSubmit(queue i64, count i64, submit SubmitInfo, fence i64) i32
extern "vulkan-1.dll" fn vkCreateImageView(
	device i64,
	info ImageViewCreateInfo,
	allocator i64,
	out view i64
) i32
extern "vulkan-1.dll" fn vkDestroyImageView(device i64, view i64, allocator i64)
extern "vulkan-1.dll" fn vkCreateImage(
	device i64,
	info ImageCreateInfo,
	allocator i64,
	out image i64
) i32
extern "vulkan-1.dll" fn vkDestroyImage(device i64, image i64, allocator i64)
extern "vulkan-1.dll" fn vkGetImageMemoryRequirements(
	device i64,
	image i64,
	mut requirements MemoryRequirements
)
extern loaded fn vkGetDeviceImageMemoryRequirements(
	device i64,
	info DeviceImageMemoryRequirements,
	mut requirements MemoryRequirements2
)
extern "vulkan-1.dll" fn vkCreateBuffer(
	device i64,
	info BufferCreateInfo,
	allocator i64,
	out buffer i64
) i32
extern "vulkan-1.dll" fn vkDestroyBuffer(device i64, buffer i64, allocator i64)
extern "vulkan-1.dll" fn vkGetBufferMemoryRequirements(
	device i64,
	buffer i64,
	mut requirements MemoryRequirements
)
extern "vulkan-1.dll" fn vkAllocateMemory(
	device i64,
	info MemoryAllocateInfo,
	allocator i64,
	out memory i64
) i32
extern "vulkan-1.dll" fn vkFreeMemory(device i64, memory i64, allocator i64)
extern "vulkan-1.dll" fn vkBindBufferMemory(device i64, buffer i64, memory i64, offset i64) i32
extern "vulkan-1.dll" fn vkBindImageMemory(device i64, image i64, memory i64, offset i64) i32
extern "vulkan-1.dll" fn vkMapMemory(
	device i64,
	memory i64,
	offset i64,
	size i64,
	flags i64,
	out data i64
) i32
extern "vulkan-1.dll" fn vkCreateSampler(
	device i64,
	info SamplerCreateInfo,
	allocator i64,
	out sampler i64
) i32
extern "vulkan-1.dll" fn vkCreateShaderModule(
	device i64,
	info ShaderModuleCreateInfo,
	allocator i64,
	out module i64
) i32
extern "vulkan-1.dll" fn vkCreateDescriptorSetLayout(
	device i64,
	info DescriptorSetLayoutCreateInfo,
	allocator i64,
	out layout i64
) i32
extern "vulkan-1.dll" fn vkCreateDescriptorPool(
	device i64,
	info DescriptorPoolCreateInfo,
	allocator i64,
	out pool i64
) i32
extern "vulkan-1.dll" fn vkDestroyDescriptorPool(device i64, pool i64, allocator i64)
extern "vulkan-1.dll" fn vkAllocateDescriptorSets(
	device i64,
	info DescriptorSetAllocateInfo,
	out set i64
) i32
extern "vulkan-1.dll" fn vkUpdateDescriptorSets(
	device i64,
	writeCount i64,
	writes WriteDescriptorImages[],
	copyCount i64,
	copies i64
)
extern "vulkan-1.dll" fn vkCreatePipelineLayout(
	device i64,
	info PipelineLayoutCreateInfo,
	allocator i64,
	out layout i64
) i32
extern "vulkan-1.dll" fn vkCreateGraphicsPipelines(
	device i64,
	cache i64,
	count i64,
	info GraphicsPipelineCreateInfo,
	allocator i64,
	out pipeline i64
) i32
extern "vulkan-1.dll" fn vkCreateComputePipelines(
	device i64,
	cache i64,
	count i64,
	info ComputePipelineCreateInfo,
	allocator i64,
	out pipeline i64
) i32
extern "vulkan-1.dll" fn vkCreatePipelineCache(
	device i64,
	info PipelineCacheCreateInfo,
	allocator i64,
	out cache i64
) i32
extern "vulkan-1.dll" fn vkGetPipelineCacheData(
	device i64,
	cache i64,
	mut size Size,
	data u8[]
) i32
extern "vulkan-1.dll" fn vkCreateCommandPool(
	device i64,
	info CommandPoolCreateInfo,
	allocator i64,
	out pool i64
) i32
extern "vulkan-1.dll" fn vkAllocateCommandBuffers(
	device i64,
	info CommandBufferAllocateInfo,
	out buffer i64
) i32
extern "vulkan-1.dll" fn vkResetCommandBuffer(buffer i64, flags i64) i32
extern "vulkan-1.dll" fn vkBeginCommandBuffer(buffer i64, info CommandBufferBeginInfo) i32
extern "vulkan-1.dll" fn vkEndCommandBuffer(buffer i64) i32
extern "vulkan-1.dll" fn vkCreateFence(
	device i64,
	info FenceCreateInfo,
	allocator i64,
	out fence i64
) i32
extern "vulkan-1.dll" fn vkWaitForFences(
	device i64,
	count i64,
	fences i64[],
	waitAll i64,
	timeout i64
) i32
extern "vulkan-1.dll" fn vkResetFences(device i64, count i64, fences i64[]) i32
extern "vulkan-1.dll" fn vkCreateSemaphore(
	device i64,
	info SemaphoreCreateInfo,
	allocator i64,
	out semaphore i64
) i32
extern "vulkan-1.dll" fn vkCreateQueryPool(
	device i64,
	info QueryPoolCreateInfo,
	allocator i64,
	out pool i64
) i32
extern "vulkan-1.dll" fn vkCmdResetQueryPool(buffer i64, pool i64, first i64, count i64)
extern "vulkan-1.dll" fn vkCmdWriteTimestamp(buffer i64, stage i64, pool i64, query i64)
extern "vulkan-1.dll" fn vkGetQueryPoolResults(
	device i64,
	pool i64,
	first i64,
	count i64,
	size i64,
	results i64[],
	stride i64,
	flags i64
) i32
extern loaded fn vkCmdBeginRendering(buffer i64, info RenderingInfo)
extern loaded fn vkCmdEndRendering(buffer i64)
extern "vulkan-1.dll" fn vkCmdPipelineBarrier(
	buffer i64,
	srcStage i64,
	dstStage i64,
	dependency i64,
	memoryCount i64,
	memory MemoryBarrier[],
	bufferCount i64,
	buffers i64, imageCount i64, images ImageMemoryBarrier[])
extern "vulkan-1.dll" fn vkCmdBindPipeline(buffer i64, bindPoint i64, pipeline i64)
extern "vulkan-1.dll" fn vkCmdBindDescriptorSets(
	buffer i64,
	bindPoint i64,
	layout i64,
	first i64,
	count i64,
	sets i64[],
	offsetCount i64,
	offsets i64
)
extern "vulkan-1.dll" fn vkCmdBindVertexBuffers(
	buffer i64,
	first i64,
	count i64,
	buffers i64[],
	offsets i64[]
)
extern "vulkan-1.dll" fn vkCmdBindIndexBuffer(buffer i64, index i64, offset i64, kind i64)
extern "vulkan-1.dll" fn vkCmdDraw(
	buffer i64,
	vertices i64,
	instances i64,
	firstVertex i64,
	firstInstance i64
)
extern "vulkan-1.dll" fn vkCmdDrawIndexed(
	buffer i64,
	indices i64,
	instances i64,
	firstIndex i64,
	vertexOffset i64,
	firstInstance i64
)
extern "vulkan-1.dll" fn vkCmdDrawIndirect(
	buffer i64,
	commands i64,
	offset i64,
	count i64,
	stride i64
)
extern "vulkan-1.dll" fn vkCmdDrawIndexedIndirect(
	buffer i64,
	commands i64,
	offset i64,
	count i64,
	stride i64
)
extern loaded fn vkCmdDrawIndirectCount(
	buffer i64,
	commands i64,
	offset i64,
	counts i64,
	countOffset i64,
	most i64,
	stride i64
)
extern loaded fn vkCmdDrawIndexedIndirectCount(
	buffer i64,
	commands i64,
	offset i64,
	counts i64,
	countOffset i64,
	most i64,
	stride i64
)
extern "vulkan-1.dll" fn vkCmdDispatch(buffer i64, x i64, y i64, z i64)
extern "vulkan-1.dll" fn vkCmdSetViewport(buffer i64, first i64, count i64, viewport Viewport)
extern "vulkan-1.dll" fn vkCmdSetScissor(buffer i64, first i64, count i64, rect Rect2D)
extern loaded fn vkCmdSetCullMode(buffer i64, mode i64)
extern loaded fn vkCmdSetFrontFace(buffer i64, face i64)
extern loaded fn vkCmdSetDepthTestEnable(buffer i64, on i64)
extern loaded fn vkCmdSetDepthWriteEnable(buffer i64, on i64)
extern loaded fn vkCmdSetDepthCompareOp(buffer i64, op i64)
extern loaded fn vkCmdSetDepthBiasEnable(buffer i64, on i64)
extern "vulkan-1.dll" fn vkCmdSetDepthBias(buffer i64, constant f32, clamp f32, slope f32)
extern "vulkan-1.dll" fn vkCmdCopyBuffer(buffer i64, src i64, dst i64, count i64, region BufferCopy)
extern "vulkan-1.dll" fn vkCmdCopyBufferToImage(
	buffer i64,
	src i64,
	image i64,
	layout i64,
	count i64,
	region BufferImageCopy
)
extern "vulkan-1.dll" fn vkCmdCopyImageToBuffer(
	buffer i64,
	image i64,
	layout i64,
	dst i64,
	count i64,
	region BufferImageCopy
)
extern "vulkan-1.dll" fn vkCmdBlitImage(
	buffer i64,
	src i64,
	srcLayout i64,
	dst i64,
	dstLayout i64,
	count i64,
	region ImageBlit,
	filter i64
)
extern "vulkan-1.dll" fn vkCmdResolveImage(
	buffer i64,
	src i64,
	srcLayout i64,
	dst i64,
	dstLayout i64,
	count i64,
	region ImageResolve
)
extern "vulkan-1.dll" fn vkCmdClearAttachments(
	buffer i64,
	count i64,
	attachments ClearAttachment[],
	rectCount i64,
	rect ClearRect
)
extern loaded fn vkCmdPushDescriptorSet(
	buffer i64,
	bindPoint i64,
	layout i64,
	set i64,
	count i64,
	writes WriteDescriptorSet[]
)
extern loaded fn vkCopyMemoryToImage(device i64, info CopyMemoryToImageInfo) i32
extern loaded fn vkTransitionImageLayout(
	device i64,
	count i64,
	transitions HostImageLayoutTransitionInfo
) i32
# vkGetPipelineCacheData asked for the size only (no data: NULL)
extern loaded "vkGetPipelineCacheData" fn pipelineCacheSize(
	device i64,
	cache i64,
	mut size Size,
	data i64
) i32

# image layouts
pub layoutUndefined = 0
pub layoutGeneral = 1
pub layoutColorAttachment = 2
pub layoutDepthAttachment = 3   # DEPTH_STENCIL_ATTACHMENT_OPTIMAL
pub layoutShaderRead = 5
pub layoutTransferSrc = 6
pub layoutTransferDst = 7
pub layoutPresent = 1_000_001_002

# pipeline stages and accesses
pub stageAllCommands = 0x1_0000
pub stageBottom = 0x2000
pub stageTop = 1
pub stageDrawIndirect = 2
pub stageVertexInput = 4
pub stageVertexShader = 8
pub stageFragmentShader = 0x80
pub stageFragmentTests = 0x300   # early and late
pub stageColorOutput = 0x400
pub stageCompute = 0x800
pub stageTransfer = 0x1000
pub stageHost = 0x4000
pub accessAll = 0x1_FFFF   # every read and write access bit of Vulkan 1.0
pub accessIndirectRead = 1
pub accessIndexRead = 2
pub accessVertexRead = 4
pub accessUniformRead = 8
pub accessShaderRead = 0x20
pub accessShaderWrite = 0x40
pub accessColorRead = 0x80
pub accessColorWrite = 0x100
pub accessDepthRead = 0x200
pub accessDepthWrite = 0x400
pub accessTransferRead = 0x800
pub accessTransferWrite = 0x1000
pub accessHostRead = 0x2000

# image usages
pub imgTransferSrc = 1
pub imgTransferDst = 2
pub imgSampled = 4
pub imgStorage = 8
pub imgColorAttachment = 0x10
pub imgDepthAttachment = 0x20
pub imgHostTransfer = 0x40_0000   # host image copy

# format features (64 bits)
pub formatHostTransfer = 0x4000_0000_0000

# memory properties
pub memDeviceLocal = 1
pub memHostVisible = 2
pub memHostCoherent = 4   # the CPU's writes seen without flushing

# descriptor types
pub descSampledImage = 1   # a combined image sampler
pub descStorageImage = 3
pub descUniformBuffer = 6
pub descStorageBuffer = 7

pub aspectColor = 1
pub aspectDepth = 2
pub aspectStencil = 4

pub resultSuccess = 0
pub resultIncomplete = 5   # more there than the room given
pub resultSuboptimal = 1_000_001_003   # the swapchain still works but no longer fits
pub resultOutOfDate = -1_000_001_004   # the swapchain must be made again
