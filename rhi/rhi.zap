# The RHI the engine draws through: one device over one of two backends, chosen when the device
# is made: Vulkan 1.4 to 1.1 (rhi/vulkan) by default, Direct3D 12 (rhi/d3d12) when
# ZAP_RUN has gpu=d3d12 or the program was started with --d3d12. Every function here
# hands its call to the backend's function of the same name and signature, or to rhi/core's
# (the logic both backends share, over the device state they keep the same way and each one's
# API calls), and each names both backends, so a function one backend lacks (or takes
# differently) stops the build. What the backends share (the types of the calls, the programs
# the compiler built, memory ranges, the state bits, that logic) is rhi/core.

import rhi.core
import rhi.vulkan
import rhi.d3d12

pub type Device:
	backend i64   # core.backendVulkan or core.backendD3d12
	vk vulkan.Device
	dx d3d12.Device

# a device that is not made yet: what the engine holds until its window opens
pub fn emptyDevice() Device:
	Device(backend = core.backendVulkan, vk = vulkan.emptyDevice(), dx = d3d12.emptyDevice())

fn gpuWord():
	RunWord(
		"gpu",
		"d3d12 draws through Direct3D 12 (as --d3d12 does), anything else through Vulkan"
	)

# the backend the program asks for: Direct3D 12 with gpu=d3d12 in ZAP_RUN or --d3d12, else Vulkan
pub fn chosenBackend() i64:
	asked = (gpuWord().value() ?? "").lower()
	core.backendD3d12 if asked == "d3d12" or "--d3d12" in args else core.backendVulkan

# the device on the window (hwnd, hinstance), its swapchain of the window's size
pub fn newDevice(hwnd i64, hinstance i64, width i64, height i64) Device:
	backend = chosenBackend()
	d = emptyDevice()
	d.backend = backend
	if backend == core.backendD3d12:
		d.dx = d3d12.newDevice(hwnd, hinstance, width, height)
	else:
		d.vk = vulkan.newDevice(hwnd, hinstance, width, height)
	d

# "Vulkan" or "Direct3D 12"
pub fn backendName(d Device) str:
	"Direct3D 12" if d.backend == core.backendD3d12 else "Vulkan"

# whether programs may read texture arrays (Texture[]) at computed indices: Direct3D 12's always,
# Vulkan's with descriptor indexing (an array read at literal indices alone is read everywhere)
pub fn textureArrays(d Device) bool:
	d.backend == core.backendD3d12 or d.vk.support.bindless

# The size of a target drawn with the screen (a depth target) for a screen of w x h: its images'
# height by width when they hold the picture turned a quarter (Vulkan's screen on a phone turned
# from its natural way).
pub fn screenTargetSize(d Device, w i64, h i64) (i64, i64):
	turn = 0 if d.backend == core.backendD3d12 else d.vk.state.screenTurn
	(h, w) if turn % 2 == 1 else (w, h)

# whether programs may make textures of BC blocks: Direct3D 12's always, Vulkan's with
# textureCompressionBC (desktops; no Android GPU)
pub fn bcTextures(d Device) bool:
	d.backend == core.backendD3d12 or d.vk.support.blocks

# whether programs may make textures of ASTC blocks: Vulkan's with textureCompressionASTC_LDR
# (Android's GPUs), never Direct3D 12's
pub fn astcTextures(d Device) bool:
	d.backend != core.backendD3d12 and d.vk.support.astc

# whether indirect draws may be counted by the GPU: Direct3D 12's always, Vulkan's with
# drawIndirectCount (1.2's feature)
pub fn countedDraws(d Device) bool:
	d.backend == core.backendD3d12 or d.vk.support.countedDraw

# whether shaders may compute in f64 (a GPU file's): Vulkan's shaderFloat64, Direct3D 12's
# doubles
pub fn doubles(d Device) bool:
	d.dx.doubles if d.backend == core.backendD3d12 else d.vk.support.float64

# ---------- frames ----------

pub fn setVsync(mut d Device, on bool):
	if d.backend == core.backendD3d12:
		d.dx.setVsync(on)
	else:
		d.vk.setVsync(on)

# the frames shown in another window of the system from the next one (an app's, made again)
pub fn setWindow(mut d Device, hwnd i64, hinstance i64):
	if d.backend == core.backendD3d12:
		d.dx.setWindow(hwnd, hinstance)
	else:
		d.vk.setWindow(hwnd, hinstance)

# the swapchain is made again before the next frame
pub fn resize(mut d Device, width i64, height i64):
	if d.backend == core.backendD3d12:
		d.dx.state.resize(width, height)
	else:
		d.vk.state.resize(width, height)

# begins a frame; false when there is nothing to draw into (a minimized window)
pub fn beginFrame(mut d Device) bool:
	if d.backend == core.backendD3d12: return d.dx.beginFrame()
	d.vk.beginFrame()

pub fn endFrame(mut d Device):
	if d.backend == core.backendD3d12:
		d.dx.endFrame()
	else:
		d.vk.endFrame()

# ends the frame with the screen's pixels copied out (r, g, b, a, rows from the top)
pub fn endFrameCapturing(mut d Device) u8[]:
	if d.backend == core.backendD3d12: return d.dx.endFrameCapturing()
	d.vk.endFrameCapturing()

pub fn waitIdle(d Device):
	if d.backend == core.backendD3d12:
		d.dx.waitIdle()
	else:
		d.vk.waitIdle()

# The pipelines made so far written beside the executable for the next run (core's
# pipelines.zap), when one was made since they last were (a frame's end does it too, once none has
# been made for a while); ZAP_RUN=gpu prints what they cost.
pub fn savePipelineCache(mut d Device):
	if d.backend == core.backendD3d12:
		core.savePipelineCache(d.dx)
	else:
		core.savePipelineCache(d.vk)

# the screen's size as the swapchain has it
pub fn screenSize(d Device) (i64, i64):
	if d.backend == core.backendD3d12: return d.dx.state.screenSize()
	d.vk.state.screenSize()

# ---------- passes and draws ----------

# color: a texture, the screen or none
pub fn beginPass(mut d Device, color i64, depth i64, clearColor Vec4?, clearDepth bool):
	d.beginTargets(core.colorsOf(color), depth, clearColor, clearDepth)

# A pass into color targets (up to core.mostColorTargets textures of one size, or the screen
# alone; the pixel stage's values in their order) and a depth target (a texture or noTarget).
pub fn beginTargets(mut d Device, colors i64[], depth i64, clearColor Vec4?, clearDepth bool):
	if d.backend == core.backendD3d12:
		d.dx.beginTargets(colors, depth, clearColor, clearDepth)
	else:
		d.vk.beginTargets(colors, depth, clearColor, clearDepth)

# every color target to c, the depth to the far end
pub fn clearPass(mut d Device, c Vec4?, depth bool):
	d.clearTargets(c, -1, 1.0 if depth else none)

# The pass's color target `index` (-1 every one) cleared to c, its depth to `depth`; nothing
# outside a pass.
pub fn clearTargets(mut d Device, c Vec4?, index i64, depth f32?):
	if d.backend == core.backendD3d12:
		d.dx.clearTargets(c, index, depth)
	else:
		d.vk.clearTargets(c, index, depth)

# Ends the frame (as endFrame does) with the first level of a color target copied out on the
# way: its bytes as its format lays them out, rows from the top, once the GPU is done.
pub fn readTexture(mut d Device, id i64) u8[]:
	if d.backend == core.backendD3d12: return d.dx.readTexture(id)
	d.vk.readTexture(id)

# a blending per color target, for PipelineState's blends: the one already made of the same, if any
pub fn blendSet(mut d Device, move blends core.TargetBlend[]) i64:
	if d.backend == core.backendD3d12: return d.dx.state.blendSet(blends)
	d.vk.state.blendSet(blends)

# does nothing outside a pass
pub fn endPass(mut d Device):
	if d.backend == core.backendD3d12:
		d.dx.endPass()
	else:
		d.vk.endPass()

# the pass being drawn (its targets, whether it is open)
pub fn currentPass(d Device) core.Pass:
	if d.backend == core.backendD3d12: return d.dx.state.currentPass()
	d.vk.state.currentPass()

pub fn draw(mut d Device, call core.DrawCall):
	if d.backend == core.backendD3d12:
		d.dx.draw(call)
	else:
		d.vk.draw(call)

# a multisampled texture's samples averaged into a plain one of its size
pub fn resolve(mut d Device, from i64, into i64):
	if d.backend == core.backendD3d12:
		d.dx.resolve(from, into)
	else:
		d.vk.resolve(from, into)

# reuses the one already made of the same bindings and attributes
pub fn vertexLayout(mut d Device, move layout core.VertexLayout) i64:
	if d.backend == core.backendD3d12: return d.dx.state.vertexLayout(layout)
	d.vk.state.vertexLayout(layout)

# ---------- programs ----------

# the program the compiler built (shader(...))
pub fn newProgram(mut d Device, code str) i64:
	if d.backend == core.backendD3d12: return core.newProgram(d.dx, code)
	core.newProgram(d.vk, code)

# the compute program the compiler built (compute(...)), its pipeline made
pub fn newCompute(mut d Device, code str) i64:
	if d.backend == core.backendD3d12: return core.newCompute(d.dx, code)
	core.newCompute(d.vk, code)

# a compute program run between the frame's passes (the pass open ends), over the call's groups;
# its writes are read by what follows
pub fn dispatch(mut d Device, call core.ComputeCall):
	if d.backend == core.backendD3d12:
		d.dx.dispatch(call)
	else:
		d.vk.dispatch(call)

# Ends the frame (as endFrame does) with the first n bytes of a buffer copied out on the way:
# returned once the GPU is done (what a compute program wrote).
pub fn readBuffer(mut d Device, id i64, n i64) u8[]:
	if d.backend == core.backendD3d12: return d.dx.readBuffer(id, n)
	d.vk.readBuffer(id, n)

# a program's parameter block set to these words (its parameter structs as their packers wrote
# them, each part at its offset)
pub fn setParams(mut d Device, program i64, words u32[]):
	if d.backend == core.backendD3d12:
		d.dx.state.setParams(program, words)
	else:
		d.vk.state.setParams(program, words)

# The texture ids each of a program's texture arrays (Texture[], TextureArray[N]) lists, as
# its parameters' packers wrote them: what its draws read from here on (the RHI keeps a table of
# them per frame in flight, written again only when they change).
pub fn setTextureArrays(mut d Device, program i64, ids i64[,]):
	if d.backend == core.backendD3d12:
		d.dx.state.setTextureArrays(program, ids)
	else:
		d.vk.state.setTextureArrays(program, ids)

# A program's parameters as they are now copied for a draw made later in this frame's current
# pass (DrawCall's paramsCopy): the copy's number. The copy is the last one when they have not
# changed since.
pub fn copyParams(mut d Device, program i64) i64:
	if d.backend == core.backendD3d12: return core.copyParams(d.dx, program)
	core.copyParams(d.vk, program)

# what the device holds, on one line (core's memoryText)
pub fn memoryText(d Device) str:
	if d.backend == core.backendD3d12: return d.dx.state.memoryText()
	d.vk.state.memoryText()

# the most host-visible memory the device has held, in bytes
pub fn hostPeak(d Device) i64:
	if d.backend == core.backendD3d12: return d.dx.state.memory.peakHost
	d.vk.state.memory.peakHost

# what the last frame's draws bound and uploaded, and what they skipped as the same as before
pub fn drawStats(d Device) core.DrawStats:
	if d.backend == core.backendD3d12: return d.dx.state.drawStats()
	d.vk.state.drawStats()

# ---------- buffers ----------

# usage: core's buf... bits
pub fn newBuffer(mut d Device, size i64, usage i64, hostVisible bool) i64:
	if d.backend == core.backendD3d12: return core.newBuffer(d.dx, size, usage, hostVisible)
	core.newBuffer(d.vk, size, usage, hostVisible)

# the handle a draw names a buffer by (DrawCall's vertexBuffers, indexBuffer)
pub fn bufferHandle(d Device, id i64) i64:
	if d.backend == core.backendD3d12: return d.dx.state.bufferHandle(id)
	d.vk.state.bufferHandle(id)

# freed once the frames that may read it are done
pub fn destroyBuffer(mut d Device, id i64):
	if d.backend == core.backendD3d12:
		d.dx.state.destroyBuffer(id)
	else:
		d.vk.state.destroyBuffer(id)

# the bytes of a list of plain values (bytes, vertices, records) written into a buffer at `offset`
pub fn writeBuffer<T Copy>(mut d Device, id i64, offset i64, values T[]):
	if d.backend == core.backendD3d12:
		core.writeBuffer(d.dx, id, offset, values)
	else:
		core.writeBuffer(d.vk, id, offset, values)

pub fn writeBufferWords(mut d Device, id i64, offset i64, words u32[]):
	if d.backend == core.backendD3d12:
		core.writeBufferWords(d.dx, id, offset, words)
	else:
		core.writeBufferWords(d.vk, id, offset, words)

# only the first `count`
pub fn writeBufferFloats(mut d Device, id i64, offset i64, values f32[], count i64):
	if d.backend == core.backendD3d12:
		core.writeBufferFloats(d.dx, id, offset, values, count)
	else:
		core.writeBufferFloats(d.vk, id, offset, values, count)

# room for n bytes in this frame's memory: the buffer's handle, the offset there, the CPU's
# address to write them to
pub fn transient(mut d Device, n i64, alignment i64) (i64, i64, i64):
	if d.backend == core.backendD3d12: return core.transient(d.dx, n, alignment)
	core.transient(d.vk, n, alignment)

# ---------- textures ----------

# read sharp and clamped until setSampler
pub fn newTexture(mut d Device, desc core.TextureDesc) i64:
	if core.isAstcFormat(desc.format) and not d.astcTextures():
		fail("rhi: a texture of ASTC blocks on {d.backendName()}, which reads none (rhi.astcTextures)")
	if d.backend == core.backendD3d12: return core.newTexture(d.dx, desc)
	core.newTexture(d.vk, desc)

# freed once the frames that may read it are done
pub fn destroyTexture(mut d Device, id i64):
	if d.backend == core.backendD3d12:
		d.dx.state.destroyTexture(id)
	else:
		d.vk.state.destroyTexture(id)

# the pixels (4 bytes each, rows from the top) of a layer's first level replaced
pub fn writeTexture(mut d Device, id i64, layer i64, pixels u8[]):
	d.writeTextureLevel(id, 0, layer, pixels)

# The bytes of a level of a layer replaced, as the texture's format lays them out (4 bytes a
# pixel, or blocks of pixels: core.levelBytes): mip levels made ahead (a compressed texture's).
pub fn writeTextureLevel(mut d Device, id i64, level i64, layer i64, bytes u8[]):
	if d.backend == core.backendD3d12:
		core.writeTextureLevel(d.dx, id, level, layer, bytes)
	else:
		core.writeTextureLevel(d.vk, id, level, layer, bytes)

# each level below the first made from the one above it (halved, smoothed), every layer (not of
# a compressed texture: its levels are written)
pub fn generateMips(mut d Device, id i64):
	if d.backend == core.backendD3d12:
		d.dx.generateMips(id)
	else:
		d.vk.generateMips(id)

pub fn setSampler(mut d Device, id i64, desc core.SamplerDesc):
	if d.backend == core.backendD3d12:
		core.setSampler(d.dx, id, desc)
	else:
		core.setSampler(d.vk, id, desc)
