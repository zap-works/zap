# The picture of the buffer the game last presented, read from guest memory: rows at the buffer's
# pitch, or its block-linear layout undone (textures/), RGBA8888 or RGB565 (Android's PIXEL_FORMATs
# 1 and 4) made RGBA8. What the GPU drew into a buffer is
# in guest memory when the drawing is done there; a renderer that draws on the host GPU shows its
# own picture instead.

import image
import recomp.switch.cpu
import recomp.switch.textures

# NvLayout's block-linear, and the pixel formats read
layoutBlockLinear = 3
formatRgb565 = 4

# the bytes of a buffer's pixels as RGBA8
fn rgbaOf(move raw u8[], pixels i64, format i64):
	if format != formatRgb565: return raw
	out u8[] = zeros(pixels * 4)
	for k in 0..pixels:
		v = i64(raw.u16le(2 * k))
		out[4 * k] = ((v >> 11) & 31) * 255 / 31
		out[4 * k + 1] = ((v >> 5) & 63) * 255 / 63
		out[4 * k + 2] = (v & 31) * 255 / 31
		out[4 * k + 3] = 255
	out

# The GPU's counts and notes after a run, a line each; none when no channel was opened.
pub fn gpuReport(k Kernel) str[]:
	if k.gpu.channels.isEmpty: return []
	st = k.gpu.stats
	counts = "gpu: {k.display.presented} frames, {st.draws} draws, {st.macroCalls} macro calls, {st.dispatches} dispatches, {st.copies} copies, {st.inlineUploads} uploads, {st.semaphores} semaphores, {st.syncpointIncrements} syncpoint increments"
	lines = [counts]
	lines.extend(k.gpu.notes.map("gpu note: {it}"))
	lines

# The last presented buffer's picture, none before the first or when it lies outside memory.
pub fn screenPicture(k Kernel) image.Image?:
	if k.display.queue.isEmpty: return none
	p = k.display.queue[len - 1]
	rowBytes = p.width * (2 if p.format == formatRgb565 else 4)
	if p.address <= 0 or p.width <= 0 or p.height <= 0: return none
	m = cpu.memory
	at = p.address - m.base
	if p.layout == layoutBlockLinear:
		s = textures.Surface(rowBytes, rows = p.height, blockHeight = p.blockHeightLog2)
		if at < 0 or at + s.layoutBytes() > m.bytes.len: return none
		return image.fromBytes(
			p.width,
			p.height,
			rgbaOf(s.unswizzle(m.bytes, at), p.width * p.height, p.format)
		)
	pitch = p.pitch if p.pitch > 0 else rowBytes
	if at < 0 or at + pitch * p.height > m.bytes.len: return none
	out u8[] = zeros(rowBytes * p.height)
	for y in 0..p.height:
		for x in 0..rowBytes:
			out[y * rowBytes + x] = m.bytes[at + y * pitch + x]
	image.fromBytes(p.width, p.height, rgbaOf(out, p.width * p.height, p.format))
