# A stage's constant buffers as its translation reads them: one array of words, bank b's word w at
# b * bankWords + w, filled from each buffer the draw bound to that stage and zeros elsewhere; only
# as many banks as the highest bound one.

import recomp.switch.shaders

# The words of the stage `kind`'s constant buffers (0 vertex to 4 pixel) read through the space.
pub fn constantWords(space AddressSpace, d DrawCall, kind i64) u32[]:
	bound = d.constantBuffers.filter(.kind == kind)
	if bound.isEmpty: return [0]
	banks = (bound.map(.slot).max() ?? 0) + 1
	words u32[] = zeros(banks * shaders.bankWords)
	for b in bound:
		n = (b.size / 4).min(shaders.bankWords)
		bytes = space.read(b.address, n * 4)
		for w in 0..n:
			words[b.slot * shaders.bankWords + w] = bytes.u32le(w * 4)
	words
