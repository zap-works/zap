# long: the Operating System traps, one arm each
#
# The Operating System's traps by number: their registers in, their result in D0 (and A0).

import cpu

# the zone a memory trap works in: the system's when its word has bit 10, else the current one
fn zoneFor(word i64):
	cpu.read32(sysZoneAt) if word & 0x400 != 0 else theZone()

fn memErr() u32:
	u32.wrap(i64(i16.wrap(i64(cpu.read16(memErrAt)))))

fn result(e i64):
	setMemErr(e)
	cpu.d0 = u32.wrap(e)

# GetTrapAddress's and SetTrapAddress's trap: D0 the word (bit 9 of the trap's word set) or the
# 64K ROM's number, 0-0x4F an Operating System trap's, the rest a Toolbox trap's
fn trapWordOf(word i64, d0 u32) i64:
	if word & 0x200 != 0: return d0 & 0xFFFF
	n = i64(d0 & 0x1FF)
	n if n < 0x50 else 0xA800 | n

pub fn osTrap(index i64, word i64, back u32) u32:
	match index:
		0x1A: cpu.a0 = theZone()
		0x1B: cpu.write32(theZoneAt, cpu.a0)
		0x1C: cpu.d0 = freeMemory(zoneFor(word))
		0x1D:
			cpu.d0 = maxBlock(zoneFor(word))
			cpu.a0 = 0
		0x1E:
			cpu.a0 = newPtr(zoneFor(word), cpu.d0)
			cpu.d0 = memErr()
		0x1F:
			disposePtr(cpu.a0)
			cpu.d0 = 0
		0x20: result(setPtrSize(cpu.a0, cpu.d0))
		0x21: cpu.d0 = blockDataSize(address(cpu.a0))
		0x22:
			cpu.a0 = newHandle(zoneFor(word), cpu.d0)
			cpu.d0 = memErr()
		0x23:
			disposeHandle(cpu.a0)
			cpu.d0 = memErr()
		0x24: result(setHandleSize(cpu.a0, cpu.d0))
		0x25:
			cpu.d0 = handleSize(cpu.a0)
			setMemErr(0)
		0x26: cpu.a0 = handleZone(cpu.a0)
		0x27: result(reallocHandle(cpu.a0, cpu.d0))
		0x28:
			cpu.a0 = recoverHandle(cpu.a0)
		0x29:
			setFlag(cpu.a0, lockedBit, true)
			result(0)
		0x2A:
			setFlag(cpu.a0, lockedBit, false)
			result(0)
		0x2B:
			emptyHandle(cpu.a0)
			result(0)
		0x2D:
			cpu.write32(applLimitAt, cpu.a0)
			result(0)
		0x2E:
			moveBytes(cpu.a1, cpu.a0, cpu.d0)
			result(0)
		0x36: result(moreMasters(theZone()))
		0x40: result(0 if maxBlock(theZone()) >= cpu.d0 else memFullErr)
		0x46:
			cpu.a0 = trapAddress(trapWordOf(word, cpu.d0))
			if traceTraps: eprint("  trap {trapWordOf(word, cpu.d0):x} is at {cpu.a0:x}")
		0x47:
			if traceTraps: eprint("  trap {trapWordOf(word, cpu.d0):x} set to {cpu.a0:x}")
			setTrapAddress(trapWordOf(word, cpu.d0), cpu.a0)
		0x48: cpu.a0 = zoneOf(address(cpu.a0))
		0x49:
			setFlag(cpu.a0, purgeableBit, true)
			result(0)
		0x4A:
			setFlag(cpu.a0, purgeableBit, false)
			result(0)
		0x4B: cpu.write32(theZone() + 16, cpu.a0)
		0x4C: cpu.d0 = maxBlock(theZone())
		0x4D:
			purge(theZone())
			result(0)
		0x55: cpu.d0 = address(cpu.d0)
		0x62:
			cpu.d0 = freeMemory(theZone())
			cpu.a0 = maxBlock(theZone())
		0x63:
			maxApplZone()
			result(0)
		0x64: result(0)
		0x65: cpu.d0 = cpu.a7 - cpu.read32(heapEndAt)
		0x66:
			cpu.a0 = newHandle(zoneFor(word), 0)
			cpu.d0 = memErr()
		0x67:
			setFlag(cpu.a0, resourceBit, true)
			result(0)
		0x68:
			setFlag(cpu.a0, resourceBit, false)
			result(0)
		0x69: cpu.d0 = cpu.read8(cpu.a0)
		0x6A:
			cpu.write8(cpu.a0, cpu.d0)
			result(0)
		_:
			if index < 0x19 or index == 0x44 or index == 0x45: return fileTrap(index, word, back)
			if index >= 0x2F and index <= 0x32: return osEventTrap(index, word, back)
			return unimplemented(word, back)
	back
