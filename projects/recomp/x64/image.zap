# A Windows x86-64 executable (PE32+) as the loader maps it at its preferred base, so relocations
# are not applied: the headers and each section at base + its RVA, the file's bytes up to the
# section's virtual size, zeros after (the .bss part). The bytes stay in the file and are read a
# page at a time when the emulator first touches one (memory.zap). Each import's slot in the
# import address table holds the address of a stub of its own (stubBase + 16 k), which the machine
# runs as that function (stubs.zap).

import fs

# where the import stubs lie: outside any image, never mapped as memory
pub stubBase u64 = 0x7FFE_0000_0000

pub type Section:
	name str
	start u64   # the address the section is mapped at
	size u64   # its virtual size
	fileAt i64   # where its bytes are in the file
	fileSize i64

# a function the executable imports: the slot its calls read and the stub address it holds
pub type Import:
	dll str
	name str
	slot u64
	stub u64

# An executable's layout; one of no file (`noImage`) maps nothing, for code a test writes into
# memory itself.
pub type Image:
	path str
	file fs.File?
	base u64
	size u64   # SizeOfImage
	headerSize i64
	entry u64
	sections Section[]
	imports Import[]

	# whether the address lies inside the mapped image
	fn holds(at u64):
		at - base < size

	# The bytes the loader puts at [at, at + n): headers, sections, zeros between and after; the
	# import slots hold their stubs' addresses.
	fn mappedBytes(at u64, n i64):
		out u8[] = zeros(n)
		if at < base: return out
		f = file ?? return out
		if at - base < u64(headerSize):
			take = (headerSize - i64(at - base)).min(n)
			out.place(0, f.bytesOf(i64(at - base), take))
		for s in sections:
			lo = at.max(s.start)
			hi = (at + u64(n)).min(s.start + s.size.min(u64(s.fileSize)))
			if lo >= hi: continue
			out.place(i64(lo - at), f.bytesOf(s.fileAt + i64(lo - s.start), i64(hi - lo)))
		for imp in imports:
			if imp.slot >= at and imp.slot + 8 <= at + u64(n):
				out.setU64le(i64(imp.slot - at), imp.stub)
		out

fn fileOffset(sections Section[], base u64, rva u64) i64?:
	for s in sections:
		if base + rva >= s.start and base + rva < s.start + s.size.max(u64(s.fileSize)):
			return s.fileAt + i64(base + rva - s.start)
	none

# n bytes of the file from `at`, fewer where it ends
fn bytesOf(file fs.File, at i64, n i64):
	file.readAt(at, n) ?? []

fn cString(file fs.File, at i64):
	file.bytesOf(at, 256).cStringAt(0, 256)

# the imports of the descriptors at `table` (an RVA), each slot given its stub
fn importsOf(file fs.File, sections Section[], base u64, table u64):
	out = []
	descriptor = fileOffset(sections, base, table) ?? return out
	loop:
		d = file.bytesOf(descriptor, 20)
		nameRva = d.u32le(12)
		if nameRva == 0: break
		dll = file.cString(fileOffset(sections, base, nameRva) ?? break)
		lookup = d.u32le(0) if d.u32le(0) != 0 else d.u32le(16)
		slots = u64(d.u32le(16))
		at = fileOffset(sections, base, lookup) ?? break
		k = 0
		loop:
			thunk = file.bytesOf(at + 8 * k, 8).u64le(0)
			if thunk == 0: break
			name = "#{thunk & 0xFFFF}"
			if thunk >> 63 == 0:
				name = file.cString((fileOffset(sections, base, thunk & 0x7FFF_FFFF) ?? break) + 2)
			stub = stubBase + 16 * u64(out.len)
			out.push(Import(dll = dll.lower(), name, slot = base + slots + 8 * u64(k), stub))
			k += 1
		descriptor += 20
	out

# The executable at `path` opened and its layout read; the error says why it is not a PE32+ file.
pub fn openImage(path str) Image ? str:
	file = fs.open(path) ?? return "cannot open {path}"
	head = file.bytesOf(0, 4096)
	if head.len < 0x200 or not head.startsWith("MZ"): return "{path}: not an executable"
	pe = i64(head.u32le(0x3C))
	if pe + 0x108 > head.len or not head.matchesAt(pe, "PE\0\0"): return "{path}: no PE header"
	if head.u16le(pe + 4) != 0x8664: return "{path}: not x86-64"
	opt = pe + 24
	if head.u16le(opt) != 0x20B: return "{path}: not PE32+"
	count = i64(head.u16le(pe + 6))
	table = opt + head.u16le(pe + 20)
	base = head.u64le(opt + 24)
	sections = []
	for k in 0..count:
		h = table + 40 * k
		sections.push(Section(
			name = head.cStringAt(h, 8),
			start = base + head.u32le(h + 12),
			size = head.u32le(h + 8),
			fileAt = head.u32le(h + 20),
			fileSize = head.u32le(h + 16)
		))
	imports = file.importsOf(sections, base, head.u32le(opt + 120))
	Image(
		path = path.copy(),
		file,
		base,
		size = head.u32le(opt + 56),
		headerSize = head.u32le(opt + 60),
		entry = base + head.u32le(opt + 16),
		sections,
		imports
	)

# the image of no file: nothing mapped, no imports
pub fn noImage() Image:
	Image(
		path = "",
		file = none,
		base = 0,
		size = 0,
		headerSize = 0,
		entry = 0,
		sections = [],
		imports = []
	)
