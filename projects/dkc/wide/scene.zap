# Donkey Kong Country's widescreen, as DKC1Recomp does it (README.md, "Widescreen as DKC1Recomp
# does it"), on recomp.snes's wide drawing (console/wide.zap): what a level is, where its camera may
# go and what its terrain is beyond the 256 pixels (level.zap), the cartridge's windows widened
# by the patches cartridge/patches.zap writes, and the helpers those call: the vertical rope's x
# and the banana writer's carry. Installed into the console by the program's setup line.

import recomp.snes.console

mut why = 1   # why the scene is centred: 1 not a level's registers, 2 the camera range too short,
              # 3 no terrain layer, 4 the ROM's map does not match the live tilemap

pub fn install():
	console.wideHooks = console.WideHooks(
		judge = judgeScene,
		sceneId = levelSource,
		marginPixel = marginPixel
	)

fn wramWord(at i64):
	console.wramByte(at) | (i64(console.wramByte(at + 1)) << 8)

# Line 0 ended: judges the scene for the frame that begins and where the native picture sits in
# the wide one. The level's camera range (1B23, 1B25) must span both margins; the shift is
# DKC1Recomp's `glide`: at a level's edge the picture is pinned inside it, the shift released one
# pixel for each 8 the camera travels.
fn judgeScene() console.SceneJudgement:
	why = 1
	if not console.isPlainMode1(): return console.SceneJudgement(why = why)
	lower = wramWord(0x1B23)
	upper = wramWord(0x1B25)
	why = 2
	if upper < lower + console.sideLeft + console.sideRight:
		return console.SceneJudgement(why = why)
	why = 3
	if not calibrateTerrain(): return console.SceneJudgement(why = why)
	bias = console.edgeBias(wramWord(0x088B), lower, upper, 8)
	console.SceneJudgement(on = true, why = 0, bias = bias)

# The vertical rope's x (relative to the camera) as its routine computed it, kept for the upper-OAM
# merge after the cull has taken a biased copy.
mut ropeX u16 = 0

pub fn noteRope(relative u16):
	ropeX = relative

# the rope's cull key: its x moved right by the left margin, so the routine's test for x < 0 lets
# the margin through (its test against 256 is widened by widenSpan)
pub fn ropeBias(relative u16) u16:
	relative + u16(console.sideLeft) if console.growsLogic() else relative

# The rope's size bit merged into the slot's upper-OAM word: natively OR-ed in; wide, the slot's
# size and x-high bits set afresh, the x-high bit as the rope's x says (bit 8, the margins' 9th bit).
pub fn ropeMerge(mask u16, existing u16) u16:
	if not console.growsLogic(): return mask | existing
	xHigh = mask >> 1
	merged = (existing & ~(mask | xHigh)) | mask
	merged | xHigh if ropeX & 0x100 != 0 else merged

# the carry the banana writer's asl takes from its x's high byte: the sign (bit 7), wide bit 8
pub fn isHighBitSet(high u8) bool:
	high & 1 != 0 if console.growsLogic() else high & 0x80 != 0
