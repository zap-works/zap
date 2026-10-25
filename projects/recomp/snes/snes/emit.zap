# A function of the cartridge as a Zap function over the cpu module's registers and the console's
# memory. One without jumps inside it is its statements in order; any other is a loop over a match
# of its labels (code's keys), each arm the instructions from that label to the next. Each
# instruction first polls once the console has an interrupt due (entered there), then runs its bus
# cycles (cycles.zap) with what it does.
#
# A call pushes its return address and calls the function; the function's return pulls it into
# cpu.ret, and the caller goes on when it is the address after the call, else returns too (a
# return past the function that made it, until the one it returns to). A jump to another function
# calls it and returns, the address it returned to going up the same way, or on at a label of
# this function where a phk and pea pushed it.

import codegen

# a function's name: f, its address, the widths it starts in
pub fn functionName(k i64) str:
	w = widthsOf(k)
	"f{addressOf(k):06x}{"e" if w.e else ""}{"m" if w.m else ""}{"x" if w.x else ""}"

# the text of one function as it is written
pub type FnText:
	code codegen.Source
	dispatched bool   # a loop over a match of its labels, else straight statements
	patches {i64: Patch}   # by the address of the instruction each changes (game.zap)
	name str
	returnText str = "return"   # how the code it is in leaves (the interpreter's give `cpu.leaving`)

	# One instruction: its flow here, what it does in emitops; a branch taken costs an internal cycle
	# more (two in emulation mode across a page).
	fn instr(p Program, f Function, i Instr, live i64):
		if i.name in conditionalBranches:
			code.block("if {conditionText(i.name)}:")
			self.takeBranch(p, f, i)
			code.end()
			return
		match i.name:
			"bra": self.takeBranch(p, f, i)
			"brl": self.goTo(p, f, i.target(), i.widths)
			"jmp", "jml", "jsr", "jsl":
				if i.mode == "w" or i.mode == "l":
					if i.name == "jsr" or i.name == "jsl":
						self.call(p, f, i)
					else:
						self.goTo(p, f, i.jumpTargetOf(), i.widths)
				else:
					self.indirect(p, f, i)
			"rts":
				code.line("cpu.returnShort({hex(i.bank(), 2)}, {i.widths.widthBits()})")
				code.line("console.idle()")
				code.line("return")
			"rtl":
				code.line("cpu.returnLong({i.widths.widthBits()})")
				code.line("return")
			"rti":
				code.line("cpu.returnInterrupt()")
				code.line("return")
			"plp":
				code.block(
					"if cpu.pullStatus({f.afterOf(i.keyOf()).statusWidths()}, {i.nextText()}):"
				)
				self.leave(f)
				code.end()
			_: self.operation(i, live)

	# the lines the instruction's patch adds before it (game.zap: RetryBefore)
	mut fn patchedBefore(f Function, i Instr):
		if self.patches.get(i.at) is RetryBefore(_, _, condition, label):
			k = key(label, i.widths)
			if not (k in f.index): fail("patch table: no label 0x{label:06X} in {self.name}")
			code.block("if {condition}:")
			code.line("pc = {hex(k, 8)}")
			code.line("continue")
			code.end()

	# the lines its patch adds after it (After)
	mut fn patchedAfter(i Instr):
		if self.patches.get(i.at) is After(_, _, added):
			for line in added:
				code.line(line)

	mut fn takeBranch(p Program, f Function, i Instr):
		code.line("console.idle()")
		if i.crossesPage(): code.line("console.idle()")
		self.goTo(p, f, i.target(), i.widths)

	mut fn goTo(p Program, f Function, at i64, w Widths):
		k = key(at, w)
		if k in f.index:
			code.line("pc = {hex(k, 8)}")
			code.line("continue")
			return
		self.tailCall(p, f, at, w)

	mut fn tailCall(p Program, f Function, at i64, w Widths):
		code.line(p.callText(at, w))
		self.leave(f)

	# a return to where cpu.ret says: on at a label a phk and pea made, else out of the function
	mut fn leave(f Function):
		for k in f.returns.keys().sorted():
			code.block("if cpu.ret == {hex(addressOf(k), 6)}:")
			code.line("pc = {hex(k, 8)}")
			code.line("continue")
			code.end()
		code.line("return")

	# the return address a call pushes: the program bank for a long one (then an internal cycle and
	# its last fetch), the address of the call's last byte
	mut fn pushReturn(i Instr):
		if i.name == "jsl":
			code.line("cpu.push8({i.bankByteText()})")
			code.line("console.idle()")
			code.line("console.fetch(1, {i.atText()})")
		code.line("cpu.push16({"u16.wrap(nextAt - 1)" if i.symbolic else hex((i.next() - 1) & 0xFFFF, 4)})")

	# A call returned: past this function, it leaves too; in other widths than the flow assumed (a
	# function that returns in widths of its own), the code after the call goes on interpreted.
	mut fn afterCall(f Function, i Instr):
		code.block("if cpu.ret != {hex(i.next(), 6)}:")
		self.leave(f)
		code.end()
		w = f.afterOf(i.keyOf()).widthBits()
		code.block("if cpu.widthsNow != {w} and cpu.goOnInterpreted({hex(i.next(), 6)}):")
		self.leave(f)
		code.end()

	mut fn call(p Program, f Function, i Instr):
		self.pushReturn(i)
		code.line(p.callText(i.jumpTargetOf(), i.widths))
		self.afterCall(f, i)

	# A jump or a call through memory: the address read, then a match over the cases the cfg's
	# dispatch names, any other through the dispatcher.
	mut fn indirect(p Program, f Function, i Instr):
		calls = i.name == "jsr"
		t = self.indirectTargetLines(i)
		fallback = "cpu.go({t}, {i.widths.widthBits()})"
		if f.dispatches.get(i.at) is d:
			code.block("match {t}:")
			seen {i64: bool} = {}
			for c in d.targets:
				if c in seen: continue
				seen[c] = true
				k = key(c, i.widths)
				if not calls and not d.calls and k in f.index:
					code.block("{hex(c, 6)}:")
					code.line("pc = {hex(k, 8)}")
					code.line("continue")
					code.end()
				else:
					code.line("{hex(c, 6)}: {p.callText(c, i.widths)}")
			code.line("_: {fallback}")
			code.end()
		else:
			code.line(fallback)
		if calls:
			self.afterCall(f, i)
		else:
			self.leave(f)

	# The lines that read where a jump or call through memory goes, into a temporary it names: a
	# jsr (a,x) pushes its return between its operand's fetches, then adds X.
	mut fn indirectTargetLines(i Instr):
		t = code.temp("t")
		if i.name == "jsr":
			self.pushReturn(i)
			code.line("console.fetch(1, {i.atText()})")
			code.line("console.idle()")
		code.line("{t} u32 = {i.indirectTarget()}")
		t

# the address a jump or call through memory reads, as the instruction's mode makes it
fn indirectTarget(i Instr):
	bank = "at & 0xFF_0000" if i.symbolic else hex(i.at & 0xFF_0000, 6)
	high = "({bank})" if i.symbolic else bank
	v = i.valueText()
	match i.mode:
		"(w,x)": "{high} | u32(cpu.read16In({bank}, {v} + u32(cpu.x)))"
		"(w)": "{high} | u32(cpu.readData16Bank0({v}))"
		_: "cpu.read24Bank0({v})"

# an integer of the code written as fmt writes it, in as many hexadecimal digits
fn hex(v i64, digits i64):
	match digits:
		2: "{v:#02X}"
		4: "{v:#04X}"
		6: "{v:#06X}"
		_: "{v:#08X}"

# the first instruction of each run that no jump lands inside: a label, one the instruction
# before does not go on to, or one an instruction elsewhere goes on to (a sep or rep reached in
# two widths)
fn blockStarts(f Function):
	starts bool[] = zeros(f.instrs.len)
	for k, i in f.instrs:
		if k == 0 or keyOf(i) in f.labels:
			starts[k] = true
			continue
		before = f.instrs[k - 1]
		starts[k] = not before.fallsThrough() or
			key(before.next(), f.afterOf(before.keyOf())) != keyOf(i)
	for k, i in f.instrs:
		if not i.fallsThrough(): continue
		if f.index.get(key(i.next(), f.afterOf(i.keyOf()))) is n and n != k + 1: starts[n] = true
	starts

# the labels a jump reaches from an instruction at or after them: the heads of loops
fn loopHeads(f Function):
	out {i64: bool} = {}
	for i in f.instrs:
		for k in f.successorKeys(i):
			if k in f.index and addressOf(k) <= i.at and k != key(i.next(), f.afterOf(i.keyOf())):
				out[k] = true
	out

# The Zap text of the function.
pub fn emitFunction(p Program, f Function) str[]:
	live = f.liveAfter()
	starts = f.blockStarts()
	heads = f.loopHeads()
	dispatched = starts.count(true) > 1 or f.instrs[0].keyOf() != f.entryKey() or
		f.entryKey() in heads
	e = FnText(
		code = codegen.Source(),
		dispatched,
		patches = p.patches.copy(),
		name = functionName(f.entryKey())
	)
	e.code.block("fn {e.name}():")
	e.code.line("if cpu.tracing: cpu.entered({hex(addressOf(f.entryKey()), 6)})")
	if dispatched:
		e.code.line("pc u32 = {hex(f.entryKey(), 8)}")
		e.code.block("loop:")
		e.code.block("match pc:")
	k = 0
	while k < f.instrs.len:
		start = k
		k += 1
		while k < f.instrs.len and not starts[k]:
			k += 1
		first = f.instrs[start].keyOf()
		if dispatched: e.code.block("{hex(first, 8)}:")
		for j in start..k:
			i = f.instrs[j]
			e.code.line(
				"if console.cycles >= console.eventDue and cpu.poll({hex(i.at, 6)}, {i.widths.statusWidths()}): return"
			)
			for line in i.leadCycles():
				e.code.line(line)
			e.patchedBefore(f, i)
			e.instr(p, f, i, live[j])
			e.patchedAfter(i)
		last = f.instrs[k - 1]
		if last.fallsThrough():
			next = key(last.next(), f.afterOf(last.keyOf()))
			if next in f.index:
				e.code.line("pc = {hex(next, 8)}")
			else:
				e.tailCall(p, f, addressOf(next), widthsOf(next))
		if dispatched: e.code.end()
	if dispatched:
		e.code.block("_:")
		e.code.line("cpu.noLabel(pc, \"{e.name}\")")
		e.code.line("return")
		e.code.end()
	e.code.lines

fn conditionText(name str):
	match name:
		"bcc": "not cpu.c"
		"bcs": "cpu.c"
		"beq": "cpu.z"
		"bne": "not cpu.z"
		"bmi": "cpu.n"
		"bpl": "not cpu.n"
		"bvc": "not cpu.v"
		_: "cpu.v"

# the function at the address called in the widths: by its name when the program has it, else
# through the dispatcher
fn callText(p Program, at i64, w Widths):
	k = key(at, w)
	if k in p.index: return "{functionName(k)}()"
	"cpu.go({hex(at, 6)}, {w.widthBits()})"
