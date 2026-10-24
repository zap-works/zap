# PFS0, the flat archive an NSP is and an ExeFS holds: "PFS0", a count of files, the size of the
# names' table, then for each file its offset (past the header), size and name's place.

pub type Entry:
	name str
	at i64   # from the archive's start
	size i64

# The files of the PFS0 whose first bytes (header, entries and names; `head` may run on) are
# `head`, the archive itself at `base`; none when it is no PFS0.
pub fn readPfs(head u8[], base i64) Entry[]?:
	if head.len < 16 or not head.startsWith("PFS0"): return none
	count = i64(head.u32le(4))
	names = i64(head.u32le(8))
	table = 16 + count * 24
	if head.len < table + names: return none
	dataAt = table + names
	out = []
	for i in 0..count:
		e = 16 + i * 24
		name = head.cStringAt(table + head.u32le(e + 16), names)
		out.push(
			Entry(name, at = base + dataAt + i64(head.u64le(e)), size = i64(head.u64le(e + 8)))
		)
	out

# how many bytes of a PFS0's start hold its whole header, from its first 16
pub fn pfsHeaderSize(first u8[]) i64:
	16 + i64(first.u32le(4)) * 24 + i64(first.u32le(8))
