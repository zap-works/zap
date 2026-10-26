# Memory maps as page tables: where a page's reads and writes land, a mirror two pages of one
# place, and the pages a function answers (-1).

import engine.memoryMap

test "a one-level map lands each page where it was mapped, the rest a function's":
	m = memoryMap.pageMap(24, 13)
	m.bytes = zeros(0x4000)
	m.mapPage(0x7E_0000, 0, 0)
	m.mapPage(0x00_0000, 0, 0)   # a mirror of the same 8 KB
	m.mapPage(0x80_8000, 0x2000, -1)   # read only
	print("{m.readAt(0x7E_1234):x} {m.writeAt(0x00_1234):x} {m.readAt(0x80_9FFF):x}")
	print("{m.writeAt(0x80_8000)} {m.readAt(0x00_2000)} {m.readAt(0xFF_FFFF)}")
	m.clear()
	print("{m.readAt(0x7E_0000)}")
	prints """
		1234 1234 3fff
		-1 -1 -1
		-1
		"""

test "a two-level map finds a page of a 48-bit space and keeps the last table":
	m = memoryMap.WideMap()
	m.mapPage(0x7FF0_0000_1000, 0, 0)
	m.mapPage(0x1_4000_0000, 4096, 4096)
	m.mapPage(0x1_4000_1000, 8192, -1)
	print("{m.readAt(0x7FF0_0000_1abc):x} {m.readAt(0x1_4000_0010):x} {m.readAt(0x1_4000_1010):x}")
	print("{m.writeAt(0x1_4000_1010)} {m.readAt(0x7FF0_0000_0000)} {m.readAt(0x2_0000_0000)}")
	prints """
		abc 1010 2010
		-1 -1 -1
		"""
