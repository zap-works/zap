# The 3D engine's macros (the MME): small programs the driver uploads and then calls through the
# methods from 0xE00, each call's words its parameters. A program has eight 32-bit registers (r0
# reads zero), a carry, a method address it sends values to (bits 0-11 the method, 12-17 the step
# after each send), and instructions of 32 bits: the operation (bits 0-2), the result's use (4-6),
# exit (7), dst (8-10), src a (11-13), src b (14-16) or a signed immediate (14-31), and the ALU's
# operation or a bitfield's source bit, size and destination bit (17-31). A branch's next
# instruction runs before it lands unless it annuls. The semantics are envytools' and yuzu's
# (macro_interpreter).

# the registers that upload code and start addresses (each through its own pointer)
reg3dMacroCodePointer = 0x45
reg3dMacroStartPointer = 0x47
macroCodeWords = 0x2000
macroStarts = 0x80

# the most instructions a call runs before it is taken for a runaway
macroStepLimit = 0x10_0000

opBranch = 7

mask32 = 0xFFFF_FFFF

# a macro's state while it runs
type MacroRun:
	regs i64[] = zeros(8)
	carry bool = false
	methodAt i64 = 0   # the method address register: method and step
	params i64[] = []
	next i64 = 0   # the next parameter to fetch

	# the next parameter, 0 past the last (as the hardware gives)
	fn fetch():
		v = params[next] if next < params.len else 0
		next += 1
		v

	fn setReg(r i64, v i64):
		if r != 0: regs[r] = v & mask32

# An upload of macro code or a start address, or the pointer either goes through.
pub fn macroUpload(mut g Gpu, c i64, sub i64, method i64, arg i64):
	m = g.channels[c].engines[sub].macros
	if method == reg3dMacroCodePointer: g.channels[c].engines[sub].macros.codeAt = arg
	elif method == reg3dMacroStartPointer: g.channels[c].engines[sub].macros.startAt = arg
	elif method == reg3dMacroCode:
		at = m.codeAt % macroCodeWords
		g.channels[c].engines[sub].macros.code[at] = arg
		g.channels[c].engines[sub].macros.codeAt = at + 1
	elif method == reg3dMacroStart:
		at = m.startAt % macroStarts
		g.channels[c].engines[sub].macros.starts[at] = arg
		g.channels[c].engines[sub].macros.startAt = at + 1

# A word written to a macro's methods: an even method begins a call with its first parameter
# (running the call before it), an odd one adds a parameter to the call under way.
pub fn macroWord(mut g Gpu, c i64, sub i64, method i64, arg i64):
	id = (method - macroMethods) / 2
	if (method - macroMethods) % 2 == 0:
		g.flushMacro(c, sub)
		g.channels[c].engines[sub].macros.pending = id
	g.channels[c].engines[sub].macros.params.push(arg & mask32)

# The call under way run, if there is one: before any other method, and at a burst's end.
pub fn flushMacro(mut g Gpu, c i64, sub i64):
	id = g.channels[c].engines[sub].macros.pending
	if id < 0: return
	params = g.channels[c].engines[sub].macros.params.copy()
	g.channels[c].engines[sub].macros.pending = -1
	g.channels[c].engines[sub].macros.params.clear()
	g.stats.macroCalls += 1
	g.runMacro(c, sub, g.channels[c].engines[sub].macros.starts[id % macroStarts], params)

fn field(w i64, at i64, width i64):
	(w >> at) & ((1 << width) - 1)

# the ALU's operation on a and b, the carry kept
fn alu(mut run MacroRun, op i64, a i64, b i64):
	match op:
		0, 1:
			sum = a + b + (1 if op == 1 and run.carry else 0)
			run.carry = sum > mask32
			sum & mask32
		2, 3:
			diff = a - b - (0 if op == 2 or run.carry else 1)
			run.carry = diff >= 0
			diff & mask32
		8: a ^ b
		9: a | b
		10: a & b
		11: a & ~b & mask32
		12: ~(a & b) & mask32
		_: 0

# a value sent to the method the address names, the address stepped on
fn send(mut g Gpu, c i64, sub i64, mut run MacroRun, value i64):
	g.call(c, sub, run.methodAt & 0xFFF, value & mask32)
	run.methodAt = (run.methodAt & ~0xFFF) | ((run.methodAt + (run.methodAt >> 12)) & 0xFFF)

# what an instruction's result does: kept, sent, made the method address, a parameter fetched
fn result(mut g Gpu, c i64, sub i64, mut run MacroRun, how i64, dst i64, value i64):
	match how:
		0: run.setReg(dst, run.fetch())
		1: run.setReg(dst, value)
		2:
			run.setReg(dst, value)
			run.methodAt = value
		3:
			run.setReg(dst, run.fetch())
			g.send(c, sub, run, value)
		4:
			run.setReg(dst, value)
			g.send(c, sub, run, value)
		5:
			run.setReg(dst, run.fetch())
			run.methodAt = value
		6:
			run.setReg(dst, value)
			run.methodAt = value
			g.send(c, sub, run, run.fetch())
		_:
			run.setReg(dst, value)
			run.methodAt = value
			g.send(c, sub, run, (value >> 12) & 0x3F)

# one instruction that is not a branch
fn macroStep(mut g Gpu, c i64, sub i64, mut run MacroRun, w i64):
	a = run.regs[field(w, 11, 3)]
	b = run.regs[field(w, 14, 3)]
	imm = field(w, 14, 18)
	if imm >= 1 << 17: imm -= 1 << 18
	srcBit = field(w, 17, 5)
	sizeMask = (1 << field(w, 22, 5)) - 1
	dstBit = field(w, 27, 5)
	value = match field(w, 0, 3):
		0: run.alu(field(w, 17, 5), a, b)   # the ALU
		1: (a + imm) & mask32   # add an immediate
		2: (a & ~(sizeMask << dstBit) | (((b >> srcBit) & sizeMask) << dstBit)) & mask32   # extract, insert
		3: (((b >> a) & sizeMask) << dstBit) & mask32   # extract, shift left by an immediate
		4: (((b >> srcBit) & sizeMask) << a) & mask32   # extract, shift left by a register
		5: g.channels[c].engines[sub].regs[(a + imm) & 0xFFF] & mask32   # read an engine register
		_: 0
	g.result(c, sub, run, field(w, 4, 3), field(w, 8, 3), value)

# The macro whose code starts at `start` run with its parameters, r1 the first.
pub fn runMacro(mut g Gpu, c i64, sub i64, start i64, params i64[]):
	run = MacroRun(params = params.copy())
	run.setReg(1, run.fetch())
	pc = start
	landing = -1   # a taken branch's target, after its delay slot
	steps = 0
	exiting = false
	while steps < macroStepLimit:
		steps += 1
		w = g.channels[c].engines[sub].macros.code[pc % macroCodeWords]
		at = pc
		pc += 1
		inDelaySlot = landing >= 0 or exiting
		if landing >= 0:
			pc = landing
			landing = -1
		taken = false
		if field(w, 0, 3) == opBranch:
			value = run.regs[field(w, 11, 3)]
			taken = (value == 0) == (field(w, 4, 1) == 0)
			if taken:
				offset = field(w, 14, 18)
				target = at + (offset - (1 << 18) if offset >= 1 << 17 else offset)
				if field(w, 5, 1) == 1: pc = target
				else: landing = target
		else:
			g.macroStep(c, sub, run, w)
		if exiting: return
		# exit runs the next instruction first; a taken branch or a delay slot does not exit
		if field(w, 7, 1) == 1 and not taken and not inDelaySlot: exiting = true
	g.note("the macro at {start} ran {macroStepLimit} steps without its exit, parameters {params.map("{it:x}").join(" ")}")
