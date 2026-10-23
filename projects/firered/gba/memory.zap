# The GBA's memory map as the recompiled code reads and writes it: the work RAMs, the I/O
# registers, the palette, video RAM and the sprites' attributes, the cartridge (its data from
# the prepared assets) and the save's flash. A word or halfword read off its alignment comes
# rotated, as the ARM7 reads it.

pub mut rom u8[] = []
pub mut ewram u8[] = zeros(0x4_0000)
pub mut iwram u8[] = zeros(0x8000)
pub mut io u8[] = zeros(0x400)
pub mut palette u8[] = zeros(0x400)
pub mut vram u8[] = zeros(0x1_8000)
pub mut oam u8[] = zeros(0x400)

fn vramOffset(a u32):
	off = i64(a & 0x1_FFFF)
	off - 0x8000 if off >= 0x1_8000 else off

# The cycles a load or store waits past its instruction's, by region (WAITCNT as FireRed sets
# it: the cartridge 3 then 1, work RAM 2): a halfword's, then a word's.
waitHalf i64[16] = [0, 0, 2, 0, 0, 0, 0, 0, 3, 3, 3, 3, 3, 3, 4, 4]
waitWord i64[16] = [0, 0, 5, 0, 0, 1, 1, 0, 5, 5, 5, 5, 5, 5, 4, 4]

pub fn load32(a u32) u32:
	cycles += waitWord[i64(a >> 24) & 15]
	w = match a >> 24:
		2: ewram.u32le(a & 0x3_FFFC)
		3: iwram.u32le(a & 0x7FFC)
		_: loadWordSlow(a & ~u32(3))
	w if a & 3 == 0 else w.rotateRight(i64(8 * (a & 3)))

fn loadWordSlow(a u32):
	match a >> 24:
		4: ioRead16(a) | (ioRead16(a + 2) << 16)
		5: palette.u32le(a & 0x3FC)
		6: vram.u32le(vramOffset(a))
		7: oam.u32le(a & 0x3FC)
		8, 9, 10, 11, 12, 13: romWord(a)
		14, 15: flashRead(a) * 0x0101_0101
		_: 0

fn romWord(a u32):
	off = i64(a & 0x1FF_FFFC)
	if off + 4 <= rom.len: return rom.u32le(off)
	(a >> 1 & 0xFFFF) | ((a + 2) >> 1 << 16)   # past the cartridge, its address lines

pub fn load16(a u32) u32:
	cycles += waitHalf[i64(a >> 24) & 15]
	h = match a >> 24:
		2: u32(ewram.u16le(a & 0x3_FFFE))
		3: iwram.u16le(a & 0x7FFE)
		_: loadHalfSlow(a & ~u32(1))
	h if a & 1 == 0 else h.rotateRight(8)

fn loadHalfSlow(a u32):
	match a >> 24:
		4: ioRead16(a)
		5: palette.u16le(a & 0x3FE)
		6: vram.u16le(vramOffset(a))
		7: oam.u16le(a & 0x3FE)
		8, 9, 10, 11, 12, 13:
			off = i64(a & 0x1FF_FFFE)
			rom.u16le(off) if off + 2 <= rom.len else (a >> 1) & 0xFFFF
		14, 15: flashRead(a) * 0x0101
		_: 0

pub fn load8(a u32) u32:
	cycles += waitHalf[i64(a >> 24) & 15]
	match a >> 24:
		2: ewram[a & 0x3_FFFF]
		3: iwram[a & 0x7FFF]
		14, 15: flashRead(a)
		_: (loadHalfSlow(a & ~u32(1)) >> (8 * (a & 1))) & 0xFF

pub fn loadS8(a u32) u32:
	i32(i8.wrap(load8(a)))

# a halfword read sign-extended; off its alignment, the byte
pub fn loadS16(a u32) u32:
	if a & 1 == 1: return loadS8(a)
	i32(i16.wrap(load16(a)))

pub fn store32(a u32, v u32):
	cycles += waitWord[i64(a >> 24) & 15]
	match a >> 24:
		2: ewram.setU32le(a & 0x3_FFFC, v)
		3: iwram.setU32le(a & 0x7FFC, v)
		_:
			store16(a & ~u32(3), v & 0xFFFF)
			store16((a & ~u32(3)) + 2, v >> 16)

pub fn store16(a u32, v u32):
	cycles += waitHalf[i64(a >> 24) & 15]
	h = u16.wrap(v)
	match a >> 24:
		2: ewram.setU16le(a & 0x3_FFFE, h)
		3: iwram.setU16le(a & 0x7FFE, h)
		4: ioWrite16(a & 0x3FE, h)
		5: palette.setU16le(a & 0x3FE, h)
		6: vram.setU16le(vramOffset(a & ~u32(1)), h)
		7: oam.setU16le(a & 0x3FE, h)
		14, 15: flashWrite(a, v & 0xFF)
		_: pass

# A byte stored: the palette and the backgrounds' video RAM take it in both halves of its
# halfword, the sprites' video RAM and attributes not at all.
pub fn store8(a u32, v u32):
	cycles += waitHalf[i64(a >> 24) & 15]
	b = u8.wrap(v)
	match a >> 24:
		2: ewram[a & 0x3_FFFF] = b
		3: iwram[a & 0x7FFF] = b
		4: ioWrite8(a & 0x3FF, b)
		5: palette.setU16le(a & 0x3FE, u16(b) * 0x101)
		6:
			off = vramOffset(a & ~u32(1))
			if off < 0x1_0000: vram.setU16le(off, u16(b) * 0x101)
		14, 15: flashWrite(a, b)
		_: pass
