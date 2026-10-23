# Writes a program of the SNES recompiler's shape (projects/recomp/snes on branch snes2zap): many
# small generated functions on the 65816's registers (byte and word arithmetic, flags, calls
# between them), one interpreter function per opcode and width, and dispatch matches of
# thousands of integer arms. Its build is the measured case of compile time for such programs.
# zap test --only size
# writes: build/recompshape/recompshape.zap (the program measured, its stem this file's)
#
#   zap run tools/recompshape.zap [entry] [translated] [interpreted]

import fs

# the opcode and width keys of the interpreter's functions, as the recompiler numbers them
fn interpreted(count i64):
	(0..count).map(u32(it % 256) | (u32(it / 256) << 8))

fn hex(v u32):
	"0x{v:08X}"

# the 65816's state and the console's services the generated functions call
fn cpuModule():
	"""
		# The registers the generated functions read and write, and what they call.

		pub mut a u16 = 0
		pub mut x u16 = 0
		pub mut y u16 = 0
		pub mut d u16 = 0
		pub mut n bool = false
		pub mut z bool = false
		pub mut c bool = false
		pub mut v bool = false
		pub mut cycles i64 = 0
		pub mut due i64 = 1_000_000
		pub mut ram u8[] = fill(0x20000, u8(0))

		pub fn poll(at u32) bool:
			cycles += i64(at & 7) + 6
			cycles > due

		pub fn fetch(bytes i64, at u32):
			cycles += bytes * 8 + i64(at & 1)

		pub fn data(at u32) u32:
			(at + u32(d)) & 0x1FFFF

		pub fn read8(at u32) u8:
			ram[i64(at & 0x1FFFF)]

		pub fn read16(at u32) u16:
			u16(ram[i64(at)]) | (u16(ram[i64((at + 1) & 0x1FFFF)]) << 8)

		pub fn write8(at u32, value u8):
			ram[i64(at & 0x1FFFF)] = value

		pub fn write16(at u32, value u16):
			ram[i64(at)] = u8.wrap(value)
			ram[i64((at + 1) & 0x1FFFF)] = u8.wrap(value >> 8)

		pub fn noLabel(pc u32):
			cycles += i64(pc & 3)

		"""

# one instruction of a translated function, by its kind
fn instruction(mut rng Random, at u32, step i64, callees str[]):
	addr = u32(rng.nextInt(0, 0x1_FFFF))
	imm = rng.nextInt(0, 256)
	v = "v{step}"
	body = "\t\t\t\tif cpu.cycles >= cpu.due and cpu.poll(0x{at:06X}): return\n"
	body += "\t\t\t\tcpu.fetch({rng.nextInt(1, 4)}, 0x{at:06X})\n"
	match rng.nextInt(0, 9):
		0: body += "\t\t\t\t{v} u8 = 0x{imm:02X}\n\t\t\t\tcpu.a = (cpu.a & 0xFF00) | u16({v})\n\t\t\t\tcpu.n = {v} & 0x80 != 0\n\t\t\t\tcpu.z = {v} == 0\n"
		1: body += "\t\t\t\t{v} u16 = cpu.read16(cpu.data(0x{addr:05X}))\n\t\t\t\tcpu.a = {v}\n\t\t\t\tcpu.n = {v} & 0x8000 != 0\n\t\t\t\tcpu.z = {v} == 0\n"
		2: body += "\t\t\t\tcpu.write8(cpu.data(0x{addr:05X}), u8.wrap(cpu.a))\n"
		3: body += "\t\t\t\t{v} u16 = (cpu.a & 0xFF) + u16(cpu.read8(cpu.data(0x{addr:05X}))) + (1 if cpu.c else 0)\n\t\t\t\tcpu.c = {v} > 0xFF\n\t\t\t\tcpu.a = (cpu.a & 0xFF00) | ({v} & 0xFF)\n\t\t\t\tcpu.z = {v} & 0xFF == 0\n"
		4: body += "\t\t\t\tcpu.x = cpu.x + 1\n\t\t\t\tcpu.n = cpu.x & 0x8000 != 0\n\t\t\t\tcpu.z = cpu.x == 0\n"
		5: body += "\t\t\t\t{v} u16 = cpu.a ^ 0x{imm:02X}{imm:02X}\n\t\t\t\tcpu.a = {v}\n\t\t\t\tcpu.z = {v} == 0\n"
		6: body += "\t\t\t\tcpu.c = cpu.a & 0x8000 != 0\n\t\t\t\tcpu.a = cpu.a << 1\n\t\t\t\tcpu.z = cpu.a == 0\n"
		7: body += "\t\t\t\tcpu.write16(cpu.data(0x{addr:05X} + u32(cpu.y)), cpu.a)\n\t\t\t\tcpu.y = cpu.y - 1\n"
		_:
			if callees.isEmpty:
				body += "\t\t\t\tcpu.c = cpu.a >= 0x{imm:02X}\n"
			else:
				body += "\t\t\t\t{callees[rng.nextInt(0, callees.len)]}()\n"
	body

# A translated function: its blocks as the arms of a match on pc, each a few instructions and a
# branch forward, so a run ends
fn translated(mut rng Random, name str, start u32, callees str[]):
	blocks = rng.nextInt(2, 6)
	out = "fn {name}():\n\tpc u32 = {hex(start)}\n\tloop:\n\t\tmatch pc:\n"
	step = 1
	for b in 0..blocks:
		at = start + u32(b * 16)
		out += "\t\t\t{hex(at)}:\n"
		loop rng.nextInt(2, 7):
			out += rng.instruction(at + u32(step), step, callees)
			step += 1
		if b + 1 == blocks:
			out += "\t\t\t\treturn\n"
		else:
			target = start + u32(rng.nextInt(b + 1, blocks) * 16)
			out += "\t\t\t\tpc = {hex(target)} if cpu.z else {hex(at + 16)}\n"
	out += "\t\t\t_:\n\t\t\t\tcpu.noLabel(pc)\n\t\t\t\treturn\n\n"
	out

# The interpreter's function for one opcode in one width: the instruction at `at` run, the next
# one's address given
fn interpreter(mut rng Random, key u32):
	name = "i{key:03x}"
	wide = key >> 8 & 2 == 0
	out = "fn {name}(at u32) u32:\n"
	out += "\toperand = u32(cpu.read8((at + 1) & 0x1FFFF))\n"
	out += "\tnextAt = (at & 0xFF_0000) | ((at + {rng.nextInt(1, 4)}) & 0xFFFF)\n"
	out += "\tcpu.fetch(2, at)\n"
	if wide:
		out += "\tv1 u16 = cpu.a | cpu.read16(cpu.data(operand + u32(cpu.x)))\n\tcpu.a = v1\n\tcpu.n = v1 & 0x8000 != 0\n\tcpu.z = v1 == 0\n"
	else:
		out += "\tv1 u8 = u8.wrap(cpu.a) & cpu.read8(cpu.data(operand + u32(cpu.y)))\n\tcpu.a = (cpu.a & 0xFF00) | u16(v1)\n\tcpu.n = v1 & 0x80 != 0\n\tcpu.z = v1 == 0\n"
	out += "\treturn nextAt\n\n"
	out

# the dispatchers: the function at an address in widths, the one it starts at, the interpreter's
# step by opcode and width
fn dispatch(names str[], starts u32[], widths u32[], keys u32[]):
	out = "pub fn callExact(at u32, widths u32) bool:\n\tmatch at | (widths << 24):\n"
	for i, name in names:
		out += "\t\t{hex(starts[i] | (widths[i] << 24))}: {name}()\n"
	out += "\t\t_: return false\n\ttrue\n\n"
	out += "pub fn callStart(at u32) bool:\n\tmatch at:\n"
	for i, name in names:
		if i == 0 or starts[i] != starts[i - 1]:
			out += "\t\t{hex(starts[i])}: {name}()\n"
	out += "\t\t_: return false\n\ttrue\n\n"
	out += "pub fn step(at u32, widths u32) u32:\n\tmatch u32(cpu.read8(at)) | (widths << 8):\n"
	for key in keys:
		out += "\t\t{hex(key)}: return i{key:03x}(at)\n"
	out += "\t\t_: return at + 1\n\n"
	out

# The translated functions, written a file of 400 each, as the recompiler orders them: by
# address, an address translated in one to four widths, each calling a few of those before it
type Translated:
	names str[]
	starts u32[]
	widths u32[]

fn writeTranslated(dir str, mut rng Random, count i64, head str):
	out = Translated(names = [], starts = [], widths = [])
	text = head.copy()
	file = 0
	at = u32(0x80_8000)
	for i in 0..count:
		w = u32(rng.nextInt(0, 4))
		if i > 0 and out.widths[i - 1] < 3 and rng.nextInt(0, 3) == 0:
			w = out.widths[i - 1] + 1
		else:
			at += u32(rng.nextInt(1, 40) * 16)
		name = "f{at:06x}{["", "x", "m", "mx"][w]}"
		callees = []
		for j in (out.names.len - 200).max(0)..out.names.len:
			if rng.nextInt(0, 60) == 0:
				callees.push(out.names[j].copy())
		text += rng.translated(name, at, callees)
		out.names.push(name)
		out.starts.push(at)
		out.widths.push(w)
		if (i + 1) % 400 == 0 or i + 1 == count:
			_ = fs.writeFile("{dir}/game/functions{file}.zap", text)
			text = head.copy()
			file += 1
	out

# the entry: each dispatcher called, so that every function is built
fn entryText(first u32):
	"""
		import cpu
		import game

		mut at = 0
		for i in 0..200:
			_ = game.callStart({hex(first)} + u32(i * 16))
			_ = game.callExact({hex(first)} + u32(i * 16), u32(i % 4))
			at = game.step(u32(i), u32(i % 4))
		print("\{cpu.a} \{cpu.cycles} \{at}")

		"""

entry = args[0] if not args.isEmpty else "build/recompshape/recompshape.zap"
count = arg(1, 2700)
opcodes = arg(2, 1280)
dir = fs.dirOf(entry)
rng = Random(65_816)
_ = fs.createDir("{dir}/game")
_ = fs.writeFile("{dir}/cpu.zap", cpuModule())
head = "import cpu\n\n"
made = writeTranslated(dir, rng, count, head)
keys = interpreted(opcodes)
text = head
for key in keys:
	text += rng.interpreter(key)
_ = fs.writeFile("{dir}/game/interpret.zap", text)
_ = fs.writeFile(
	"{dir}/game/dispatch.zap",
	head + dispatch(made.names, made.starts, made.widths, keys)
)
_ = fs.writeFile(entry, entryText(made.starts[0]))
print("{entry}: {count} translated functions, {opcodes} interpreted")
