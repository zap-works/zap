# The SNES's address space as the recompiled 65816 reads and writes it, a 24-bit address a call:
# the cartridge (HiROM: banks 40-7D and C0-FF the ROM whole, 00-3F and 80-BF its upper halves,
# the battery RAM at 20-3F:6000-7FFF), the 128 KB of work RAM (banks 7E-7F, its first 8 KB seen
# at 0000-1FFF of the low banks) and the registers: the PPU's (2100-213F), the APU's ports
# (2140-217F), the work RAM's port (2180-2183), the joypads' (4016-4017), the CPU's (4200-421F)
# and the DMA's (4300-437F). A read of what nothing answers gives the open bus, taken as the
# address's middle byte: the last byte an absolute load fetched before it.
#
# The memories are one list of bytes (work RAM, then the battery RAM, then the ROM) behind a page
# table of 8 KB pages (engine.memorymap): a page wholly of memory is read through its table
# (written too when work RAM), any other is decoded a byte at a time below.

import engine.memorymap
import recomp.snes.cartridge

wramSize = 0x2_0000
sramAt = wramSize   # the battery RAM's place in the map's bytes; the ROM's follows it
pageSize = 0x2000

pub mut memoryMap = emptyMap()
mut romAt = sramAt
mut romLen = pageSize   # without a cartridge, one page of zeros
mut sramLen = 0
pub mut cartridgeHeader = cartridge.Header(
	title = "",
	hirom = true,
	fast = false,
	sramBytes = 0,
	pal = false,
	chip = ""
)
mut wramPort = 0   # 2181-2183: where the port at 2180 reads and writes next

fn emptyMap():
	m = memorymap.pageMap(24, 13)
	m.bytes = zeros(wramSize + pageSize)
	m

# The cartridge read from a file (a copier's 512-byte header skipped), its map and battery RAM
# as its header says.
pub fn loadRom(path str):
	loadedRom = path.copy()
	rom = cartridge.readRom(path) ?? fail("cannot read the cartridge {path}: {error}")
	if rom.len < 0x1_0000: fail("{path} is too short for a cartridge")
	cartridgeHeader = cartridge.readHeader(rom)
	cartridge.hirom = cartridgeHeader.hirom
	sramLen = cartridgeHeader.sramBytes
	romAt = sramAt + sramLen.alignUp(pageSize)
	romLen = rom.len
	bytes = memoryMap.bytes[..wramSize].copy()
	bytes.extend(zeros(romAt - sramAt))
	bytes.extend(rom)
	memoryMap.bytes = bytes
	setRegion(cartridgeHeader.pal)
	startChip(path)
	mapMemory()

# work RAM cleared, the pages mapped
fn memoryPowerOn():
	memoryMap.bytes.place(0, zeros(wramSize))
	mapMemory()

# The pages' tables as the cartridge and its chip map them: a page all of memory, in one run of
# bytes, read there (and written, when work RAM); any other left to slowRead and slowWrite.
fn mapMemory():
	for page in 0..0x800:
		at = u32(page) << 13
		read = memoryPlace(at) if isMemoryPage(at) else -1
		memoryMap.mapPage(i64(at), read, read if read >= 0 and read < wramSize else -1)

# whether the 8 KB page from `at` is memory in one run of bytes, none of it the chip's (the maps'
# edges fall on 4 KB)
fn isMemoryPage(at u32):
	first = memoryPlace(at)
	if first < 0: return false
	for k in [0, 0x0FFF, 0x1000, 0x1FFF]:
		if isChipAddress(at + u32(k)) or memoryPlace(at + u32(k)) != first + k: return false
	true

fn isChipAddress(addr u32):
	necMapped and isNecAddress((addr >> 16) & 0xFF, n32(addr & 0xFFFF))

# 2000-5FFF of the low banks
fn isRegisterAddress(addr u32):
	off = addr & 0xFFFF
	(addr >> 16) & 0x7F < 0x40 and off >= 0x2000 and off < 0x6000

# where in the map's bytes the byte at the address is (work RAM, ROM, battery RAM), with no
# register touched; -1 where no memory is
fn memoryPlace(addr u32) i64:
	bank = (addr >> 16) & 0xFF
	off = addr & 0xFFFF
	if bank == 0x7E or bank == 0x7F: return i64(addr & 0x1_FFFF)
	if bank & 0x7F < 0x40 and off < 0x8000:
		if off < 0x2000: return i64(off)
		if off < 0x6000: return -1
	elif cartridge.isRomAddress(addr):
		return romAt + cartridge.romOffset(addr) % romLen
	at = cartridge.sramOffset(addr, sramLen)
	sramAt + at if at >= 0 else -1

pub fn read8(addr u32) u8:
	at = memoryMap.readAt(i64(addr))
	if at >= 0: return memoryMap.bytes[at]
	slowRead(addr)

# a read the page table leaves: the chip, the registers, the open bus, a page memory shares
fn slowRead(addr u32) u8:
	if isChipAddress(addr): return necRead(addr)
	if isRegisterAddress(addr): return registerRead(addr, addr & 0xFFFF)
	at = memoryPlace(addr)
	memoryMap.bytes[at] if at >= 0 else openBus()

# the byte memory holds at the address (work RAM, ROM, battery RAM), with no register touched;
# none where nothing holds one
pub fn memoryByte(addr u32) u8?:
	at = memoryPlace(addr)
	if at < 0: return none
	memoryMap.bytes[at]

# the byte of work RAM at `at` (0 to 1FFFF)
pub fn wramByte(at i64) u8:
	memoryMap.bytes[at & 0x1_FFFF]

# the ROM's byte at an offset of its file, and the file's size
pub fn romByte(at i64) u8:
	memoryMap.bytes[romAt + at % romLen]

pub fn romSize() i64:
	romLen

# the work RAM's bytes, a copy
pub fn wramCopy() u8[]:
	memoryMap.bytes[..wramSize].copy()

# the battery RAM's bytes, a copy
fn sramCopy() u8[]:
	memoryMap.bytes[sramAt..sramAt + sramLen].copy()

fn registerRead(addr u32, off u32):
	match off:
		0x2100..0x2140: ppuRead(off)
		0x2140..0x2180: apuPortRead(off & 3)
		0x2180:
			v = memoryMap.bytes[wramPort]
			wramPort = (wramPort + 1) & 0x1_FFFF
			v
		0x2000..0x3000: ppuOpenBus(off)
		0x4016, 0x4017:
			noteJoypadRead()
			serialRead(off == 0x4017) | (openBus() & 0xFC)
		0x4200..0x4220: cpuRegisterRead(addr, off)
		0x4300..0x4380: dmaRegisterRead(off)
		_: openBus()

pub fn read16(addr u32) u16:
	lo = read8(addr)
	lo | (u16(read8((addr + 1) & 0xFF_FFFF)) << 8)

pub fn write8(addr u32, v u8):
	at = memoryMap.writeAt(i64(addr))
	if at >= 0:
		memoryMap.bytes[at] = v
		return
	slowWrite(addr, v)

# a write the page table leaves: the chip, the registers, the battery RAM; the ROM's is lost
fn slowWrite(addr u32, v u8):
	if isChipAddress(addr):
		necWrite(addr, v)
		return
	off = addr & 0xFFFF
	if isRegisterAddress(addr):
		if off >= 0x2100 and off < 0x2200: busBWrite(off, v)
		else: cpuRegisterWrite(off, v)
		return
	if cartridge.isRomAddress(addr): return
	at = memoryPlace(addr)
	if at < 0: return
	memoryMap.bytes[at] = v
	if at >= sramAt: sramChanged = true

pub fn write16(addr u32, v u16):
	write8(addr, v & 0xFF)
	write8((addr + 1) & 0xFF_FFFF, v >> 8)

# a write to the B bus (2100-21FF), the CPU's or a DMA's
fn busBWrite(off u32, v u8):
	if off >= writesFrom and off <= writesTo and frameCount >= writesFromFrame:
		eprint("W {cycles} {off:04X} {v:02X}")
	match off:
		0x2100..0x2140: ppuWrite(off, v)
		0x2140..0x2180: apuPortWrite(off & 3, v)
		0x2180:
			memoryMap.bytes[wramPort] = v
			wramPort = (wramPort + 1) & 0x1_FFFF
		0x2181: wramPort = (wramPort & 0x1_FF00) | i64(v)
		0x2182: wramPort = (wramPort & 0x1_00FF) | (i64(v) << 8)
		0x2183: wramPort = (wramPort & 0xFFFF) | (i64(v & 1) << 16)
		_: pass

fn cpuRegisterWrite(off u32, v u8):
	match off:
		0x4016: serialStrobe(v)
		0x4200..0x4220: cpuRegisterSet(off, v)
		0x4300..0x4380: dmaRegisterWrite(off, v)
		_: pass

# The master cycles an access to the address takes: 6 (fast), 8 (slow) or 12 (the joypads' old
# port), as the CPU's side adds them to `cycles`. The ROM's upper banks are fast when 420D says.
pub fn accessCycles(addr u32) i64:
	bank = (addr >> 16) & 0xFF
	off = addr & 0xFFFF
	if bank & 0x40 != 0 or off >= 0x8000: return 6 if bank >= 0x80 and fastRom else 8
	match off:
		0x0000..0x2000, 0x6000..0x8000: 8
		0x4000..0x4200: 12
		_: 6
