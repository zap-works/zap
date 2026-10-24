# svcGetInfo: what the process asks the kernel about itself (switchbrew: SVC#InfoType), from the
# layout of space.zap. The alias region is the first half of the stack region, the stack region
# its second half.


# long: a dispatch of one line per kind
fn infoValue(mut k Kernel, kind i64, sub i64) u64?:
	s = k.space
	match kind:
		0: u64(0xF)   # the cores it may run on
		1: ~u64(0)   # the priorities it may use
		2: u64(s.aliasRegion.at)
		3: u64(s.aliasRegion.size)
		4: u64(s.heapRegion.at)
		5: u64(s.heapRegion.size)
		6: u64(s.heapMax + 0x0800_0000)
		7: u64(s.heapSize + 0x0400_0000)
		8: u64(0)   # no debugger
		9: u64(0)   # no resource limit handle
		10: u64(0)
		11: (u64(sub) * 0x9E37_79B9_7F4A_7C15) ^ 0x5851_F42D_4C95_7F2D   # entropy
		12: u64(s.aslrRegion.at)
		13: u64(s.aslrRegion.size)
		14: u64(s.stackRegion.at)
		15: u64(s.stackRegion.size)
		16, 17: u64(0)
		18: u64(i64(k.programId))
		19, 20: u64(0)
		21: u64(s.heapMax + 0x0800_0000)
		22: u64(s.heapSize + 0x0400_0000)
		23: u64(1)
		0xF000_0002: u64(k.now())
		_: none

fn getInfo(mut k Kernel, i i64):
	v = k.infoValue(k.arg32(i, 1), i64(k.arg(i, 3))) ?? return k.reply(i, resultInvalidEnum)
	k.answer(i, v)
