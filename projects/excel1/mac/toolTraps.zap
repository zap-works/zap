# long: the Toolbox traps, one arm each
#
# The Toolbox's traps by number (A800 + n): their Pascal arguments popped, their results left on
# the stack.

pub mut exitRequested = false

pub fn toolTrap(n i64, word i64, back u32) u32:
	match n:
		0x1A0:
			id = popInt()
			kind = popLong()
			h = getResource(kind, id, [], false)
			if traceTraps: eprint("  resource {kind:x} {id} -> {h:x}")
			resultLong(h)
		0x1F0:
			segment = popInt()
			loadSegment(segment)
			# back to the entry, now a jump
			return back - 6
		0x1F1: unloadSegment(popLong())
		0x1F4:
			exitRequested = true
			return returnToZap
		_:
			if n >= 0x50 and n < 0x104: return quickdrawTrap(n, word, back)
			if n >= 0x104 and n < 0x153 or n == 0x1BF or n == 0x1C0:
				return windowTrap(n, word, back)
			if n >= 0x192 and n < 0x1B1: return resourceTrap(n, word, back)
			if n >= 0x170 and n < 0x178 or n >= 0x1B2 and n < 0x1B6 or n == 0x1C2 or n == 0x1C8:
				return eventTrap(n, word, back)
			isDialogs = n == 0x14B or n >= 0x153 and n < 0x16E or n >= 0x178 and n < 0x192 or
				n == 0x1BE
			if isDialogs or n >= 0x1CB and n < 0x1DE: return dialogTrap(n, word, back)
			return utilityTrap(n, word, back)
	back
