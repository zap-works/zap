# Executables put in guest memory as Horizon's loader puts them: an NSO's segments (stored whole by
# tools/extract.zap) where its header says, or an NRO (a homebrew) as it lies in its file, each
# followed by its zeroed .bss; .text mapped read-execute, .rodata read-only, .data and .bss
# read-write. Modules follow each other on page boundaries.

import recomp.switch.package

pub type Module:
	name str
	at i64
	size i64
	textSize i64

# the module's three segments (memory offset, size) mapped and its whole size
fn mapSegments(mut s Space, at i64, text (i64, i64), ro (i64, i64), data (i64, i64), bss i64):
	textAt, textSize = text
	roAt, roSize = ro
	dataAt, dataSize = data
	s.map(at + textAt, textSize.alignUp(pageSize), typeCode, permRead | permExecute)
	s.map(at + roAt, roSize.alignUp(pageSize), typeCode, permRead)
	whole = (dataAt + dataSize + bss).alignUp(pageSize)
	s.map(at + dataAt, whole - dataAt, typeCodeData, permRead | permWrite)
	whole

# An NSO stored whole put at `at`; the module, or why not.
pub fn loadNso(mut s Space, name str, file u8[], at i64) Module ? str:
	nso = package.readNso(file) ?? return "{name} is no NSO"
	if nso.segments.any(.stored != .size):
		return "{name} is compressed: extract it with tools/extract.zap"
	t = nso.segments[0]
	r = nso.segments[1]
	d = nso.segments[2]
	size = s.mapSegments(
		at,
		(t.memoryAt, t.size),
		(r.memoryAt, r.size),
		(d.memoryAt, d.size),
		nso.bss
	)
	for seg in nso.segments:
		putBytes(at + seg.memoryAt, file[seg.fileAt..seg.fileAt + seg.size])
	Module(name = name.copy(), at, size, textSize = t.size)

# An NRO (its header at 0x10: "NRO0", the size, the three segments' offsets and sizes, .bss's
# size) put at `at`; the module, or why not.
pub fn loadNro(mut s Space, name str, file u8[], at i64) Module ? str:
	if file.len < 0x80 or not file.matchesAt(0x10, "NRO0"): return "{name} is no NRO"
	size = i64(file.u32le(0x18)).min(file.len)
	seg = (k i64): (i64(file.u32le(0x20 + k * 8)), i64(file.u32le(0x24 + k * 8)))
	whole = s.mapSegments(at, seg(0), seg(1), seg(2), file.u32le(0x38))
	putBytes(at, file[..size])
	Module(name = name.copy(), at, size = whole, textSize = file.u32le(0x24))
