# The presented frame drawn by the renderer: the last frame's clears and draws replayed in a frame
# of the window's GPU, and the target at the presented buffer's GPU address read back as the
# picture (Kernel.frame). A frame whose buffer no target holds ends with the window's own frame.

import engine
import recomp.switch.horizon
import recomp.switch.maxwell
import recomp.switch.render

# The picture of the last presented frame, none when the renderer drew no target there.
pub fn renderedPicture(
	mut rp render.Replayer,
	mut window engine.PixelWindow,
	mut k horizon.Kernel
) image.Image?:
	if k.gpu.channels.isEmpty or k.display.queue.isEmpty: return none
	s = k.gpu.channels[0].space
	if s < 0: return none
	if not window.window.nextFrame(window.frames, escEnds = false): return none
	rp.replay(window.renderer, k.gpu.spaces[s], k.gpu.lastFrame)
	host = k.display.queue[len - 1].address
	address = k.gpu.spaces[s].gpuAddressOf(host) ?? -1
	if rp.pictureAt(address) is picture: return picture
	k.gpu.note("presented {host:x} (GPU {address:x}) is no target of {rp.targetAddresses()}")
	window.renderer.showFrame(window.window, window.frames)
	none
