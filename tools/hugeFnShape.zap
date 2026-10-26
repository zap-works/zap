# Writes a program of one huge translated function, of the shape of BotW's f881b6b8 (recomp.switch's
# part 36): a `while true` loop over a match on the guest's pc whose first arm runs thousands of
# guest instructions straight on, each a register set, a load or a store through the guest's memory
# (inlined, a branch or two each) or a call out to another function (inlined too). Its build is the
# measured case of a function's passes in time linear in its size.
# zap test --only size
# writes: build/hugeFnShape/hugeFnShape.zap (the program measured, its stem this file's)
#
#   zap run tools/hugeFnShape.zap [entry] [lines]

import fs

# the guest's registers and memory, as recomp.switch's core has them
fn stateText():
	"""
		# A guest thread's registers, its memory and the calls out to other functions.

		import vmem

		pub type Cpu:
			x u64[33] = fill(33, u64(0))
			pc i64 = 0
			isHalted bool = false
			budget i64 = 0

			fn link(ret i64, callee i64):
				x[30] = u64(ret)
				pc = callee

			fn leftAfter(ret i64):
				pc != ret or isHalted

		mut window = vmem.reserve(0x10_0000_0000, 0x10_0000) ?? fail("the window is taken")

		pub mut checking = false
		pub mut journaling = false
		mut journalAt i64[] = []
		mut journalWas u8[] = []
		mut committedFrom i64[] = []
		mut committedTo i64[] = []

		fn noteBytes(at i64, n i64):
			for a in at..at + n:
				journalAt.push(a)
				journalWas.push(window.load8(a))

		fn isCommitted(at i64, n i64):
			for k in 0..committedFrom.len:
				if at >= committedFrom[k] and at + n <= committedTo[k]: return true
			false

		pub type Memory:
			base i64 = 0
			end i64 = 0
			faultAt i64 = -1
			faultBytes i64 = 0

			fn inside(at i64, n i64):
				if at >= base and n >= 0 and at <= end - n: return true
				if faultAt < 0:
					faultAt = at
					faultBytes = n
				false

			fn readable(at i64, n i64):
				if isCommitted(at, n): return inside(at, n)
				if faultAt < 0:
					faultAt = at
					faultBytes = n
				false

			mut fn load(at i64, size i64) u64:
				if checking and not readable(at, 1 << size): return 0
				match size:
					0: window.load8(at)
					1: window.load16(at)
					2: window.load32(at)
					_: window.load64(at)

			mut fn store(at i64, size i64, v u64):
				if checking or journaling:
					if checking and not readable(at, 1 << size): return
					if journaling: noteBytes(at, 1 << size)
				match size:
					0: window.store8(at, v & 0xFF)
					1: window.store16(at, v & 0xFFFF)
					2: window.store32(at, v & 0xFFFF_FFFF)
					_: window.store64(at, v)

		pub mut memory = Memory()

		"""

# the calls out to other functions and a shift, as recomp.switch's core has them
fn callsText():
	"""
		pub type Translated:
			at i64
			end i64
			run fn(mut ref Cpu)

		pub mut functions Translated[] = []

		pub fn functionAt(pc i64) i64?:
			lo = 0
			hi = functions.len
			while lo < hi:
				mid = (lo + hi) / 2
				if functions[mid].end <= pc: lo = mid + 1
				elif functions[mid].at > pc: hi = mid
				else: return mid
			none

		pub fn enter(mut c Cpu):
			if functionAt(c.pc) is f: functions[f].run(mut ref c)

		pub fn callOut(mut c Cpu, ret i64, callee i64) bool:
			c.link(ret, callee)
			c.enter()
			c.leftAfter(ret)

		pub fn shifted(v u64, kind i64, amount i64, sf bool) u64:
			m = u64(-1) if sf else u64(0xFFFF_FFFF)
			x = v & m
			if amount == 0: return x
			match kind:
				0: (x << amount) & m
				1: x >> amount
				2:
					if sf: return u64(i64(x) >> amount)
					u64(i64(i32(u32(x))) >> amount) & m
				_: x.rotateRight(amount)

		"""

# Ten of the function's lines as the translation writes them: a field read from an object, a
# string's address made, two calls out, a value combined and stored, at the guest's pc
fn group(pc i64, step i64):
	at = "\t\t\t\t"
	out = "{at}c.x[21] = core.memory.load(i64(c.x[19]) + 3112, 2)\n"
	out += "{at}c.x[0] = u64(163065856)\n"
	out += "{at}c.x[0] = c.x[0] + u64({2827 + step * 23})\n"
	out += "{at}if core.callOut(c, 0x{pc + 8:x}, 0x8a2c618): return\n"
	out += "{at}c.x[8] = core.memory.load(i64(c.x[19]) + 3032, 3)\n"
	out += "{at}c.x[1] = (u64(0) | (c.x[0] & 0xFFFF_FFFF)) & 0xFFFF_FFFF\n"
	out += "{at}c.x[0] = core.memory.load(i64(c.x[8]) + 0, 3)\n"
	out += "{at}if core.callOut(c, 0x{pc + 24:x}, 0x8c7a9d8): return\n"
	out += "{at}c.x[8] = ((c.x[0] & 0xFFFF_FFFF) | core.shifted((c.x[21] & 0xFFFF_FFFF), 0, 24, false)) & 0xFFFF_FFFF\n"
	out += "{at}core.memory.store(i64(c.x[20]) + {step % 1000 * 4}, 2, c.x[8])\n"
	out

# The function of about `lines` lines: its prologue, the groups, the epilogue's arm a branch
# skips to, and the arm for any other pc
fn huge(lines i64):
	start = 0x881_b6b8
	exit = start + 0x2_0000
	out = "pub fn f{start:x}(c mut ref core.Cpu):\n\tlabel = c.pc\n\twhile true:\n\t\tmatch label:\n"
	out += "\t\t\t0x{start:x}:\n\t\t\t\tc.budget -= {lines}\n"
	out += "\t\t\t\tt = i64(c.x[32]) + -48\n\t\t\t\tc.x[32] = u64(t)\n"
	out += "\t\t\t\tcore.memory.store(t, 3, c.x[21])\n"
	out += "\t\t\t\tc.x[19] = core.memory.load(i64(c.x[8]) + 0, 3)\n"
	out += "\t\t\t\tif c.x[19] == 0:\n\t\t\t\t\tlabel = 0x{exit:x}\n\t\t\t\t\tcontinue\n"
	out += "\t\t\t\tc.x[20] = u64(169291776)\n"
	for step in 0..lines / 10:
		out += group(start + 32 + step * 40, step)
	out += "\t\t\t\tlabel = 0x{exit:x}\n\t\t\t\tcontinue\n"
	out += "\t\t\t0x{exit:x}:\n\t\t\t\tc.x[19] = core.memory.load(i64(c.x[32]) + 16, 3)\n"
	out += "\t\t\t\tc.x[32] = u64(i64(c.x[32]) + 48)\n\t\t\t\treturn\n"
	out += "\t\t\t_:\n\t\t\t\tc.pc = label\n\t\t\t\treturn\n"
	out

# the entry: the function called at a pc it does not hold (its memory is never committed)
fn entryText():
	r"""
		import core
		import part

		c = core.Cpu()
		c.pc = 0
		part.f881b6b8(mut ref c)
		print("{c.pc} {c.x[19]}")

		"""

entry = args[0] if not args.isEmpty else "build/hugeFnShape/hugeFnShape.zap"
lines = arg(1, 16_000)
dir = fs.dirOf(entry)
_ = fs.createDir(dir)
_ = fs.writeFile("{dir}/core.zap", "{stateText()}\n{callsText()}")
_ = fs.writeFile("{dir}/part.zap", "import core\n\n{huge(lines)}")
_ = fs.writeFile(entry, entryText())
print("{entry}: a function of {lines} lines")
