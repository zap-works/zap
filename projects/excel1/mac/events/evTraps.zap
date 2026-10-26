# long: the Event Manager's traps, one arm each
#
# The Event Manager's traps, and the Desk Manager's a program calls in its event loop.

import cpu

# null events in a row after which a run stops, its program waiting for input (-1 never)
pub mut idleLimit = -1

pub fn eventTrap(n i64, trapWord i64, back u32) u32:
	match n:
		0x170, 0x171:
			at = popLong()
			mask = popInt()
			resultBool(getEvent(mask, at, n == 0x170))
			if not waitsForInput():
				exitRequested = true
				return returnToZap
		0x172:
			at = popLong()
			v, h = globalToLocal(thePort(), mouseV, mouseH)
			setWord(at, v)
			setWord(at + 2, h)
		0x173, 0x174, 0x177:
			if n != 0x174: followMouse()
			resultBool(isButtonDown)
		0x175: resultLong(tick())
		0x176:
			at = popLong()
			for i in 0..16:
				cpu.write8(at + u32(i), 0)
		0x1B2: resultBool(false)
		0x1B3:
			popLong()
			popLong()
		0x1B4: tick()
		0x1B5: popInt()
		0x1C2:
			popInt()
			resultBool(false)
		0x1C8: popInt()
		_: return unimplemented(trapWord, back)
	back

pub fn osEventTrap(index i64, trapWord i64, back u32) u32:
	match index:
		0x2F:
			postEvent(Event(what = cpu.a0 & 0xFFFF, message = cpu.d0))
			cpu.d0 = 0
		0x30, 0x31:
			tick()
			poll(false)
			e = nextEvent(cpu.d0 & 0xFFFF, index == 0x31)
			at = cpu.a0
			setWord(at, e.what)
			cpu.write32(at + 2, e.message)
			cpu.write32(at + 6, cpu.read32(ticksAt))
			cpu.write32(at + 10, pointValue(mouseV, mouseH))
			setWord(at + 14, 0x80)
			cpu.d0 = 0 if e.what != nullEvent else 0xFFFF_FFFF
		0x32:
			flushEvents(cpu.d0 & 0xFFFF, cpu.d0 >> 16)
			cpu.d0 = 0
		_: return unimplemented(trapWord, back)
	back
