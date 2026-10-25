# A guest's memory map as page tables, for an emulator or a recompiler: one list of bytes holds
# every memory the guest reaches (its RAM, ROM, battery RAM, the pages made as it touches them),
# and two tables give, a page at a time, where in it a read and a write of the page land. A read
# is a table load, an add and an index; a page whose entry is -1 is the caller's to answer by a
# call (registers, open bus, a coprocessor, ROM for writes, a page not made yet). PageMap is one
# level, for a space of up to 32 bits (the SNES's 24 in pages of 8 KB); WideMap two, for a 48-bit
# one (x64's, in pages of 4 KB): an address's top bits pick a table, made when a page of its range
# is first mapped, the last table found kept for the next access.

# One level: an entry a page.
pub type PageMap:
	pageBits i64
	bytes u8[] = []
	reads i64[] = []   # each page's first byte's place in bytes, -1 where a function answers
	writes i64[] = []

	# where in bytes a read of `at` lands, -1 where a function answers
	pub fn readAt(at i64) i64:
		page = reads[at >> pageBits]
		if page < 0: return -1
		page + (at & ((1 << pageBits) - 1))

	# where in bytes a write of `at` lands, -1 where a function answers
	pub fn writeAt(at i64) i64:
		page = writes[at >> pageBits]
		if page < 0: return -1
		page + (at & ((1 << pageBits) - 1))

	# the page holding `at` read from `read` and written to `write` in bytes (-1: a function
	# answers)
	pub mut fn mapPage(at i64, read i64, write i64):
		reads[at >> pageBits] = read
		writes[at >> pageBits] = write

	# every page left to the functions
	pub mut fn clear():
		reads = fill(reads.len, -1)
		writes = fill(writes.len, -1)

# a map of a space of 1 << addressBits bytes in pages of 1 << pageBits, every page a function's
pub fn pageMap(addressBits i64, pageBits i64) PageMap:
	pages = 1 << (addressBits - pageBits)
	PageMap(pageBits, reads = fill(pages, -1), writes = fill(pages, -1))

# Two levels, pages of 4 KB: a table holds the 1024 pages of 4 MB, found by the address's bits
# above them.
pub type WideMap:
	bytes u8[] = []
	tables {i64: i64} = {}   # an address's bits from 22 up -> its table's first entry
	reads i64[] = []   # the tables, one after another: a page's place in bytes or -1
	writes i64[] = []
	lastTop i64 = -1
	lastTable i64 = 0

	# where in bytes a read of `at` lands, -1 where a function answers
	pub mut fn readAt(at i64) i64:
		table = tableOf(at)
		if table < 0: return -1
		page = reads[table + ((at >> wideBits) & (wideTable - 1))]
		if page < 0: return -1
		page + (at & (widePage - 1))

	# where in bytes a write of `at` lands, -1 where a function answers
	pub mut fn writeAt(at i64) i64:
		table = tableOf(at)
		if table < 0: return -1
		page = writes[table + ((at >> wideBits) & (wideTable - 1))]
		if page < 0: return -1
		page + (at & (widePage - 1))

	# the first entry of the table of `at`'s range, -1 when no page of it is mapped
	mut fn tableOf(at i64) i64:
		top = at >> (wideBits + 10)
		if top == lastTop: return lastTable
		table = tables.get(top) ?? return -1
		lastTop = top
		lastTable = table
		table

	# the page holding `at` read from `read` and written to `write` in bytes (-1: a function
	# answers)
	pub mut fn mapPage(at i64, read i64, write i64):
		top = at >> (wideBits + 10)
		table = tables.get(top) ?? reads.len
		if table == reads.len:
			reads.extend(fill(wideTable, -1))
			writes.extend(fill(wideTable, -1))
			tables[top] = table
		k = table + ((at >> wideBits) & (wideTable - 1))
		reads[k] = read
		writes[k] = write

wideBits = 12
widePage = 4096
wideTable = 1024
