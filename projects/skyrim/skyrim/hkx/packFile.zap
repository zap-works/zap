# Havok's binary packfiles as Skyrim Special Edition keeps its skeletons and animations
# (hk_2010.2.0-r1, 64-bit): a 64-byte header (the magic, the file version 8, the layout rules:
# pointer size, byte order, reuse of padding, empty base classes; the section and offset of the
# contents, the version string), then a 48-byte header per section (a 19-byte name and 0xFF, the
# absolute start of its data, then the offsets of its local, global and virtual fixups, exports,
# imports and end, from that start). __classnames__ is (u32 signature, 0x09, name) records;
# __data__ holds the objects as the 64-bit C++ classes lay them out, its pointers zero in the file
# and named by the fixups: local (from, to) within the section, global (from, section, to) into
# any, virtual (from, section, name) giving the class of the object at `from`. Every offset kept
# here is the file's.

fileHeader = 64
sectionHeader = 48
noFixup = 0xFFFF_FFFF

type Section:
	name str
	start i64
	local i64   # the fixup tables' ends, absolute
	global i64
	virtual i64
	exports i64

# an object of the data section and the name of its class
pub type HkObject:
	at i64
	className str

# a file's objects with their pointers resolved
pub type Packfile:
	d ref u8[]   # the file's bytes
	pointers {i64: i64}   # where a pointer is, where it points
	objects HkObject[]
	root i64   # the contents: an hkRootLevelContainer

	# a section's three tables of fixups into the packfile's pointers and objects
	fn readFixups(s Section, sections Section[]) ? str:
		at = s.local
		while at + 8 <= s.global:
			from = d.u32le(at)
			if from != noFixup: pointers[s.start + from] = s.start + d.u32le(at + 4)
			at += 8
		at = s.global
		while at + 12 <= s.virtual:
			from = d.u32le(at)
			if from != noFixup:
				to = i64(d.u32le(at + 4))
				if to >= sections.len: return "a pointer into section {to}, which is not there"
				pointers[s.start + from] = sections[to].start + d.u32le(at + 8)
			at += 12
		at = s.virtual
		while at + 12 <= s.exports:
			from = d.u32le(at)
			if from != noFixup:
				names = i64(d.u32le(at + 4))
				if names >= sections.len:
					return "a class named in section {names}, which is not there"
				name = d.cStringAt(sections[names].start + d.u32le(at + 8), 256)
				objects.push(HkObject(at = s.start + from, className = name))
			at += 12

# a packfile read from its bytes, or why it is not one this reader knows
pub fn openPackfile(d u8[]) Packfile ? str:
	if d.len < fileHeader or d.u32le(0) != 0x57E0_E057 or d.u32le(4) != 0x10C0_C010:
		return "not a Havok packfile"
	version = d.cStringAt(0x28, 16)
	if d.u32le(12) != 8 or d.u32le(16) != 0x0100_0108:
		return "a Havok packfile of {version} with other layout rules (8-byte pointers, little endian are read)"
	count = i64(d.u32le(0x14))
	if fileHeader + count * sectionHeader > d.len: return "a Havok packfile cut short"
	sections = []
	for i in 0..count:
		h = fileHeader + i * sectionHeader
		start = i64(d.u32le(h + 20))
		sections.push(
			Section(
				name = d.cStringAt(h, 19),
				start,
				local = start + d.u32le(h + 24),
				global = start + d.u32le(h + 28),
				virtual = start + d.u32le(h + 32),
				exports = start + d.u32le(h + 36)
			)
		)
	for s in sections:
		if s.exports > d.len or s.start > s.local: return "the section {s.name} runs past the end"
	contents = i64(d.u32le(0x18))
	if contents >= count: return "the contents are in no section"
	p = Packfile(
		d,
		pointers = {},
		objects = [],
		root = sections[contents].start + d.u32le(0x1C)
	)
	for s in sections:
		try p.readFixups(s, sections)
	p

# where the pointer at `at` points, -1 when it is null
pub fn target(p Packfile, at i64) i64:
	p.pointers.get(at) ?? -1

# the text the char* at `at` points to, "" when it is null
pub fn textAt(p Packfile, at i64) str:
	to = p.target(at)
	"" if to < 0 else p.d.cStringAt(to, 4096)

# the class of the object at `at`, "" when no object starts there
pub fn classAt(p Packfile, at i64) str:
	for o in p.objects:
		if o.at == at: return o.className.copy()
	""

# an hkArray: the address of its first element (-1 when empty) and how many there are
pub type HkArray:
	first i64
	count i64

# the hkArray at `at`: a pointer, a u32 size and a u32 of capacity and flags
pub fn arrayAt(p Packfile, at i64) HkArray:
	HkArray(first = p.target(at), count = p.d.u32le(at + 8))

# the address of element i of an array of `size`-byte elements
pub fn element(a HkArray, i i64, size i64) i64:
	a.first + i * size

# whether the array's elements lie inside the file
pub fn fits(p Packfile, a HkArray, size i64) bool:
	a.count == 0 or (a.first >= 0 and a.count > 0 and a.first + a.count * size <= p.d.len)
