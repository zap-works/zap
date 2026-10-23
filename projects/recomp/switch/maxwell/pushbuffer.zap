# GPFIFO entries and the pushbuffers they name. An entry is two words: the pushbuffer's address
# (bits 2 and up of the first word, the low byte of the second) and its length in words (bits 10
# and up of the second). A pushbuffer is a stream of method headers, each followed by the data
# words of its burst: 1 (and the older 0) increments the method after each word, 3 (and the older
# 2) does not, 4 carries one word in the header, 5 increments once after the first (yuzu's
# dma_pusher). Subchannel and method select the register.

secIncrementOld = 0
secNonIncrementOld = 2
secIncrement = 1
secNonIncrement = 3
secImmediate = 4
secIncrementOnce = 5
macroMethods = 0xE00

# The entries (8 bytes each) of a submission run in order on channel c.
pub fn submit(mut g Gpu, c i64, entries u8[]):
	if g.channels[c].space < 0: return g.note("channel {c} submitted without an address space")
	for k in 0..entries.len / 8:
		lo = i64(entries.u32le(k * 8))
		hi = i64(entries.u32le(k * 8 + 4))
		g.run(c, (lo & ~3) | (hi & 0xFF) << 32, (hi >> 10) & 0x1F_FFFF)

# the pushbuffer of `words` words at a GPU address run
fn run(mut g Gpu, c i64, at i64, words i64):
	bytes = g.spaces[g.channels[c].space].read(at, words * 4)
	for k in 0..words:
		g.feed(c, bytes.u32le(k * 4))

# One word of a pushbuffer: a header, or data for the burst a header began.
fn feed(mut g Gpu, c i64, w i64):
	if g.channels[c].remaining > 0: return g.burstWord(c, w)
	op = (w >> 29) & 7
	method = w & 0x1FFF
	sub = (w >> 13) & 7
	count = (w >> 16) & 0x1FFF
	if op == secImmediate:
		g.call(c, sub, method, count)
		if method >= macroMethods: g.flushMacro(c, sub)
		return
	if op == secIncrementOld: op = secIncrement
	if op == secNonIncrementOld: op = secNonIncrement
	if op != secIncrement and op != secNonIncrement and op != secIncrementOnce: return
	g.channels[c].mode = op
	g.channels[c].method = method
	g.channels[c].burstStart = method
	g.channels[c].subchannel = sub
	g.channels[c].remaining = count

# a data word of the burst under way
fn burstWord(mut g Gpu, c i64, w i64):
	method = g.channels[c].method
	g.call(c, g.channels[c].subchannel, method, w)
	g.channels[c].remaining -= 1
	if g.channels[c].mode == secIncrement: g.channels[c].method += 1
	elif g.channels[c].mode == secIncrementOnce:
		g.channels[c].method += 1
		g.channels[c].mode = secNonIncrement
	if g.channels[c].remaining == 0 and g.channels[c].burstStart >= macroMethods:
		g.flushMacro(c, g.channels[c].subchannel)
