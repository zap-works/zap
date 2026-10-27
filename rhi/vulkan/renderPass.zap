# Passes on a device without dynamic rendering (1.1's, or 1.2's without VK_KHR_dynamic_rendering:
# Android's emulator, many phones): a render pass of one subpass for each set of formats, samples
# and loads (made once, kept), its attachments in the layouts the barriers leave them in (so it
# moves none), and a framebuffer of the pass's views, made when the pass begins and retired with
# the frame. A pipeline is made for the render pass of its formats that loads, which every render
# pass of those formats is compatible with.

import rhi.core

pub extern type AttachmentDescription:
	flags u32 = 0
	format u32
	samples u32
	loadOp u32
	storeOp u32 = 0   # STORE
	stencilLoadOp u32 = 2   # DONT_CARE
	stencilStoreOp u32 = 1   # DONT_CARE
	initialLayout u32
	finalLayout u32

pub extern type AttachmentReference:
	attachment u32
	layout u32

pub extern type SubpassDescription:
	flags u32 = 0
	bindPoint u32 = 0   # GRAPHICS
	inputCount u32 = 0
	inputs i64 = 0
	colorCount u32
	colors ref AttachmentReference[]
	resolves i64 = 0
	depth ref AttachmentReference?
	preserveCount u32 = 0
	preserves i64 = 0

pub extern type RenderPassCreateInfo:
	sType u32 = 38
	next i64 = 0
	flags u32 = 0
	attachmentCount u32
	attachments ref AttachmentDescription[]
	subpassCount u32 = 1
	subpass ref SubpassDescription
	dependencyCount u32 = 0
	dependencies i64 = 0

pub extern type FramebufferCreateInfo:
	sType u32 = 37
	next i64 = 0
	flags u32 = 0
	renderPass i64
	attachmentCount u32
	attachments ref i64[]
	width u32
	height u32
	layers u32 = 1

pub extern type ClearValue:
	value f32[4]   # a color, or the depth first

pub extern type RenderPassBeginInfo:
	sType u32 = 43
	next i64 = 0
	renderPass i64
	framebuffer i64
	area Rect2D
	clearCount u32
	clears ref ClearValue[]

extern "vulkan-1.dll" fn vkCreateRenderPass(
	device i64,
	info RenderPassCreateInfo,
	allocator i64,
	out pass i64
) i32
extern "vulkan-1.dll" fn vkCreateFramebuffer(
	device i64,
	info FramebufferCreateInfo,
	allocator i64,
	out framebuffer i64
) i32
pub extern "vulkan-1.dll" fn vkDestroyFramebuffer(device i64, framebuffer i64, allocator i64)
extern "vulkan-1.dll" fn vkCmdBeginRenderPass(buffer i64, info RenderPassBeginInfo, contents i64)
pub extern "vulkan-1.dll" fn vkCmdEndRenderPass(buffer i64)

# a framebuffer retired with its frame
pub retiredFramebuffer = core.retiredOwn + 1

loadOpLoad = 0
loadOpClear = 1

# The render pass into color targets of `formats` and a depth target of `depthFormat`
# (fmtUndefined none), of `samples`, each cleared or loaded: made the first time, then kept.
pub fn renderPassOf(
	mut d Device,
	formats i64[],
	depthFormat i64,
	samples i64,
	clearColor bool,
	clearDepth bool
) i64:
	key = "{formats.map("{it}").join(",")};{depthFormat};{samples};{clearColor};{clearDepth}"
	if d.renderPasses.get(key) is known: return known
	attachments = formats.map(AttachmentDescription(
		format = u32(it),
		samples = u32(samples),
		loadOp = u32(loadOpClear if clearColor else loadOpLoad),
		initialLayout = u32(layoutColorAttachment),
		finalLayout = u32(layoutColorAttachment)))
	colors = (0..formats.len).map(
		AttachmentReference(attachment = u32(it), layout = u32(layoutColorAttachment))
	)
	withDepth = depthFormat != core.fmtUndefined
	if withDepth:
		attachments.push(AttachmentDescription(
			format = u32(depthFormat),
			samples = u32(samples),
			loadOp = u32(loadOpClear if clearDepth else loadOpLoad),
			initialLayout = u32(layoutDepthAttachment),
			finalLayout = u32(layoutDepthAttachment)))
	depth = AttachmentReference(attachment = u32(formats.len), layout = u32(layoutDepthAttachment))
	subpass = SubpassDescription(
		colorCount = u32(colors.len),
		colors,
		depth = depth if withDepth else none
	)
	info = RenderPassCreateInfo(attachmentCount = u32(attachments.len), attachments, subpass)
	check(vkCreateRenderPass(d.device, info, 0, out made), "vkCreateRenderPass")
	d.renderPasses[key] = made
	made

# The pass begun (its render pass) on a framebuffer of its views (colors, then the depth's when
# there is one), the colors cleared to clearColor and the depth to 1 where they are cleared.
pub fn beginRenderPass(mut d Device, cmd i64, views i64[], clearColor Vec4?, clearDepth bool):
	area = d.onTargets(0, 0, d.state.pass.width, d.state.pass.height)
	first = d.state.pass.colorFormat
	formats i64[] = [] if first == core.fmtUndefined else [first]
	formats.extend(core.unpackFormats(d.state.pass.extraFormats))
	depthFormat = d.state.pass.depthFormat
	samples = d.state.pass.samples
	renderPass = d.renderPassOf(formats, depthFormat, samples, clearColor != none, clearDepth)
	info = FramebufferCreateInfo(
		renderPass,
		attachmentCount = u32(views.len),
		attachments = views,
		width = area.width,
		height = area.height
	)
	check(vkCreateFramebuffer(d.device, info, 0, out framebuffer), "vkCreateFramebuffer")
	d.state.retire(
		core.Retired(
			kind = retiredFramebuffer,
			handle = framebuffer,
			block = -1,
			offset = 0,
			size = 0
		)
	)
	color = clearColor ?? Vec4(r = 0.0, g = 0.0, b = 0.0, a = 0.0)
	clears = fill(formats.len, ClearValue(value = [color.r, color.g, color.b, color.a]))
	clears.push(ClearValue(value = [1.0, 0.0, 0.0, 0.0]))
	begin = RenderPassBeginInfo(
		renderPass,
		framebuffer,
		area,
		clearCount = u32(clears.len),
		clears
	)
	vkCmdBeginRenderPass(cmd, begin, 0)   # INLINE
