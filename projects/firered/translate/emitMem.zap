# Loads and stores as calls of gba's memory: a load from the cartridge at a constant address is
# its value, read when translating.

import arm

loadCalls = ["", "load8", "load16", "", "load32"]
signedLoadCalls = ["", "loadS8", "loadS16", "", ""]
storeCalls = ["", "store8", "store16", "", "store32"]

# the offset's value as an unsigned word added or taken away
fn offsetText(mut fnText FnText, i arm.Instr, offset arm.Operand) str:
	fnText.operandValue(i, offset)

fn addressOf(mut fnText FnText, i arm.Instr, n i64, offset arm.Operand, up bool):
	if offset is Imm(v, _) and v == 0: return i.reg(n)
	"{i.reg(n)} {"+" if up else "-"} {fnText.offsetText(i, offset)}"

# the value read from the cartridge at a constant address, for a load relative to the program
# counter
fn constantLoad(code Code, i arm.Instr) str?:
	match i.op:
		Load(size, signed, _, n, Imm(v, _), true, up, false) and n == arm.pc:
			base = (i.pcValue() & ~3) if i.thumb else i.pcValue()
			at = base + (v if up else -i64(v))
			if not code.isInRom(at): return none
			w = code.word(at & ~3) >> (8 * (at & 3))
			value = match size:
				1: i64(i8.wrap(w)) if signed else (w & 0xFF)
				2: i16.wrap(w) if signed else (w & 0xFFFF)
				_: w
			hex(u32.wrap(value))
		_: none

pub fn load(mut fnText FnText, depth i64, code Code, i arm.Instr):
	size, signed, d, n, offset, pre, up, back = match i.op:
		Load(size, signed, d, n, offset, pre, up, back): (size, signed, d, n, offset, pre, up, back)
		_: fail("no load")
	call = signedLoadCalls[size] if signed else loadCalls[size]
	if code.constantLoad(i) is value:
		fnText.writeReg(depth, i, d, value)
		return
	if not back:
		fnText.writeReg(depth, i, d, "gba.{call}({fnText.addressOf(i, n, offset, up)})")
		return
	a = fnText.temp("a")
	if pre:
		fnText.put(depth, "{a} = {fnText.addressOf(i, n, offset, up)}")
		if n != arm.pc: fnText.put(depth, "{regTarget(n)} = {a}")
	else:
		fnText.put(depth, "{a} = {i.reg(n)}")
		if n != arm.pc: fnText.put(depth, "{regTarget(n)} = {fnText.addressOf(i, n, offset, up)}")
	fnText.writeReg(depth, i, d, "gba.{call}({a})")

pub fn store(mut fnText FnText, depth i64, i arm.Instr):
	size, d, n, offset, pre, up, back = match i.op:
		Store(size, d, n, offset, pre, up, back): (size, d, n, offset, pre, up, back)
		_: fail("no store")
	value = hex(i.pcValue() + 4) if d == arm.pc else i.reg(d)
	if not back:
		fnText.put(depth, "gba.{storeCalls[size]}({fnText.addressOf(i, n, offset, up)}, {value})")
		return
	a = fnText.temp("a")
	fnText.put(depth, "{a} = {fnText.addressOf(i, n, offset, up) if pre else i.reg(n)}")
	fnText.put(depth, "gba.{storeCalls[size]}({a}, {value})")
	if n != arm.pc:
		fnText.put(depth, "{regTarget(n)} = {a if pre else fnText.addressOf(i, n, offset, up)}")

fn listRegs(list i64):
	(0..16).filter((list >> it) & 1 == 1)

# A load or store of several registers: the lowest register at the lowest address. A load into
# the program counter is a jump, last.
pub fn block(mut fnText FnText, depth i64, i arm.Instr):
	load, n, list, pre, up, back = match i.op:
		Block(load, n, list, pre, up, back, _): (load, n, list, pre, up, back)
		_: fail("no block")
	regs = listRegs(list)
	count = regs.len
	if count == 0: return
	a = fnText.temp("a")
	first = match (up, pre):
		(true, false): "{i.reg(n)}"
		(true, true): "{i.reg(n)} + 4"
		(false, false): "{i.reg(n)} - {4 * count - 4}"
		_: "{i.reg(n)} - {4 * count}"
	fnText.put(depth, "{a} = {first}")
	moved = "{i.reg(n)} + {4 * count}" if up else "{i.reg(n)} - {4 * count}"
	if load:
		if back and (list >> n) & 1 == 0: fnText.put(depth, "{regTarget(n)} = {moved}")
		fnText.loadAll(depth, a, regs, i)
		return
	fnText.storeAll(depth, a, regs, i)
	if back: fnText.put(depth, "{regTarget(n)} = {moved}")

fn at(a str, k i64):
	a if k == 0 else "{a} + {4 * k}"

fn loadAll(mut fnText FnText, depth i64, a str, regs i64[], i arm.Instr):
	for k, r in regs:
		if r == arm.pc:
			fnText.jump(
				depth,
				"gba.load32({at(a, k)}) | 1" if i.thumb else "gba.load32({at(a, k)}) & ~u32(1)"
			)
		else:
			fnText.put(depth, "{regTarget(r)} = gba.load32({at(a, k)})")

fn storeAll(mut fnText FnText, depth i64, a str, regs i64[], i arm.Instr):
	for k, r in regs:
		value = hex(i.pcValue() + 4) if r == arm.pc else i.reg(r)
		fnText.put(depth, "gba.store32({at(a, k)}, {value})")

pub fn swap(mut fnText FnText, depth i64, i arm.Instr):
	match i.op:
		Swap(byte, d, m, n):
			t = fnText.temp("s")
			size = "8" if byte else "32"
			fnText.put(depth, "{t} = gba.load{size}({i.reg(n)})")
			fnText.put(depth, "gba.store{size}({i.reg(n)}, {i.reg(m)})")
			fnText.put(depth, "{regTarget(d)} = {t}")
		_: fail("no swap")
