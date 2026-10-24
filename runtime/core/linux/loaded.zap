# Loadable builds on Linux and Android (runtime/core/loaded.zap): the image is the static ELF the
# target's executable is (compiler/targets/elf.zap), its segments copied beside the program at
# their places from the first, each then given the access its header names. It imports nothing.
# The kernel makes the instruction cache see the code as its pages turn executable (arm64's
# set_pte_at), and they are written only before.

# the ELF at p mapped beside the program: where its first segment is and the size of them all;
# (0, 0) when it is no ELF or finds no room
fn mappedImage(image str) (i64, i64):
	p = sPtr(image)
	if __ld32(p) != 0x464C_457F: return (0, 0)   # "\x7fELF"
	first = -1
	end = 0
	each = loadSegments(p)
	for h in each:
		if first < 0: first = __ld64(h + 16)
		end = end.max(__ld64(h + 16) + __ld64(h + 40) - first)
	if first < 0: return (0, 0)
	size = end.alignUp(65_536)
	base = reserveNear(size)
	if base == 0: return (0, 0)
	for h in each:
		__memcpy(base + __ld64(h + 16) - first, p + __ld64(h + 8), __ld64(h + 32))
	(base, size)

# the program headers of the ELF at p that load a segment (PT_LOAD), in their order
fn loadSegments(p i64) i64[]:
	out = []
	headers = p + __ld64(p + 32)   # e_phoff
	for k in 0..__ld16(p + 56):   # e_phnum
		h = headers + 56 * k
		if __ld32(h) == 1: out.push(h)
	out

# the image mapped at base, its first segment holding the headers, each segment given the access
# its flags name (ELF's X 1, W 2, R 4 as mprotect's EXEC 4, WRITE 2, READ 1)
fn makeRunnable(base i64, size i64):
	_ = size
	each = loadSegments(base)
	if each.isEmpty: return
	first = __ld64(each[0] + 16)
	for h in each:
		flags = __ld32(h + 4)
		access = (flags & 4) >> 2 | flags & 2 | (flags & 1) << 2
		at = base + __ld64(h + 16) - first
		_ = sysMprotect(at, wholePages(__ld64(h + 40)), access)
