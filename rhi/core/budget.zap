# What the device holds, for a budget test and for ZAP_RUN=gpumemory: the driver's memory in
# blocks (device and host-visible, now and at its peak) and what the live textures, buffers and
# rings take of it.

fn megabytes(n i64):
	(n + 524_288) / 1_048_576

fn textureBytes(t Texture):
	total = 0
	for level in 0..t.levels:
		total += levelBytes(t.format, (t.width >> level).max(1), (t.height >> level).max(1))
	total * t.layers

# one line: device and host memory in MB (now and at the peak), the live textures' and buffers' bytes
pub fn memoryText(s DeviceState) str:
	textures = 0
	for t in s.textures:
		if t.live: textures += t.textureBytes()
	buffers = 0
	for b in s.buffers:
		if b.live: buffers += b.size
	m = s.memory
	"gpu memory: device {megabytes(m.held(false))} MB, device peak {megabytes(m.peakDevice)} MB, host {megabytes(m.held(true))} MB, host peak {megabytes(m.peakHost)} MB, live textures {megabytes(textures)} MB, live buffers {megabytes(buffers)} MB"
