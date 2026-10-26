# The interpreter's instructions: every opcode in every widths it runs in written as a Zap function
# by the same translation as the cartridge's code (emitOps, emitMem, cycles), its address, operand
# and the address after it the function's variables (Instr.symbolic). cpu.interpret runs them where
# no translated function is: code the game writes into RAM, an address no jump the preparation saw
# reaches, a task resumed in the middle of a function. The same bus cycles, the same flags.
#
# A function takes the instruction's address and gives the next one to run, or cpu.leaving when a
# return took the code past it (cpu.ret where); the widths it leaves in are cpu.widthsNow.

import codegen

# the widths an instruction runs in: native mode's four, and emulation mode's
interpretedWidths = [
	Widths(e = false, m = false, x = false),
	Widths(e = false, m = false, x = true),
	Widths(e = false, m = true, x = false),
	Widths(e = false, m = true, x = true),
	powerOn
]

# the interpreter's function of an opcode in widths
fn interpretedName(opcode i64, w Widths):
	"i{opcode:02x}{w.widthBits()}"

# The functions of every opcode in every widths, a text each, and the step that runs one:
# `step(at, widths)` the instruction at `at`.
pub fn interpreterTexts(d Decoder) (str[], str):
	texts = []
	step = codegen.Source()
	step.line("# the instruction at `at` run in `widths` (bits e, m, x): the address of the next, or cpu.leaving")
	step.block("pub fn step(at u32, widths u32) u32:")
	step.block("match u32(console.read8(at)) | (widths << 8):")
	for row in d.rows:
		for w in interpretedWidths:
			size = 1 + operandSize(row.mode, w)
			i = Instr(
				at = -1,
				opcode = row.opcode,
				name = row.name.copy(),
				mode = row.mode.copy(),
				value = -1,
				size,
				widths = w,
				symbolic = true
			)
			name = interpretedName(row.opcode, w)
			texts.push("\n{i.interpretedFunction(name).join("\n")}\n")
			step.line("{row.opcode | (w.widthBits() << 8):#03X}: return {name}(at)")
	step.line("_: pass")
	step.end()
	step.line("cpu.unsupported(at, \"an opcode in widths \{widths}\")")
	step.line("cpu.leaving")
	step.end()
	(texts, "\n{step.text()}")

# One instruction as an interpreter's function: its cycles and what it does, then the address
# after it unless it went elsewhere.
fn interpretedFunction(i Instr, name str):
	ft = FnText(
		code = codegen.Source(level = 1),
		dispatched = false,
		patches = {},
		name = name.copy(),
		returnText = "return cpu.leaving"
	)
	for line in i.leadCycles():
		ft.code.line(line)
	ft.interpreted(i)
	if ft.code.lines.isEmpty or not ft.code.lines[len - 1].startsWith("\treturn "):
		ft.code.line("return nextAt")
	body = ft.code.lines.join("\n")
	out = codegen.Source()
	out.block("fn {name}(at u32) u32:")
	if "operand" in body: out.line("operand = cpu.operandAt(at, {i.size - 1})")
	if "nextAt" in body: out.line("nextAt = (at & 0xFF_0000) | ((at + {i.size}) & 0xFFFF)")
	out.lines.extend(ft.code.lines)
	out.lines

# What the instruction does where the interpreter runs it: its flow by the address it gives,
# the widths rep, sep and plp leave read from the status they make, the rest as translated.
fn interpreted(mut ft FnText, i Instr):
	bits = i.widths.widthBits()
	if i.name in conditionalBranches:
		ft.code.block("if {conditionText(i.name)}:")
		ft.branchTaken(i)
		ft.code.end()
		return
	match i.name:
		"bra": ft.branchTaken(i)
		"brl": ft.code.line("return {i.targetText()}")
		"jmp", "jml", "jsr", "jsl":
			calls = i.name == "jsr" or i.name == "jsl"
			target = ""
			if i.mode == "w":
				if calls: ft.pushReturn(i)
				target = "(at & 0xFF_0000) | operand"
			elif i.mode == "l":
				if calls: ft.pushReturn(i)
				target = "operand"
			else:
				target = ft.indirectTargetLines(i)
			if not calls:
				ft.code.line("return {target}")
				return
			ft.code.line("cpu.goFrom({target}, {bits})")
			ft.code.line("if cpu.ret != nextAt: return cpu.leaving")
		"rts":
			ft.code.line("cpu.returnShort(at >> 16, {bits})")
			ft.code.line("console.idle()")
			ft.code.line("return cpu.leaving")
		"rtl":
			ft.code.line("cpu.returnLong({bits})")
			ft.code.line("return cpu.leaving")
		"rti":
			ft.code.line("cpu.returnInterrupt()")
			ft.code.line("return cpu.leaving")
		"plp": ft.code.line("cpu.pullStatusAny()")
		"rep", "sep": ft.code.line("cpu.changeStatus(u8.wrap(operand), {i.name == "sep"})")
		_: ft.operation(i, allFlags)

# a branch taken: an internal cycle, one more in emulation mode across a page, then its target
fn branchTaken(mut ft FnText, i Instr):
	ft.code.line("console.idle()")
	if i.widths.e:
		ft.code.line("if ({i.targetText()} ^ nextAt) & 0xFF00 != 0: console.idle()")
	ft.code.line("return {i.targetText()}")
