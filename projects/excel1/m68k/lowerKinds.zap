# The 68000's kinds of instruction lowered to steps, by family (lower.zap holds the places and
# the flags they share).

import cpu

fn regNumber(o Operand):
	8 + o.reg if o.mode == .A else o.reg

fn lowerMove(mut l Lowering, i Inst):
	size = i.size
	match i.kind:
		Move:
			if i.src.mode == .Usp or i.dst.mode == .Usp:
				l.setReg(
					i.dst.regNumber() if i.dst.mode != .Usp else 16,
					l.getReg(16 if i.src.mode == .Usp else i.src.regNumber())
				)
				return
			v = l.fetch(l.locate(i.src, size), size)
			isFlagged = i.dst.mode != .Ccr and i.dst.mode != .Sr and i.src.mode != .Sr
			l.store(l.locate(i.dst, size), v, size)
			if isFlagged: l.logicFlags(v, size)
		Movea:
			v = l.fetch(l.locate(i.src, size), size)
			if size == 2: v = l.unary(.Sext, v, 2)
			l.setReg(8 + i.dst.reg, v)
		Moveq:
			v = l.constant(i.src.value)
			l.setReg(i.dst.reg, v)
			l.logicFlags(v, 4)
		Lea: l.setReg(8 + i.dst.reg, l.addressOf(i.src))
		Pea: l.pushValue(l.addressOf(i.src))
		Clr:
			p = l.locate(i.src, size)
			zero = l.constant(0)
			l.store(p, zero, size)
			l.logicFlags(zero, size)
		Exg:
			a = i.src.regNumber()
			b = i.dst.regNumber()
			va = l.getReg(a)
			vb = l.getReg(b)
			l.setReg(a, vb)
			l.setReg(b, va)
		Swap:
			v = l.getReg(i.src.reg)
			sixteen = l.constant(16)
			r = l.binary(.Or, l.binary(.Shl, v, sixteen), l.binary(.Shr, v, sixteen))
			l.setReg(i.src.reg, r)
			l.logicFlags(r, 4)
		Ext:
			r = l.unary(.Sext, l.getReg(i.src.reg), size / 2)
			l.setReg(i.src.reg, r, size)
			l.logicFlags(r, size)
		Link:
			an = 8 + i.src.reg
			l.pushValue(l.getReg(an))
			sp = l.getReg(15)
			l.setReg(an, sp)
			l.setReg(15, l.addConstant(sp, i16.wrap(i.dst.value)))
		Unlk:
			an = 8 + i.src.reg
			frame = l.getReg(an)
			saved = l.put(cpu.Step(op = .Load, a = frame, size = 4))
			l.setReg(15, l.addConstant(frame, 4))
			l.setReg(an, saved)
		Movem: l.lowerMovem(i)
		_: l.lowerMovep(i)

# MOVEM: the registers of the mask (d0-d7 then a0-a7, reversed for -(An)) to memory or from it,
# words sign-extended into the registers
fn lowerMovem(mut l Lowering, i Inst):
	size = i.size
	isToMemory = i.src.mode == .List
	mask = i.src.value if isToMemory else i.dst.value
	o = i.dst if isToMemory else i.src
	if o.mode == .PreDec:
		an = 8 + o.reg
		at = l.getReg(an)
		values = []
		for bit in 0..16:
			if mask >> bit & 1 != 0: values.push((15 - bit, l.getReg(15 - bit)))
		for (_, v) in values:
			at = l.addConstant(at, -size)
			l.emit(cpu.Step(op = .Store, a = at, b = v, size))
		l.setReg(an, at)
		return
	at = l.getReg(8 + o.reg) if o.mode == .PostInc else l.addressOf(o)
	for r in 0..16:
		if mask >> r & 1 == 0: continue
		if isToMemory:
			l.emit(cpu.Step(op = .Store, a = at, b = l.getReg(r), size))
		else:
			v = l.put(cpu.Step(op = .Load, a = at, size))
			if size == 2: v = l.unary(.Sext, v, 2)
			l.setReg(r, v)
		at = l.addConstant(at, size)
	if o.mode == .PostInc: l.setReg(8 + o.reg, at)

# MOVEP: a register's bytes to or from every other byte of memory, the highest first
fn lowerMovep(mut l Lowering, i Inst):
	size = i.size
	isToMemory = i.src.mode == .D
	o = i.dst if isToMemory else i.src
	dn = i.src.reg if isToMemory else i.dst.reg
	base = l.addConstant(l.getReg(8 + o.reg), o.value)
	if isToMemory:
		v = l.getReg(dn)
		for k in 0..size:
			byte = l.binary(.Shr, v, l.constant((size - 1 - k) * 8))
			l.emit(cpu.Step(op = .Store, a = l.addConstant(base, 2 * k), b = byte, size = 1))
		return
	v = l.constant(0)
	for k in 0..size:
		byte = l.put(cpu.Step(op = .Load, a = l.addConstant(base, 2 * k), size = 1))
		v = l.binary(.Or, l.binary(.Shl, v, l.constant(8)), byte)
	l.setReg(dn, v, size)

fn lowerArithmetic(mut l Lowering, i Inst):
	size = i.size
	isSub = match i.kind:
		Sub, Suba, Subx, Cmp, Cmpa, Cmpm, Neg, Negx: true
		_: false
	op cpu.Op = .Sub if isSub else .Add
	match i.kind:
		Adda, Suba, Cmpa:
			s = l.fetch(l.locate(i.src, size), size)
			if size == 2: s = l.unary(.Sext, s, 2)
			an = 8 + i.dst.reg
			d = l.getReg(an)
			r = l.binary(op, d, s)
			if i.kind == .Cmpa:
				l.arithmeticFlags(true, d, s, r, 4, hasX = false, keepsZ = false)
			else:
				l.setReg(an, r)
		Neg, Negx:
			p = l.locate(i.src, size)
			v = l.fetch(p, size)
			zero = l.constant(0)
			r = l.binary(.Sub, zero, v)
			if i.kind == .Negx: r = l.binary(.Sub, r, l.xBit())
			l.store(p, r, size)
			l.arithmeticFlags(true, zero, v, r, size, hasX = true, keepsZ = i.kind == .Negx)
		_:
			if i.dst.mode == .A:
				# ADDQ and SUBQ to an address register: all 32 bits, no flags
				an = 8 + i.dst.reg
				l.setReg(an, l.binary(op, l.getReg(an), l.constant(i.src.value)))
				return
			s = l.fetch(l.locate(i.src, size), size)
			p = l.locate(i.dst, size)
			d = l.fetch(p, size)
			r = l.binary(op, d, s)
			isExtended = i.kind == .Addx or i.kind == .Subx
			if isExtended: r = l.binary(op, r, l.xBit())
			isCompare = i.kind == .Cmp or i.kind == .Cmpm
			if not isCompare: l.store(p, r, size)
			l.arithmeticFlags(isSub, d, s, r, size, hasX = not isCompare, keepsZ = isExtended)

fn lowerLogic(mut l Lowering, i Inst):
	size = i.size
	match i.kind:
		And, Or, Eor:
			op cpu.Op = match i.kind:
				And: .And
				Or: .Or
				_: .Xor
			s = l.fetch(l.locate(i.src, size), size)
			p = l.locate(i.dst, size)
			d = l.fetch(p, size)
			r = l.binary(op, d, s)
			l.store(p, r, size)
			if not p.isCcr and not p.isSr: l.logicFlags(r, size)
		Not:
			p = l.locate(i.src, size)
			r = l.unary(.Not, l.fetch(p, size))
			l.store(p, r, size)
			l.logicFlags(r, size)
		Tst: l.logicFlags(l.fetch(l.locate(i.src, size), size), size)
		Tas:
			p = l.locate(i.src, 1)
			v = l.fetch(p, 1)
			l.logicFlags(v, 1)
			l.store(p, l.binary(.Or, v, l.constant(0x80)), 1)
		_:
			s = l.fetch(l.locate(i.src, 2), 2)
			d = l.getReg(i.dst.reg)
			isSigned = i.kind == .Muls
			a = l.unary(.Sext if isSigned else .Zext, d, 2)
			b = l.unary(.Sext if isSigned else .Zext, s, 2)
			r = l.binary(.Mul, a, b)
			l.setReg(i.dst.reg, r)
			l.logicFlags(r, 4)

fn lowerBit(mut l Lowering, i Inst):
	isRegister = i.dst.mode == .D
	size = 4 if isRegister else 1
	bit = l.fetch(l.locate(i.src, 4), 4)
	p = l.locate(i.dst, size)
	v = l.fetch(p, size)
	n = l.binary(.And, bit, l.constant(31 if isRegister else 7))
	m = l.binary(.Shl, l.constant(1), n)
	l.flag(cpu.flagZ, l.binary(.Eq, l.binary(.And, v, m), l.constant(0)))
	r = match i.kind:
		Bchg: l.binary(.Xor, v, m)
		Bclr: l.binary(.And, v, l.unary(.Not, m))
		Bset: l.binary(.Or, v, m)
		_: -1
	if r >= 0: l.store(p, r, size)

fn helperOf(k Kind):
	match k:
		Asl: cpu.helperAsl
		Asr: cpu.helperAsr
		Lsl: cpu.helperLsl
		Lsr: cpu.helperLsr
		Rol: cpu.helperRol
		Ror: cpu.helperRor
		Roxl: cpu.helperRoxl
		Roxr: cpu.helperRoxr
		Divu: cpu.helperDivu
		Divs: cpu.helperDivs
		Abcd: cpu.helperAbcd
		Sbcd, Nbcd: cpu.helperSbcd
		Chk: cpu.helperChk
		_: cpu.helperTrapv

fn callHelper(mut l Lowering, k Kind, a i64, b i64, size i64) i64:
	l.put(cpu.Step(op = .Helper, a, b, size, k = k.helperOf()))

fn lowerShift(mut l Lowering, i Inst):
	if i.dst.mode == .None:
		p = l.locate(i.src, 2)
		r = l.callHelper(i.kind, l.fetch(p, 2), l.constant(1), 2)
		l.store(p, r, 2)
		return
	count = l.constant(i.src.value) if i.src.mode == .Imm else l.getReg(i.src.reg)
	r = l.callHelper(i.kind, l.getReg(i.dst.reg), count, i.size)
	l.setReg(i.dst.reg, r, i.size)

fn lowerHelper(mut l Lowering, i Inst):
	match i.kind:
		Divu, Divs, Chk:
			s = l.fetch(l.locate(i.src, 2), 2)
			if i.kind != .Chk:
				isZero = l.binary(.Eq, l.put(cpu.Step(op = .Zext, a = s, size = 2)), l.constant(0))
				l.emit(cpu.Step(op = .ExceptionIf, a = isZero, k = 5))
			r = l.callHelper(i.kind, l.getReg(i.dst.reg), s, 2)
			if i.kind != .Chk: l.setReg(i.dst.reg, r)
		Abcd, Sbcd:
			s = l.fetch(l.locate(i.src, 1), 1)
			p = l.locate(i.dst, 1)
			r = l.callHelper(i.kind, l.fetch(p, 1), s, 1)
			l.store(p, r, 1)
		Nbcd:
			p = l.locate(i.src, 1)
			r = l.callHelper(i.kind, l.constant(0), l.fetch(p, 1), 1)
			l.store(p, r, 1)
		_: l.callHelper(i.kind, -1, -1, 4)

fn lowerFlow(mut l Lowering, i Inst):
	match i.kind:
		Bra: l.emit(cpu.Step(op = .Jump, k = i.target))
		Bsr:
			l.pushValue(l.put(cpu.Step(op = .Code, k = l.next)))
			l.emit(cpu.Step(op = .Jump, k = i.target))
		Bcc: l.emit(
			cpu.Step(op = .JumpIf, a = l.put(cpu.Step(op = .Cond, k = i.cond)), k = i.target)
		)
		Dbcc:
			c = l.put(cpu.Step(op = .Cond, k = i.cond))
			v = l.getReg(i.src.reg)
			r = l.addConstant(v, -1)
			l.setReg(i.src.reg, l.put(cpu.Step(op = .Select, a = c, b = v, c = r)), 2)
			ended = l.binary(.Eq, l.unary(.Zext, r, 2), l.constant(0xFFFF))
			stays = l.binary(.Or, c, ended)
			l.emit(cpu.Step(op = .JumpIf, a = l.binary(.Eq, stays, l.constant(0)), k = i.target))
		Scc:
			c = l.put(cpu.Step(op = .Cond, k = i.cond))
			v = l.put(cpu.Step(op = .Select, a = c, b = l.constant(0xFF), c = l.constant(0)))
			l.store(l.locate(i.src, 1), v, 1)
		Jmp, Jsr:
			isStatic = i.src.mode == .PcDisp
			target = -1 if isStatic else l.addressOf(i.src)
			if i.kind == .Jsr: l.pushValue(l.put(cpu.Step(op = .Code, k = l.next)))
			if isStatic:
				l.emit(cpu.Step(op = .Jump, k = i.src.value))
			else:
				l.emit(cpu.Step(op = .JumpTo, a = target))
		Rts: l.emit(cpu.Step(op = .JumpTo, a = l.popValue(4)))
		Rte, Rtr:
			status = l.popValue(2)
			back = l.popValue(4)
			l.emit(cpu.Step(op = .PutSr if i.kind == .Rte else .PutCcr, a = status))
			l.emit(cpu.Step(op = .JumpTo, a = back))
		Trap: l.emit(cpu.Step(op = .Exception, k = 32 + i.src.value))
		Illegal: l.emit(cpu.Step(op = .Exception, k = 4))
		Fline: l.emit(cpu.Step(op = .Exception, k = 11))
		Aline: l.emit(cpu.Step(op = .Aline, k = i.word))
		Stop: l.emit(cpu.Step(op = .Stop, k = i.src.value))
		_: pass
