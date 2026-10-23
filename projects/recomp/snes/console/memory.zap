# The SNES's address space as the recompiled 65816 reads and writes it, a 24-bit address a call:
# the cartridge (HiROM: banks 40-7D and C0-FF the ROM whole, 00-3F and 80-BF its upper halves,
# the battery RAM at 20-3F:6000-7FFF), the 128 KB of work RAM (banks 7E-7F, its first 8 KB seen
# at 0000-1FFF of the low banks) and the registers: the PPU's (2100-213F), the APU's ports
# (2140-217F), the work RAM's port (2180-2183), the joypads' (4016-4017), the CPU's (4200-421F)
# and the DMA's (4300-437F). A read of what nothing answers gives the open bus, taken as the
# address's middle byte: the last byte an absolute load fetched before it.

import recomp.snes.cartridge

pub mut rom u8[] = []
pub mut wram u8[] = zeros(0x2_0000)
pub mut sram u8[] = []
pub mut cartridgeHeader = cartridge.Header(
	title = "",
	hirom = true,
	fast = false,
	sramBytes = 0,
	pal = false,
	chip = ""
)
mut wramPort = 0   # 2181-2183: where the port at 2180 reads and writes next

# The cartridge read from a file (a copier's 512-byte header skipped), its map and battery RAM
# as its header says.
pub fn loadRom(path str):
	loadedRom = path.copy()
	rom = cartridge.readRom(path) ?? fail("cannot read the cartridge {path}: {error}")
	if rom.len < 0x1_0000: fail("{path} is too short for a cartridge")
	cartridgeHeader = cartridge.readHeader(rom)
	cartridge.hirom = cartridgeHeader.hirom
	sram = fill(cartridgeHeader.sramBytes, 0)
	setRegion(cartridgeHeader.pal)
	startChip(path)

fn romByte(off i64) u8:
	if rom.isEmpty: return 0
	rom[off % len]

pub fn read8(addr u32) u8:
	bank = (addr >> 16) & 0xFF
	off = addr & 0xFFFF
	if necMapped and isNecAddress(bank, n32(off)): return necRead(addr)
	if bank == 0x7E or bank == 0x7F: return wram[addr & 0x1_FFFF]
	if bank & 0x7F < 0x40 and off < 0x8000:
		if off < 0x2000: return wram[off]
		if off < 0x6000: return registerRead(addr, off)
	elif cartridge.isRomAddress(addr):
		return romByte(cartridge.romOffset(addr))
	at = cartridge.sramOffset(addr, sram.len)
	sram[at] if at >= 0 else openBus()

# the byte memory holds at the address (work RAM, ROM, battery RAM), with no register touched;
# none where nothing holds one
fn memoryByte(addr u32) u8?:
	bank = (addr >> 16) & 0xFF
	off = addr & 0xFFFF
	if bank == 0x7E or bank == 0x7F: return wram[addr & 0x1_FFFF]
	if bank & 0x7F < 0x40 and off < 0x8000:
		if off < 0x2000: return wram[off]
		if off < 0x6000: return none
	elif cartridge.isRomAddress(addr):
		return romByte(cartridge.romOffset(addr))
	at = cartridge.sramOffset(addr, sram.len)
	if at >= 0: return sram[at]
	none

fn registerRead(addr u32, off u32):
	match off:
		0x2100..0x2140: ppuRead(off)
		0x2140..0x2180: apuPortRead(off & 3)
		0x2180:
			v = wram[wramPort]
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
	bank = (addr >> 16) & 0xFF
	off = addr & 0xFFFF
	if necMapped and isNecAddress(bank, n32(off)):
		necWrite(addr, v)
		return
	if bank == 0x7E or bank == 0x7F:
		wram[addr & 0x1_FFFF] = v
	elif bank & 0x7F < 0x40 and off < 0x2000:
		wram[off] = v
	elif bank & 0x7F < 0x40 and off < 0x6000:
		if off >= 0x2100 and off < 0x2200: busBWrite(off, v)
		else: cpuRegisterWrite(off, v)
	elif not cartridge.isRomAddress(addr):
		at = cartridge.sramOffset(addr, sram.len)
		if at >= 0:
			sram[at] = v
			sramChanged = true

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
			wram[wramPort] = v
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
