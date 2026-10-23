# aoc:u, the add-on content (switchbrew: NS services#aoc:u): this console has none installed, and
# an add-on content's ids start at its application's id plus 0x1000.

addOnBaseOffset = 0x1000

fn addOnContent(mut k Kernel, i i64, req Request, mut res Response):
	match req.command:
		2, 3: res.u32(0)
		5: res.u64(i64(k.programId) + addOnBaseOffset)
		6: pass
		7:
			_, h = k.newEvent(false)
			res.copied.push(h)
		_: k.unwritten(i, req)
