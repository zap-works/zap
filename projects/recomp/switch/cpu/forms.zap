# long: written by tools/forms.zap, a function of branches over each operation's attributes
# Written by tools/forms.zap from translate/forms.zap, the forms the translation writes: do
# not edit. Each is the interpreter's function for one operation (execute.zap calls them).

import recomp.switch.arm64

# long: a dispatch over the attributes, each branch the operation's form
pub fn formAddImm(mut c Cpu, i arm64.Instr):
	if i.sf:
		if i.setFlags:
			if i.subtract:
				tr, tf = addWithCarry(c.x[i.rn], ~u64(i.imm), true, true)
				c.setNzcv(tf)
				c.x[i.rd] = tr
				c.x[31] = 0
			else:
				tr, tf = addWithCarry(c.x[i.rn], u64(i.imm), false, true)
				c.setNzcv(tf)
				c.x[i.rd] = tr
				c.x[31] = 0
		else:
			if i.subtract:
				c.x[i.rd] = c.x[i.rn] - u64(i.imm)
				c.x[31] = 0
			else:
				c.x[i.rd] = c.x[i.rn] + u64(i.imm)
				c.x[31] = 0
	else:
		if i.setFlags:
			if i.subtract:
				tr, tf = addWithCarry(c.x[i.rn] & 0xFFFF_FFFF, ~u64(i.imm), true, false)
				c.setNzcv(tf)
				c.x[i.rd] = (tr) & 0xFFFF_FFFF
				c.x[31] = 0
			else:
				tr, tf = addWithCarry(c.x[i.rn] & 0xFFFF_FFFF, u64(i.imm), false, false)
				c.setNzcv(tf)
				c.x[i.rd] = (tr) & 0xFFFF_FFFF
				c.x[31] = 0
		else:
			if i.subtract:
				c.x[i.rd] = ((c.x[i.rn] & 0xFFFF_FFFF) - u64(i.imm)) & 0xFFFF_FFFF
				c.x[31] = 0
			else:
				c.x[i.rd] = ((c.x[i.rn] & 0xFFFF_FFFF) + u64(i.imm)) & 0xFFFF_FFFF
				c.x[31] = 0

# long: a dispatch over the attributes, each branch the operation's form
pub fn formAddShifted(mut c Cpu, i arm64.Instr):
	if i.sf:
		if i.setFlags:
			if i.subtract:
				tr, tf = addWithCarry(
					c.x[i.rn],
					~shifted(c.x[i.rm], i.shift, i.amount, true),
					true,
					true
				)
				c.setNzcv(tf)
				c.x[i.rd] = tr
				c.x[31] = 0
			else:
				tr, tf = addWithCarry(
					c.x[i.rn],
					shifted(c.x[i.rm], i.shift, i.amount, true),
					false,
					true
				)
				c.setNzcv(tf)
				c.x[i.rd] = tr
				c.x[31] = 0
		else:
			if i.subtract:
				c.x[i.rd] = c.x[i.rn] - shifted(c.x[i.rm], i.shift, i.amount, true)
				c.x[31] = 0
			else:
				c.x[i.rd] = c.x[i.rn] + shifted(c.x[i.rm], i.shift, i.amount, true)
				c.x[31] = 0
	else:
		if i.setFlags:
			if i.subtract:
				tr, tf = addWithCarry(
					c.x[i.rn] & 0xFFFF_FFFF,
					~shifted(c.x[i.rm] & 0xFFFF_FFFF, i.shift, i.amount, false),
					true,
					false
				)
				c.setNzcv(tf)
				c.x[i.rd] = (tr) & 0xFFFF_FFFF
				c.x[31] = 0
			else:
				tr, tf = addWithCarry(
					c.x[i.rn] & 0xFFFF_FFFF,
					shifted(c.x[i.rm] & 0xFFFF_FFFF, i.shift, i.amount, false),
					false,
					false
				)
				c.setNzcv(tf)
				c.x[i.rd] = (tr) & 0xFFFF_FFFF
				c.x[31] = 0
		else:
			if i.subtract:
				c.x[i.rd] = (
					(c.x[i.rn] & 0xFFFF_FFFF) -
						shifted(c.x[i.rm] & 0xFFFF_FFFF, i.shift, i.amount, false)
				) & 0xFFFF_FFFF
				c.x[31] = 0
			else:
				c.x[i.rd] = (
					(c.x[i.rn] & 0xFFFF_FFFF) +
						shifted(c.x[i.rm] & 0xFFFF_FFFF, i.shift, i.amount, false)
				) & 0xFFFF_FFFF
				c.x[31] = 0

# long: a dispatch over the attributes, each branch the operation's form
pub fn formLogicImm(mut c Cpu, i arm64.Instr):
	if i.sf:
		match i.opc:
			0:
				c.x[i.rd] = c.x[i.rn] & u64(i.imm)
				c.x[31] = 0
			1:
				c.x[i.rd] = c.x[i.rn] | u64(i.imm)
				c.x[31] = 0
			2:
				c.x[i.rd] = c.x[i.rn] ^ u64(i.imm)
				c.x[31] = 0
			3:
				tr = (c.x[i.rn] & u64(i.imm)) & u64(-1)
				c.setNzcv(flagBit(isNegative(tr, true)) << 3 | flagBit(tr == 0) << 2)
				c.x[i.rd] = tr
				c.x[31] = 0
			_: pass
	else:
		match i.opc:
			0:
				c.x[i.rd] = ((c.x[i.rn] & 0xFFFF_FFFF) & u64(i.imm)) & 0xFFFF_FFFF
				c.x[31] = 0
			1:
				c.x[i.rd] = ((c.x[i.rn] & 0xFFFF_FFFF) | u64(i.imm)) & 0xFFFF_FFFF
				c.x[31] = 0
			2:
				c.x[i.rd] = ((c.x[i.rn] & 0xFFFF_FFFF) ^ u64(i.imm)) & 0xFFFF_FFFF
				c.x[31] = 0
			3:
				tr = ((c.x[i.rn] & 0xFFFF_FFFF) & u64(i.imm)) & u64(0xFFFF_FFFF)
				c.setNzcv(flagBit(isNegative(tr, false)) << 3 | flagBit(tr == 0) << 2)
				c.x[i.rd] = (tr) & 0xFFFF_FFFF
				c.x[31] = 0
			_: pass

# long: a dispatch over the attributes, each branch the operation's form
pub fn formLogicShifted(mut c Cpu, i arm64.Instr):
	if i.sf:
		match i.opc:
			0:
				if i.subtract:
					c.x[i.rd] = c.x[i.rn] & ~shifted(c.x[i.rm], i.shift, i.amount, true)
					c.x[31] = 0
				else:
					c.x[i.rd] = c.x[i.rn] & shifted(c.x[i.rm], i.shift, i.amount, true)
					c.x[31] = 0
			1:
				if i.subtract:
					c.x[i.rd] = c.x[i.rn] | ~shifted(c.x[i.rm], i.shift, i.amount, true)
					c.x[31] = 0
				else:
					c.x[i.rd] = c.x[i.rn] | shifted(c.x[i.rm], i.shift, i.amount, true)
					c.x[31] = 0
			2:
				if i.subtract:
					c.x[i.rd] = c.x[i.rn] ^ ~shifted(c.x[i.rm], i.shift, i.amount, true)
					c.x[31] = 0
				else:
					c.x[i.rd] = c.x[i.rn] ^ shifted(c.x[i.rm], i.shift, i.amount, true)
					c.x[31] = 0
			3:
				if i.subtract:
					tr = (c.x[i.rn] & ~shifted(c.x[i.rm], i.shift, i.amount, true)) & u64(-1)
					c.setNzcv(flagBit(isNegative(tr, true)) << 3 | flagBit(tr == 0) << 2)
					c.x[i.rd] = tr
					c.x[31] = 0
				else:
					tr = (c.x[i.rn] & shifted(c.x[i.rm], i.shift, i.amount, true)) & u64(-1)
					c.setNzcv(flagBit(isNegative(tr, true)) << 3 | flagBit(tr == 0) << 2)
					c.x[i.rd] = tr
					c.x[31] = 0
			_: pass
	else:
		match i.opc:
			0:
				if i.subtract:
					c.x[i.rd] = (
						(c.x[i.rn] & 0xFFFF_FFFF) & ~shifted(
							c.x[i.rm] & 0xFFFF_FFFF,
							i.shift,
							i.amount,
							false
						)
					) & 0xFFFF_FFFF
					c.x[31] = 0
				else:
					c.x[i.rd] = (
						(c.x[i.rn] & 0xFFFF_FFFF) & shifted(
							c.x[i.rm] & 0xFFFF_FFFF,
							i.shift,
							i.amount,
							false
						)
					) & 0xFFFF_FFFF
					c.x[31] = 0
			1:
				if i.subtract:
					c.x[i.rd] = (
						(c.x[i.rn] & 0xFFFF_FFFF) | ~shifted(
							c.x[i.rm] & 0xFFFF_FFFF,
							i.shift,
							i.amount,
							false
						)
					) & 0xFFFF_FFFF
					c.x[31] = 0
				else:
					c.x[i.rd] = (
						(c.x[i.rn] & 0xFFFF_FFFF) | shifted(
							c.x[i.rm] & 0xFFFF_FFFF,
							i.shift,
							i.amount,
							false
						)
					) & 0xFFFF_FFFF
					c.x[31] = 0
			2:
				if i.subtract:
					c.x[i.rd] = (
						(c.x[i.rn] & 0xFFFF_FFFF) ^ ~shifted(
							c.x[i.rm] & 0xFFFF_FFFF,
							i.shift,
							i.amount,
							false
						)
					) & 0xFFFF_FFFF
					c.x[31] = 0
				else:
					c.x[i.rd] = (
						(c.x[i.rn] & 0xFFFF_FFFF) ^ shifted(
							c.x[i.rm] & 0xFFFF_FFFF,
							i.shift,
							i.amount,
							false
						)
					) & 0xFFFF_FFFF
					c.x[31] = 0
			3:
				if i.subtract:
					tr = (
						(c.x[i.rn] & 0xFFFF_FFFF) & ~shifted(
							c.x[i.rm] & 0xFFFF_FFFF,
							i.shift,
							i.amount,
							false
						)
					) & u64(0xFFFF_FFFF)
					c.setNzcv(flagBit(isNegative(tr, false)) << 3 | flagBit(tr == 0) << 2)
					c.x[i.rd] = (tr) & 0xFFFF_FFFF
					c.x[31] = 0
				else:
					tr = (
						(c.x[i.rn] & 0xFFFF_FFFF) & shifted(
							c.x[i.rm] & 0xFFFF_FFFF,
							i.shift,
							i.amount,
							false
						)
					) & u64(0xFFFF_FFFF)
					c.setNzcv(flagBit(isNegative(tr, false)) << 3 | flagBit(tr == 0) << 2)
					c.x[i.rd] = (tr) & 0xFFFF_FFFF
					c.x[31] = 0
			_: pass

# long: a dispatch over the attributes, each branch the operation's form
pub fn formLoad(mut c Cpu, i arm64.Instr):
	if i.vector:
		if i.signed:
			if i.sf:
				match i.mode:
					Offset:
						c.loadVector(i.rd, i64(c.x[i.rn]) + i.imm, i.size)
					PreIndex:
						ta = i64(c.x[i.rn]) + i.imm
						c.x[i.rn] = u64(ta)
						c.loadVector(i.rd, ta, i.size)
					PostIndex:
						ta = i64(c.x[i.rn])
						c.x[i.rn] = u64(ta + i.imm)
						c.loadVector(i.rd, ta, i.size)
					RegisterOffset:
						c.loadVector(
							i.rd,
							i64(c.x[i.rn]) + i64(extended(c.x[i.rm], i.shift, i.amount, true)),
							i.size
						)
			else:
				match i.mode:
					Offset:
						c.loadVector(i.rd, i64(c.x[i.rn]) + i.imm, i.size)
					PreIndex:
						ta = i64(c.x[i.rn]) + i.imm
						c.x[i.rn] = u64(ta)
						c.loadVector(i.rd, ta, i.size)
					PostIndex:
						ta = i64(c.x[i.rn])
						c.x[i.rn] = u64(ta + i.imm)
						c.loadVector(i.rd, ta, i.size)
					RegisterOffset:
						c.loadVector(
							i.rd,
							i64(c.x[i.rn]) + i64(extended(c.x[i.rm], i.shift, i.amount, true)),
							i.size
						)
		else:
			if i.sf:
				match i.mode:
					Offset:
						c.loadVector(i.rd, i64(c.x[i.rn]) + i.imm, i.size)
					PreIndex:
						ta = i64(c.x[i.rn]) + i.imm
						c.x[i.rn] = u64(ta)
						c.loadVector(i.rd, ta, i.size)
					PostIndex:
						ta = i64(c.x[i.rn])
						c.x[i.rn] = u64(ta + i.imm)
						c.loadVector(i.rd, ta, i.size)
					RegisterOffset:
						c.loadVector(
							i.rd,
							i64(c.x[i.rn]) + i64(extended(c.x[i.rm], i.shift, i.amount, true)),
							i.size
						)
			else:
				match i.mode:
					Offset:
						c.loadVector(i.rd, i64(c.x[i.rn]) + i.imm, i.size)
					PreIndex:
						ta = i64(c.x[i.rn]) + i.imm
						c.x[i.rn] = u64(ta)
						c.loadVector(i.rd, ta, i.size)
					PostIndex:
						ta = i64(c.x[i.rn])
						c.x[i.rn] = u64(ta + i.imm)
						c.loadVector(i.rd, ta, i.size)
					RegisterOffset:
						c.loadVector(
							i.rd,
							i64(c.x[i.rn]) + i64(extended(c.x[i.rm], i.shift, i.amount, true)),
							i.size
						)
	else:
		if i.signed:
			if i.sf:
				match i.mode:
					Offset:
						c.x[i.rd] = signExtend(
							memory.load(i64(c.x[i.rn]) + i.imm, i.size),
							i.size,
							true
						)
						c.x[31] = 0
					PreIndex:
						ta = i64(c.x[i.rn]) + i.imm
						c.x[i.rn] = u64(ta)
						c.x[i.rd] = signExtend(memory.load(ta, i.size), i.size, true)
						c.x[31] = 0
					PostIndex:
						ta = i64(c.x[i.rn])
						c.x[i.rn] = u64(ta + i.imm)
						c.x[i.rd] = signExtend(memory.load(ta, i.size), i.size, true)
						c.x[31] = 0
					RegisterOffset:
						c.x[i.rd] = signExtend(
							memory.load(i64(c.x[i.rn]) + i64(extended(c.x[i.rm], i.shift, i.amount, true)), i.size),
							i.size,
							true
						)
						c.x[31] = 0
			else:
				match i.mode:
					Offset:
						c.x[i.rd] = signExtend(
							memory.load(i64(c.x[i.rn]) + i.imm, i.size),
							i.size,
							false
						)
						c.x[31] = 0
					PreIndex:
						ta = i64(c.x[i.rn]) + i.imm
						c.x[i.rn] = u64(ta)
						c.x[i.rd] = signExtend(memory.load(ta, i.size), i.size, false)
						c.x[31] = 0
					PostIndex:
						ta = i64(c.x[i.rn])
						c.x[i.rn] = u64(ta + i.imm)
						c.x[i.rd] = signExtend(memory.load(ta, i.size), i.size, false)
						c.x[31] = 0
					RegisterOffset:
						c.x[i.rd] = signExtend(
							memory.load(i64(c.x[i.rn]) + i64(extended(c.x[i.rm], i.shift, i.amount, true)), i.size),
							i.size,
							false
						)
						c.x[31] = 0
		else:
			if i.sf:
				match i.mode:
					Offset:
						c.x[i.rd] = memory.load(i64(c.x[i.rn]) + i.imm, i.size)
						c.x[31] = 0
					PreIndex:
						ta = i64(c.x[i.rn]) + i.imm
						c.x[i.rn] = u64(ta)
						c.x[i.rd] = memory.load(ta, i.size)
						c.x[31] = 0
					PostIndex:
						ta = i64(c.x[i.rn])
						c.x[i.rn] = u64(ta + i.imm)
						c.x[i.rd] = memory.load(ta, i.size)
						c.x[31] = 0
					RegisterOffset:
						c.x[i.rd] = memory.load(
							i64(c.x[i.rn]) + i64(extended(c.x[i.rm], i.shift, i.amount, true)),
							i.size
						)
						c.x[31] = 0
			else:
				match i.mode:
					Offset:
						c.x[i.rd] = memory.load(i64(c.x[i.rn]) + i.imm, i.size)
						c.x[31] = 0
					PreIndex:
						ta = i64(c.x[i.rn]) + i.imm
						c.x[i.rn] = u64(ta)
						c.x[i.rd] = memory.load(ta, i.size)
						c.x[31] = 0
					PostIndex:
						ta = i64(c.x[i.rn])
						c.x[i.rn] = u64(ta + i.imm)
						c.x[i.rd] = memory.load(ta, i.size)
						c.x[31] = 0
					RegisterOffset:
						c.x[i.rd] = memory.load(
							i64(c.x[i.rn]) + i64(extended(c.x[i.rm], i.shift, i.amount, true)),
							i.size
						)
						c.x[31] = 0

# long: a dispatch over the attributes, each branch the operation's form
pub fn formStore(mut c Cpu, i arm64.Instr):
	if i.vector:
		match i.mode:
			Offset:
				c.storeVector(i.rd, i64(c.x[i.rn]) + i.imm, i.size)
			PreIndex:
				ta = i64(c.x[i.rn]) + i.imm
				c.x[i.rn] = u64(ta)
				c.storeVector(i.rd, ta, i.size)
			PostIndex:
				ta = i64(c.x[i.rn])
				c.x[i.rn] = u64(ta + i.imm)
				c.storeVector(i.rd, ta, i.size)
			RegisterOffset:
				c.storeVector(
					i.rd,
					i64(c.x[i.rn]) + i64(extended(c.x[i.rm], i.shift, i.amount, true)),
					i.size
				)
	else:
		match i.mode:
			Offset:
				tv = c.x[i.rd]
				memory.store(i64(c.x[i.rn]) + i.imm, i.size, tv)
			PreIndex:
				tv = c.x[i.rd]
				ta = i64(c.x[i.rn]) + i.imm
				c.x[i.rn] = u64(ta)
				memory.store(ta, i.size, tv)
			PostIndex:
				tv = c.x[i.rd]
				ta = i64(c.x[i.rn])
				c.x[i.rn] = u64(ta + i.imm)
				memory.store(ta, i.size, tv)
			RegisterOffset:
				tv = c.x[i.rd]
				memory.store(
					i64(c.x[i.rn]) + i64(extended(c.x[i.rm], i.shift, i.amount, true)),
					i.size,
					tv
				)

# long: a dispatch over the attributes, each branch the operation's form
pub fn formLoadPair(mut c Cpu, i arm64.Instr):
	if i.vector:
		if i.signed:
			match i.mode:
				Offset:
					c.loadVector(i.rd, i64(c.x[i.rn]) + i.imm, i.size)
					c.loadVector(i.ra, i64(c.x[i.rn]) + i.imm + (1 << i.size), i.size)
				PreIndex:
					ta = i64(c.x[i.rn]) + i.imm
					c.x[i.rn] = u64(ta)
					c.loadVector(i.rd, ta, i.size)
					c.loadVector(i.ra, ta + (1 << i.size), i.size)
				PostIndex:
					ta = i64(c.x[i.rn])
					c.x[i.rn] = u64(ta + i.imm)
					c.loadVector(i.rd, ta, i.size)
					c.loadVector(i.ra, ta + (1 << i.size), i.size)
				_: pass
		else:
			match i.mode:
				Offset:
					c.loadVector(i.rd, i64(c.x[i.rn]) + i.imm, i.size)
					c.loadVector(i.ra, i64(c.x[i.rn]) + i.imm + (1 << i.size), i.size)
				PreIndex:
					ta = i64(c.x[i.rn]) + i.imm
					c.x[i.rn] = u64(ta)
					c.loadVector(i.rd, ta, i.size)
					c.loadVector(i.ra, ta + (1 << i.size), i.size)
				PostIndex:
					ta = i64(c.x[i.rn])
					c.x[i.rn] = u64(ta + i.imm)
					c.loadVector(i.rd, ta, i.size)
					c.loadVector(i.ra, ta + (1 << i.size), i.size)
				_: pass
	else:
		if i.signed:
			match i.mode:
				Offset:
					tv = signExtend(memory.load(i64(c.x[i.rn]) + i.imm, i.size), i.size, true)
					tw = signExtend(
						memory.load(i64(c.x[i.rn]) + i.imm + (1 << i.size), i.size),
						i.size,
						true
					)
					c.x[i.rd] = tv
					c.x[31] = 0
					c.x[i.ra] = tw
					c.x[31] = 0
				PreIndex:
					ta = i64(c.x[i.rn]) + i.imm
					c.x[i.rn] = u64(ta)
					tv = signExtend(memory.load(ta, i.size), i.size, true)
					tw = signExtend(memory.load(ta + (1 << i.size), i.size), i.size, true)
					c.x[i.rd] = tv
					c.x[31] = 0
					c.x[i.ra] = tw
					c.x[31] = 0
				PostIndex:
					ta = i64(c.x[i.rn])
					c.x[i.rn] = u64(ta + i.imm)
					tv = signExtend(memory.load(ta, i.size), i.size, true)
					tw = signExtend(memory.load(ta + (1 << i.size), i.size), i.size, true)
					c.x[i.rd] = tv
					c.x[31] = 0
					c.x[i.ra] = tw
					c.x[31] = 0
				_: pass
		else:
			match i.mode:
				Offset:
					tv = memory.load(i64(c.x[i.rn]) + i.imm, i.size)
					tw = memory.load(i64(c.x[i.rn]) + i.imm + (1 << i.size), i.size)
					c.x[i.rd] = tv
					c.x[31] = 0
					c.x[i.ra] = tw
					c.x[31] = 0
				PreIndex:
					ta = i64(c.x[i.rn]) + i.imm
					c.x[i.rn] = u64(ta)
					tv = memory.load(ta, i.size)
					tw = memory.load(ta + (1 << i.size), i.size)
					c.x[i.rd] = tv
					c.x[31] = 0
					c.x[i.ra] = tw
					c.x[31] = 0
				PostIndex:
					ta = i64(c.x[i.rn])
					c.x[i.rn] = u64(ta + i.imm)
					tv = memory.load(ta, i.size)
					tw = memory.load(ta + (1 << i.size), i.size)
					c.x[i.rd] = tv
					c.x[31] = 0
					c.x[i.ra] = tw
					c.x[31] = 0
				_: pass

# long: a dispatch over the attributes, each branch the operation's form
pub fn formStorePair(mut c Cpu, i arm64.Instr):
	if i.vector:
		match i.mode:
			Offset:
				c.storeVector(i.rd, i64(c.x[i.rn]) + i.imm, i.size)
				c.storeVector(i.ra, i64(c.x[i.rn]) + i.imm + (1 << i.size), i.size)
			PreIndex:
				ta = i64(c.x[i.rn]) + i.imm
				c.x[i.rn] = u64(ta)
				c.storeVector(i.rd, ta, i.size)
				c.storeVector(i.ra, ta + (1 << i.size), i.size)
			PostIndex:
				ta = i64(c.x[i.rn])
				c.x[i.rn] = u64(ta + i.imm)
				c.storeVector(i.rd, ta, i.size)
				c.storeVector(i.ra, ta + (1 << i.size), i.size)
			_: pass
	else:
		match i.mode:
			Offset:
				tv = c.x[i.rd]
				tw = c.x[i.ra]
				memory.store(i64(c.x[i.rn]) + i.imm, i.size, tv)
				memory.store(i64(c.x[i.rn]) + i.imm + (1 << i.size), i.size, tw)
			PreIndex:
				tv = c.x[i.rd]
				tw = c.x[i.ra]
				ta = i64(c.x[i.rn]) + i.imm
				c.x[i.rn] = u64(ta)
				memory.store(ta, i.size, tv)
				memory.store(ta + (1 << i.size), i.size, tw)
			PostIndex:
				tv = c.x[i.rd]
				tw = c.x[i.ra]
				ta = i64(c.x[i.rn])
				c.x[i.rn] = u64(ta + i.imm)
				memory.store(ta, i.size, tv)
				memory.store(ta + (1 << i.size), i.size, tw)
			_: pass

# long: a dispatch over the attributes, each branch the operation's form
pub fn formMoveWide(mut c Cpu, i arm64.Instr):
	if i.sf:
		match i.opc:
			0:
				c.x[i.rd] = ~(u64(i.imm) << i.shift)
				c.x[31] = 0
			2:
				c.x[i.rd] = u64(i.imm) << i.shift
				c.x[31] = 0
			3:
				c.x[i.rd] = (c.x[i.rd] & ~(u64(0xFFFF) << i.shift)) | (u64(i.imm) << i.shift)
				c.x[31] = 0
			_: pass
	else:
		match i.opc:
			0:
				c.x[i.rd] = (~(u64(i.imm) << i.shift)) & 0xFFFF_FFFF
				c.x[31] = 0
			2:
				c.x[i.rd] = (u64(i.imm) << i.shift) & 0xFFFF_FFFF
				c.x[31] = 0
			3:
				c.x[i.rd] = (
					(c.x[i.rd] & ~(u64(0xFFFF) << i.shift)) | (u64(i.imm) << i.shift)
				) & 0xFFFF_FFFF
				c.x[31] = 0
			_: pass

# long: a dispatch over the attributes, each branch the operation's form
pub fn formAdr(mut c Cpu, i arm64.Instr):
	c.x[i.rd] = u64(i.imm)
	c.x[31] = 0

# long: a dispatch over the attributes, each branch the operation's form
pub fn formCondSelect(mut c Cpu, i arm64.Instr):
	if i.sf:
		match i.opc:
			0:
				if c.holds(i.cond):
					c.x[i.rd] = c.x[i.rn]
					c.x[31] = 0
				else:
					c.x[i.rd] = c.x[i.rm]
					c.x[31] = 0
			1:
				if c.holds(i.cond):
					c.x[i.rd] = c.x[i.rn]
					c.x[31] = 0
				else:
					c.x[i.rd] = c.x[i.rm] + 1
					c.x[31] = 0
			2:
				if c.holds(i.cond):
					c.x[i.rd] = c.x[i.rn]
					c.x[31] = 0
				else:
					c.x[i.rd] = ~c.x[i.rm]
					c.x[31] = 0
			3:
				if c.holds(i.cond):
					c.x[i.rd] = c.x[i.rn]
					c.x[31] = 0
				else:
					c.x[i.rd] = 0 - c.x[i.rm]
					c.x[31] = 0
			_: pass
	else:
		match i.opc:
			0:
				if c.holds(i.cond):
					c.x[i.rd] = (c.x[i.rn] & 0xFFFF_FFFF) & 0xFFFF_FFFF
					c.x[31] = 0
				else:
					c.x[i.rd] = (c.x[i.rm] & 0xFFFF_FFFF) & 0xFFFF_FFFF
					c.x[31] = 0
			1:
				if c.holds(i.cond):
					c.x[i.rd] = (c.x[i.rn] & 0xFFFF_FFFF) & 0xFFFF_FFFF
					c.x[31] = 0
				else:
					c.x[i.rd] = ((c.x[i.rm] & 0xFFFF_FFFF) + 1) & 0xFFFF_FFFF
					c.x[31] = 0
			2:
				if c.holds(i.cond):
					c.x[i.rd] = (c.x[i.rn] & 0xFFFF_FFFF) & 0xFFFF_FFFF
					c.x[31] = 0
				else:
					c.x[i.rd] = (~(c.x[i.rm] & 0xFFFF_FFFF)) & 0xFFFF_FFFF
					c.x[31] = 0
			3:
				if c.holds(i.cond):
					c.x[i.rd] = (c.x[i.rn] & 0xFFFF_FFFF) & 0xFFFF_FFFF
					c.x[31] = 0
				else:
					c.x[i.rd] = (0 - (c.x[i.rm] & 0xFFFF_FFFF)) & 0xFFFF_FFFF
					c.x[31] = 0
			_: pass

# long: a dispatch over the attributes, each branch the operation's form
pub fn formBranchCond(mut c Cpu, i arm64.Instr):
	if c.holds(i.cond):
		c.pc = i.imm

# long: a dispatch over the attributes, each branch the operation's form
pub fn formAddExtended(mut c Cpu, i arm64.Instr):
	if i.sf:
		if i.setFlags:
			if i.subtract:
				tr, tf = addWithCarry(
					c.x[i.rn],
					~extended(c.x[i.rm], i.shift, i.amount, true),
					true,
					true
				)
				c.setNzcv(tf)
				c.x[i.rd] = tr
				c.x[31] = 0
			else:
				tr, tf = addWithCarry(
					c.x[i.rn],
					extended(c.x[i.rm], i.shift, i.amount, true),
					false,
					true
				)
				c.setNzcv(tf)
				c.x[i.rd] = tr
				c.x[31] = 0
		else:
			if i.subtract:
				c.x[i.rd] = c.x[i.rn] - extended(c.x[i.rm], i.shift, i.amount, true)
				c.x[31] = 0
			else:
				c.x[i.rd] = c.x[i.rn] + extended(c.x[i.rm], i.shift, i.amount, true)
				c.x[31] = 0
	else:
		if i.setFlags:
			if i.subtract:
				tr, tf = addWithCarry(
					c.x[i.rn] & 0xFFFF_FFFF,
					~extended(c.x[i.rm], i.shift, i.amount, false),
					true,
					false
				)
				c.setNzcv(tf)
				c.x[i.rd] = (tr) & 0xFFFF_FFFF
				c.x[31] = 0
			else:
				tr, tf = addWithCarry(
					c.x[i.rn] & 0xFFFF_FFFF,
					extended(c.x[i.rm], i.shift, i.amount, false),
					false,
					false
				)
				c.setNzcv(tf)
				c.x[i.rd] = (tr) & 0xFFFF_FFFF
				c.x[31] = 0
		else:
			if i.subtract:
				c.x[i.rd] = (
					(c.x[i.rn] & 0xFFFF_FFFF) - extended(c.x[i.rm], i.shift, i.amount, false)
				) & 0xFFFF_FFFF
				c.x[31] = 0
			else:
				c.x[i.rd] = (
					(c.x[i.rn] & 0xFFFF_FFFF) + extended(c.x[i.rm], i.shift, i.amount, false)
				) & 0xFFFF_FFFF
				c.x[31] = 0

# long: a dispatch over the attributes, each branch the operation's form
pub fn formAddCarry(mut c Cpu, i arm64.Instr):
	if i.sf:
		if i.setFlags:
			if i.subtract:
				tr, tf = addWithCarry(c.x[i.rn], ~c.x[i.rm], c.flagC, true)
				c.setNzcv(tf)
				c.x[i.rd] = tr
				c.x[31] = 0
			else:
				tr, tf = addWithCarry(c.x[i.rn], c.x[i.rm], c.flagC, true)
				c.setNzcv(tf)
				c.x[i.rd] = tr
				c.x[31] = 0
		else:
			if i.subtract:
				tr, _ = addWithCarry(c.x[i.rn], ~c.x[i.rm], c.flagC, true)
				c.x[i.rd] = tr
				c.x[31] = 0
			else:
				tr, _ = addWithCarry(c.x[i.rn], c.x[i.rm], c.flagC, true)
				c.x[i.rd] = tr
				c.x[31] = 0
	else:
		if i.setFlags:
			if i.subtract:
				tr, tf = addWithCarry(
					c.x[i.rn] & 0xFFFF_FFFF,
					~(c.x[i.rm] & 0xFFFF_FFFF),
					c.flagC,
					false
				)
				c.setNzcv(tf)
				c.x[i.rd] = (tr) & 0xFFFF_FFFF
				c.x[31] = 0
			else:
				tr, tf = addWithCarry(
					c.x[i.rn] & 0xFFFF_FFFF,
					c.x[i.rm] & 0xFFFF_FFFF,
					c.flagC,
					false
				)
				c.setNzcv(tf)
				c.x[i.rd] = (tr) & 0xFFFF_FFFF
				c.x[31] = 0
		else:
			if i.subtract:
				tr, _ = addWithCarry(
					c.x[i.rn] & 0xFFFF_FFFF,
					~(c.x[i.rm] & 0xFFFF_FFFF),
					c.flagC,
					false
				)
				c.x[i.rd] = (tr) & 0xFFFF_FFFF
				c.x[31] = 0
			else:
				tr, _ = addWithCarry(
					c.x[i.rn] & 0xFFFF_FFFF,
					c.x[i.rm] & 0xFFFF_FFFF,
					c.flagC,
					false
				)
				c.x[i.rd] = (tr) & 0xFFFF_FFFF
				c.x[31] = 0

# long: a dispatch over the attributes, each branch the operation's form
pub fn formBitfield(mut c Cpu, i arm64.Instr):
	if i.sf:
		match i.opc:
			0:
				tw, tm = bitfieldMasks(i.imm, i.imm2, true)
				c.x[i.rd] = bitfieldOf(c.x[i.rn], 0, i.imm, i.imm2, tw, tm, 0, true)
				c.x[31] = 0
			1:
				tw, tm = bitfieldMasks(i.imm, i.imm2, true)
				c.x[i.rd] = bitfieldOf(c.x[i.rn], c.x[i.rd], i.imm, i.imm2, tw, tm, 1, true)
				c.x[31] = 0
			2:
				tw, tm = bitfieldMasks(i.imm, i.imm2, true)
				c.x[i.rd] = bitfieldOf(c.x[i.rn], 0, i.imm, i.imm2, tw, tm, 2, true)
				c.x[31] = 0
			_: pass
	else:
		match i.opc:
			0:
				tw, tm = bitfieldMasks(i.imm, i.imm2, false)
				c.x[i.rd] = (
					bitfieldOf(c.x[i.rn] & 0xFFFF_FFFF, 0, i.imm, i.imm2, tw, tm, 0, false)
				) & 0xFFFF_FFFF
				c.x[31] = 0
			1:
				tw, tm = bitfieldMasks(i.imm, i.imm2, false)
				c.x[i.rd] = (
					bitfieldOf(
						c.x[i.rn] & 0xFFFF_FFFF,
						c.x[i.rd] & 0xFFFF_FFFF,
						i.imm,
						i.imm2,
						tw,
						tm,
						1,
						false
					)
				) & 0xFFFF_FFFF
				c.x[31] = 0
			2:
				tw, tm = bitfieldMasks(i.imm, i.imm2, false)
				c.x[i.rd] = (
					bitfieldOf(c.x[i.rn] & 0xFFFF_FFFF, 0, i.imm, i.imm2, tw, tm, 2, false)
				) & 0xFFFF_FFFF
				c.x[31] = 0
			_: pass

# long: a dispatch over the attributes, each branch the operation's form
pub fn formExtract(mut c Cpu, i arm64.Instr):
	if i.sf:
		c.x[i.rd] = extractOf(c.x[i.rm], c.x[i.rn], i.imm, true)
		c.x[31] = 0
	else:
		c.x[i.rd] = (
			extractOf(c.x[i.rm] & 0xFFFF_FFFF, c.x[i.rn] & 0xFFFF_FFFF, i.imm, false)
		) & 0xFFFF_FFFF
		c.x[31] = 0

# long: a dispatch over the attributes, each branch the operation's form
pub fn formCondCompare(mut c Cpu, i arm64.Instr):
	if i.sf:
		if i.subtract:
			if i.pair:
				if c.holds(i.cond):
					_, tf = addWithCarry(c.x[i.rn], ~u64(i.rm), true, true)
					c.setNzcv(tf)
				else:
					c.setNzcv(u64(i.imm))
			else:
				if c.holds(i.cond):
					_, tf = addWithCarry(c.x[i.rn], ~c.x[i.rm], true, true)
					c.setNzcv(tf)
				else:
					c.setNzcv(u64(i.imm))
		else:
			if i.pair:
				if c.holds(i.cond):
					_, tf = addWithCarry(c.x[i.rn], u64(i.rm), false, true)
					c.setNzcv(tf)
				else:
					c.setNzcv(u64(i.imm))
			else:
				if c.holds(i.cond):
					_, tf = addWithCarry(c.x[i.rn], c.x[i.rm], false, true)
					c.setNzcv(tf)
				else:
					c.setNzcv(u64(i.imm))
	else:
		if i.subtract:
			if i.pair:
				if c.holds(i.cond):
					_, tf = addWithCarry(c.x[i.rn] & 0xFFFF_FFFF, ~u64(i.rm), true, false)
					c.setNzcv(tf)
				else:
					c.setNzcv(u64(i.imm))
			else:
				if c.holds(i.cond):
					_, tf = addWithCarry(
						c.x[i.rn] & 0xFFFF_FFFF,
						~(c.x[i.rm] & 0xFFFF_FFFF),
						true,
						false
					)
					c.setNzcv(tf)
				else:
					c.setNzcv(u64(i.imm))
		else:
			if i.pair:
				if c.holds(i.cond):
					_, tf = addWithCarry(c.x[i.rn] & 0xFFFF_FFFF, u64(i.rm), false, false)
					c.setNzcv(tf)
				else:
					c.setNzcv(u64(i.imm))
			else:
				if c.holds(i.cond):
					_, tf = addWithCarry(
						c.x[i.rn] & 0xFFFF_FFFF,
						c.x[i.rm] & 0xFFFF_FFFF,
						false,
						false
					)
					c.setNzcv(tf)
				else:
					c.setNzcv(u64(i.imm))

# long: a dispatch over the attributes, each branch the operation's form
pub fn formThreeSource(mut c Cpu, i arm64.Instr):
	if i.sf:
		match i.opc:
			0:
				c.x[i.rd] = c.x[i.ra] + c.x[i.rn] * c.x[i.rm]
				c.x[31] = 0
			1:
				c.x[i.rd] = c.x[i.ra] - c.x[i.rn] * c.x[i.rm]
				c.x[31] = 0
			2:
				c.x[i.rd] = c.x[i.ra] + mulSignedWords(c.x[i.rn], c.x[i.rm])
				c.x[31] = 0
			3:
				c.x[i.rd] = c.x[i.ra] - mulSignedWords(c.x[i.rn], c.x[i.rm])
				c.x[31] = 0
			4:
				c.x[i.rd] = mulHighSigned(c.x[i.rn], c.x[i.rm])
				c.x[31] = 0
			10:
				c.x[i.rd] = c.x[i.ra] + (c.x[i.rn] & 0xFFFF_FFFF) * (c.x[i.rm] & 0xFFFF_FFFF)
				c.x[31] = 0
			11:
				c.x[i.rd] = c.x[i.ra] - (c.x[i.rn] & 0xFFFF_FFFF) * (c.x[i.rm] & 0xFFFF_FFFF)
				c.x[31] = 0
			12:
				c.x[i.rd] = mulHigh(c.x[i.rn], c.x[i.rm])
				c.x[31] = 0
			_: pass
	else:
		match i.opc:
			0:
				c.x[i.rd] = (c.x[i.ra] + c.x[i.rn] * c.x[i.rm]) & 0xFFFF_FFFF
				c.x[31] = 0
			1:
				c.x[i.rd] = (c.x[i.ra] - c.x[i.rn] * c.x[i.rm]) & 0xFFFF_FFFF
				c.x[31] = 0
			2:
				c.x[i.rd] = c.x[i.ra] + mulSignedWords(c.x[i.rn], c.x[i.rm])
				c.x[31] = 0
			3:
				c.x[i.rd] = c.x[i.ra] - mulSignedWords(c.x[i.rn], c.x[i.rm])
				c.x[31] = 0
			4:
				c.x[i.rd] = mulHighSigned(c.x[i.rn], c.x[i.rm])
				c.x[31] = 0
			10:
				c.x[i.rd] = c.x[i.ra] + (c.x[i.rn] & 0xFFFF_FFFF) * (c.x[i.rm] & 0xFFFF_FFFF)
				c.x[31] = 0
			11:
				c.x[i.rd] = c.x[i.ra] - (c.x[i.rn] & 0xFFFF_FFFF) * (c.x[i.rm] & 0xFFFF_FFFF)
				c.x[31] = 0
			12:
				c.x[i.rd] = mulHigh(c.x[i.rn], c.x[i.rm])
				c.x[31] = 0
			_: pass

# long: a dispatch over the attributes, each branch the operation's form
pub fn formCompareBranch(mut c Cpu, i arm64.Instr):
	if i.sf:
		match i.opc:
			0:
				if c.x[i.rd] == 0:
					c.pc = i.imm
			1:
				if c.x[i.rd] != 0:
					c.pc = i.imm
			_: pass
	else:
		match i.opc:
			0:
				if (c.x[i.rd] & 0xFFFF_FFFF) == 0:
					c.pc = i.imm
			1:
				if (c.x[i.rd] & 0xFFFF_FFFF) != 0:
					c.pc = i.imm
			_: pass

# long: a dispatch over the attributes, each branch the operation's form
pub fn formTestBranch(mut c Cpu, i arm64.Instr):
	match i.opc:
		0:
			if (c.x[i.rd] >> i.imm2) & 1 == 0:
				c.pc = i.imm
		1:
			if (c.x[i.rd] >> i.imm2) & 1 != 0:
				c.pc = i.imm
		_: pass

# long: a dispatch over the attributes, each branch the operation's form
pub fn formFloat(mut c Cpu, i arm64.Instr):
	match i.fop:
		Move:
			if i.setFlags:
				if i.pair:
					if i.sf:
						if i.signed:
							c.writeFp(i.rd, c.readFp(i.rn, fmtOf(i.size)))
						else:
							c.writeFp(i.rd, c.readFp(i.rn, fmtOf(i.size)))
					else:
						if i.signed:
							c.writeFp(i.rd, c.readFp(i.rn, fmtOf(i.size)))
						else:
							c.writeFp(i.rd, c.readFp(i.rn, fmtOf(i.size)))
				else:
					if i.sf:
						if i.signed:
							c.writeFp(i.rd, c.readFp(i.rn, fmtOf(i.size)))
						else:
							c.writeFp(i.rd, c.readFp(i.rn, fmtOf(i.size)))
					else:
						if i.signed:
							c.writeFp(i.rd, c.readFp(i.rn, fmtOf(i.size)))
						else:
							c.writeFp(i.rd, c.readFp(i.rn, fmtOf(i.size)))
			else:
				if i.pair:
					if i.sf:
						if i.signed:
							c.writeFp(i.rd, c.readFp(i.rn, fmtOf(i.size)))
						else:
							c.writeFp(i.rd, c.readFp(i.rn, fmtOf(i.size)))
					else:
						if i.signed:
							c.writeFp(i.rd, c.readFp(i.rn, fmtOf(i.size)))
						else:
							c.writeFp(i.rd, c.readFp(i.rn, fmtOf(i.size)))
				else:
					if i.sf:
						if i.signed:
							c.writeFp(i.rd, c.readFp(i.rn, fmtOf(i.size)))
						else:
							c.writeFp(i.rd, c.readFp(i.rn, fmtOf(i.size)))
					else:
						if i.signed:
							c.writeFp(i.rd, c.readFp(i.rn, fmtOf(i.size)))
						else:
							c.writeFp(i.rd, c.readFp(i.rn, fmtOf(i.size)))
		Abs:
			if i.setFlags:
				if i.pair:
					if i.sf:
						if i.signed:
							c.writeFp(
								i.rd,
								c.readFp(i.rn, fmtOf(i.size)) & ~fmtOf(i.size).signBit()
							)
						else:
							c.writeFp(
								i.rd,
								c.readFp(i.rn, fmtOf(i.size)) & ~fmtOf(i.size).signBit()
							)
					else:
						if i.signed:
							c.writeFp(
								i.rd,
								c.readFp(i.rn, fmtOf(i.size)) & ~fmtOf(i.size).signBit()
							)
						else:
							c.writeFp(
								i.rd,
								c.readFp(i.rn, fmtOf(i.size)) & ~fmtOf(i.size).signBit()
							)
				else:
					if i.sf:
						if i.signed:
							c.writeFp(
								i.rd,
								c.readFp(i.rn, fmtOf(i.size)) & ~fmtOf(i.size).signBit()
							)
						else:
							c.writeFp(
								i.rd,
								c.readFp(i.rn, fmtOf(i.size)) & ~fmtOf(i.size).signBit()
							)
					else:
						if i.signed:
							c.writeFp(
								i.rd,
								c.readFp(i.rn, fmtOf(i.size)) & ~fmtOf(i.size).signBit()
							)
						else:
							c.writeFp(
								i.rd,
								c.readFp(i.rn, fmtOf(i.size)) & ~fmtOf(i.size).signBit()
							)
			else:
				if i.pair:
					if i.sf:
						if i.signed:
							c.writeFp(
								i.rd,
								c.readFp(i.rn, fmtOf(i.size)) & ~fmtOf(i.size).signBit()
							)
						else:
							c.writeFp(
								i.rd,
								c.readFp(i.rn, fmtOf(i.size)) & ~fmtOf(i.size).signBit()
							)
					else:
						if i.signed:
							c.writeFp(
								i.rd,
								c.readFp(i.rn, fmtOf(i.size)) & ~fmtOf(i.size).signBit()
							)
						else:
							c.writeFp(
								i.rd,
								c.readFp(i.rn, fmtOf(i.size)) & ~fmtOf(i.size).signBit()
							)
				else:
					if i.sf:
						if i.signed:
							c.writeFp(
								i.rd,
								c.readFp(i.rn, fmtOf(i.size)) & ~fmtOf(i.size).signBit()
							)
						else:
							c.writeFp(
								i.rd,
								c.readFp(i.rn, fmtOf(i.size)) & ~fmtOf(i.size).signBit()
							)
					else:
						if i.signed:
							c.writeFp(
								i.rd,
								c.readFp(i.rn, fmtOf(i.size)) & ~fmtOf(i.size).signBit()
							)
						else:
							c.writeFp(
								i.rd,
								c.readFp(i.rn, fmtOf(i.size)) & ~fmtOf(i.size).signBit()
							)
		Neg:
			if i.setFlags:
				if i.pair:
					if i.sf:
						if i.signed:
							c.writeFp(i.rd, c.readFp(i.rn, fmtOf(i.size)) ^ fmtOf(i.size).signBit())
						else:
							c.writeFp(i.rd, c.readFp(i.rn, fmtOf(i.size)) ^ fmtOf(i.size).signBit())
					else:
						if i.signed:
							c.writeFp(i.rd, c.readFp(i.rn, fmtOf(i.size)) ^ fmtOf(i.size).signBit())
						else:
							c.writeFp(i.rd, c.readFp(i.rn, fmtOf(i.size)) ^ fmtOf(i.size).signBit())
				else:
					if i.sf:
						if i.signed:
							c.writeFp(i.rd, c.readFp(i.rn, fmtOf(i.size)) ^ fmtOf(i.size).signBit())
						else:
							c.writeFp(i.rd, c.readFp(i.rn, fmtOf(i.size)) ^ fmtOf(i.size).signBit())
					else:
						if i.signed:
							c.writeFp(i.rd, c.readFp(i.rn, fmtOf(i.size)) ^ fmtOf(i.size).signBit())
						else:
							c.writeFp(i.rd, c.readFp(i.rn, fmtOf(i.size)) ^ fmtOf(i.size).signBit())
			else:
				if i.pair:
					if i.sf:
						if i.signed:
							c.writeFp(i.rd, c.readFp(i.rn, fmtOf(i.size)) ^ fmtOf(i.size).signBit())
						else:
							c.writeFp(i.rd, c.readFp(i.rn, fmtOf(i.size)) ^ fmtOf(i.size).signBit())
					else:
						if i.signed:
							c.writeFp(i.rd, c.readFp(i.rn, fmtOf(i.size)) ^ fmtOf(i.size).signBit())
						else:
							c.writeFp(i.rd, c.readFp(i.rn, fmtOf(i.size)) ^ fmtOf(i.size).signBit())
				else:
					if i.sf:
						if i.signed:
							c.writeFp(i.rd, c.readFp(i.rn, fmtOf(i.size)) ^ fmtOf(i.size).signBit())
						else:
							c.writeFp(i.rd, c.readFp(i.rn, fmtOf(i.size)) ^ fmtOf(i.size).signBit())
					else:
						if i.signed:
							c.writeFp(i.rd, c.readFp(i.rn, fmtOf(i.size)) ^ fmtOf(i.size).signBit())
						else:
							c.writeFp(i.rd, c.readFp(i.rn, fmtOf(i.size)) ^ fmtOf(i.size).signBit())
		Sqrt:
			if i.setFlags:
				if i.pair:
					if i.sf:
						if i.signed:
							c.writeFp(i.rd, c.fpSqrt(fmtOf(i.size), c.readFp(i.rn, fmtOf(i.size))))
						else:
							c.writeFp(i.rd, c.fpSqrt(fmtOf(i.size), c.readFp(i.rn, fmtOf(i.size))))
					else:
						if i.signed:
							c.writeFp(i.rd, c.fpSqrt(fmtOf(i.size), c.readFp(i.rn, fmtOf(i.size))))
						else:
							c.writeFp(i.rd, c.fpSqrt(fmtOf(i.size), c.readFp(i.rn, fmtOf(i.size))))
				else:
					if i.sf:
						if i.signed:
							c.writeFp(i.rd, c.fpSqrt(fmtOf(i.size), c.readFp(i.rn, fmtOf(i.size))))
						else:
							c.writeFp(i.rd, c.fpSqrt(fmtOf(i.size), c.readFp(i.rn, fmtOf(i.size))))
					else:
						if i.signed:
							c.writeFp(i.rd, c.fpSqrt(fmtOf(i.size), c.readFp(i.rn, fmtOf(i.size))))
						else:
							c.writeFp(i.rd, c.fpSqrt(fmtOf(i.size), c.readFp(i.rn, fmtOf(i.size))))
			else:
				if i.pair:
					if i.sf:
						if i.signed:
							c.writeFp(i.rd, c.fpSqrt(fmtOf(i.size), c.readFp(i.rn, fmtOf(i.size))))
						else:
							c.writeFp(i.rd, c.fpSqrt(fmtOf(i.size), c.readFp(i.rn, fmtOf(i.size))))
					else:
						if i.signed:
							c.writeFp(i.rd, c.fpSqrt(fmtOf(i.size), c.readFp(i.rn, fmtOf(i.size))))
						else:
							c.writeFp(i.rd, c.fpSqrt(fmtOf(i.size), c.readFp(i.rn, fmtOf(i.size))))
				else:
					if i.sf:
						if i.signed:
							c.writeFp(i.rd, c.fpSqrt(fmtOf(i.size), c.readFp(i.rn, fmtOf(i.size))))
						else:
							c.writeFp(i.rd, c.fpSqrt(fmtOf(i.size), c.readFp(i.rn, fmtOf(i.size))))
					else:
						if i.signed:
							c.writeFp(i.rd, c.fpSqrt(fmtOf(i.size), c.readFp(i.rn, fmtOf(i.size))))
						else:
							c.writeFp(i.rd, c.fpSqrt(fmtOf(i.size), c.readFp(i.rn, fmtOf(i.size))))
		Add:
			if i.setFlags:
				if i.pair:
					if i.sf:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Add,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Add,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
					else:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Add,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Add,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
				else:
					if i.sf:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Add,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Add,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
					else:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Add,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Add,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
			else:
				if i.pair:
					if i.sf:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Add,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Add,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
					else:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Add,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Add,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
				else:
					if i.sf:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Add,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Add,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
					else:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Add,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Add,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
		Sub:
			if i.setFlags:
				if i.pair:
					if i.sf:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Sub,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Sub,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
					else:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Sub,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Sub,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
				else:
					if i.sf:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Sub,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Sub,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
					else:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Sub,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Sub,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
			else:
				if i.pair:
					if i.sf:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Sub,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Sub,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
					else:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Sub,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Sub,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
				else:
					if i.sf:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Sub,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Sub,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
					else:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Sub,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Sub,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
		Mul:
			if i.setFlags:
				if i.pair:
					if i.sf:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Mul,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Mul,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
					else:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Mul,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Mul,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
				else:
					if i.sf:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Mul,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Mul,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
					else:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Mul,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Mul,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
			else:
				if i.pair:
					if i.sf:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Mul,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Mul,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
					else:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Mul,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Mul,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
				else:
					if i.sf:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Mul,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Mul,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
					else:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Mul,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Mul,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
		Div:
			if i.setFlags:
				if i.pair:
					if i.sf:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Div,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Div,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
					else:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Div,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Div,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
				else:
					if i.sf:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Div,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Div,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
					else:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Div,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Div,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
			else:
				if i.pair:
					if i.sf:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Div,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Div,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
					else:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Div,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Div,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
				else:
					if i.sf:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Div,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Div,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
					else:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Div,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Div,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
		Max:
			if i.setFlags:
				if i.pair:
					if i.sf:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Max,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Max,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
					else:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Max,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Max,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
				else:
					if i.sf:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Max,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Max,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
					else:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Max,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Max,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
			else:
				if i.pair:
					if i.sf:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Max,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Max,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
					else:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Max,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Max,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
				else:
					if i.sf:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Max,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Max,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
					else:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Max,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Max,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
		Min:
			if i.setFlags:
				if i.pair:
					if i.sf:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Min,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Min,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
					else:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Min,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Min,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
				else:
					if i.sf:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Min,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Min,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
					else:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Min,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Min,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
			else:
				if i.pair:
					if i.sf:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Min,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Min,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
					else:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Min,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Min,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
				else:
					if i.sf:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Min,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Min,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
					else:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Min,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.Min,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
		MaxNum:
			if i.setFlags:
				if i.pair:
					if i.sf:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.MaxNum,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.MaxNum,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
					else:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.MaxNum,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.MaxNum,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
				else:
					if i.sf:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.MaxNum,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.MaxNum,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
					else:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.MaxNum,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.MaxNum,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
			else:
				if i.pair:
					if i.sf:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.MaxNum,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.MaxNum,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
					else:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.MaxNum,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.MaxNum,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
				else:
					if i.sf:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.MaxNum,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.MaxNum,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
					else:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.MaxNum,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.MaxNum,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
		MinNum:
			if i.setFlags:
				if i.pair:
					if i.sf:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.MinNum,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.MinNum,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
					else:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.MinNum,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.MinNum,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
				else:
					if i.sf:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.MinNum,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.MinNum,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
					else:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.MinNum,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.MinNum,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
			else:
				if i.pair:
					if i.sf:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.MinNum,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.MinNum,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
					else:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.MinNum,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.MinNum,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
				else:
					if i.sf:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.MinNum,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.MinNum,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
					else:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.MinNum,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
						else:
							c.writeFp(
								i.rd,
								c.fpArith(
									fmtOf(i.size),
									.MinNum,
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								)
							)
		NegMul:
			if i.setFlags:
				if i.pair:
					if i.sf:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpMul(
									fmtOf(i.size),
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								) ^ fmtOf(i.size).signBit()
							)
						else:
							c.writeFp(
								i.rd,
								c.fpMul(
									fmtOf(i.size),
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								) ^ fmtOf(i.size).signBit()
							)
					else:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpMul(
									fmtOf(i.size),
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								) ^ fmtOf(i.size).signBit()
							)
						else:
							c.writeFp(
								i.rd,
								c.fpMul(
									fmtOf(i.size),
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								) ^ fmtOf(i.size).signBit()
							)
				else:
					if i.sf:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpMul(
									fmtOf(i.size),
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								) ^ fmtOf(i.size).signBit()
							)
						else:
							c.writeFp(
								i.rd,
								c.fpMul(
									fmtOf(i.size),
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								) ^ fmtOf(i.size).signBit()
							)
					else:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpMul(
									fmtOf(i.size),
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								) ^ fmtOf(i.size).signBit()
							)
						else:
							c.writeFp(
								i.rd,
								c.fpMul(
									fmtOf(i.size),
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								) ^ fmtOf(i.size).signBit()
							)
			else:
				if i.pair:
					if i.sf:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpMul(
									fmtOf(i.size),
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								) ^ fmtOf(i.size).signBit()
							)
						else:
							c.writeFp(
								i.rd,
								c.fpMul(
									fmtOf(i.size),
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								) ^ fmtOf(i.size).signBit()
							)
					else:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpMul(
									fmtOf(i.size),
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								) ^ fmtOf(i.size).signBit()
							)
						else:
							c.writeFp(
								i.rd,
								c.fpMul(
									fmtOf(i.size),
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								) ^ fmtOf(i.size).signBit()
							)
				else:
					if i.sf:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpMul(
									fmtOf(i.size),
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								) ^ fmtOf(i.size).signBit()
							)
						else:
							c.writeFp(
								i.rd,
								c.fpMul(
									fmtOf(i.size),
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								) ^ fmtOf(i.size).signBit()
							)
					else:
						if i.signed:
							c.writeFp(
								i.rd,
								c.fpMul(
									fmtOf(i.size),
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								) ^ fmtOf(i.size).signBit()
							)
						else:
							c.writeFp(
								i.rd,
								c.fpMul(
									fmtOf(i.size),
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size))
								) ^ fmtOf(i.size).signBit()
							)
		Compare:
			if i.setFlags:
				if i.pair:
					if i.sf:
						if i.signed:
							c.setNzcv(
								c.fpCompare(fmtOf(i.size), c.readFp(i.rn, fmtOf(i.size)), 0, true)
							)
						else:
							c.setNzcv(
								c.fpCompare(fmtOf(i.size), c.readFp(i.rn, fmtOf(i.size)), 0, true)
							)
					else:
						if i.signed:
							c.setNzcv(
								c.fpCompare(fmtOf(i.size), c.readFp(i.rn, fmtOf(i.size)), 0, true)
							)
						else:
							c.setNzcv(
								c.fpCompare(fmtOf(i.size), c.readFp(i.rn, fmtOf(i.size)), 0, true)
							)
				else:
					if i.sf:
						if i.signed:
							c.setNzcv(
								c.fpCompare(
									fmtOf(i.size),
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size)),
									true
								)
							)
						else:
							c.setNzcv(
								c.fpCompare(
									fmtOf(i.size),
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size)),
									true
								)
							)
					else:
						if i.signed:
							c.setNzcv(
								c.fpCompare(
									fmtOf(i.size),
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size)),
									true
								)
							)
						else:
							c.setNzcv(
								c.fpCompare(
									fmtOf(i.size),
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size)),
									true
								)
							)
			else:
				if i.pair:
					if i.sf:
						if i.signed:
							c.setNzcv(
								c.fpCompare(fmtOf(i.size), c.readFp(i.rn, fmtOf(i.size)), 0, false)
							)
						else:
							c.setNzcv(
								c.fpCompare(fmtOf(i.size), c.readFp(i.rn, fmtOf(i.size)), 0, false)
							)
					else:
						if i.signed:
							c.setNzcv(
								c.fpCompare(fmtOf(i.size), c.readFp(i.rn, fmtOf(i.size)), 0, false)
							)
						else:
							c.setNzcv(
								c.fpCompare(fmtOf(i.size), c.readFp(i.rn, fmtOf(i.size)), 0, false)
							)
				else:
					if i.sf:
						if i.signed:
							c.setNzcv(
								c.fpCompare(
									fmtOf(i.size),
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size)),
									false
								)
							)
						else:
							c.setNzcv(
								c.fpCompare(
									fmtOf(i.size),
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size)),
									false
								)
							)
					else:
						if i.signed:
							c.setNzcv(
								c.fpCompare(
									fmtOf(i.size),
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size)),
									false
								)
							)
						else:
							c.setNzcv(
								c.fpCompare(
									fmtOf(i.size),
									c.readFp(i.rn, fmtOf(i.size)),
									c.readFp(i.rm, fmtOf(i.size)),
									false
								)
							)
		Select:
			if i.setFlags:
				if i.pair:
					if i.sf:
						if i.signed:
							c.writeFp(
								i.rd,
								c.readFp(i.rn, fmtOf(i.size)) if c.holds(i.cond)
								else c.readFp(i.rm, fmtOf(i.size))
							)
						else:
							c.writeFp(
								i.rd,
								c.readFp(i.rn, fmtOf(i.size)) if c.holds(i.cond)
								else c.readFp(i.rm, fmtOf(i.size))
							)
					else:
						if i.signed:
							c.writeFp(
								i.rd,
								c.readFp(i.rn, fmtOf(i.size)) if c.holds(i.cond)
								else c.readFp(i.rm, fmtOf(i.size))
							)
						else:
							c.writeFp(
								i.rd,
								c.readFp(i.rn, fmtOf(i.size)) if c.holds(i.cond)
								else c.readFp(i.rm, fmtOf(i.size))
							)
				else:
					if i.sf:
						if i.signed:
							c.writeFp(
								i.rd,
								c.readFp(i.rn, fmtOf(i.size)) if c.holds(i.cond)
								else c.readFp(i.rm, fmtOf(i.size))
							)
						else:
							c.writeFp(
								i.rd,
								c.readFp(i.rn, fmtOf(i.size)) if c.holds(i.cond)
								else c.readFp(i.rm, fmtOf(i.size))
							)
					else:
						if i.signed:
							c.writeFp(
								i.rd,
								c.readFp(i.rn, fmtOf(i.size)) if c.holds(i.cond)
								else c.readFp(i.rm, fmtOf(i.size))
							)
						else:
							c.writeFp(
								i.rd,
								c.readFp(i.rn, fmtOf(i.size)) if c.holds(i.cond)
								else c.readFp(i.rm, fmtOf(i.size))
							)
			else:
				if i.pair:
					if i.sf:
						if i.signed:
							c.writeFp(
								i.rd,
								c.readFp(i.rn, fmtOf(i.size)) if c.holds(i.cond)
								else c.readFp(i.rm, fmtOf(i.size))
							)
						else:
							c.writeFp(
								i.rd,
								c.readFp(i.rn, fmtOf(i.size)) if c.holds(i.cond)
								else c.readFp(i.rm, fmtOf(i.size))
							)
					else:
						if i.signed:
							c.writeFp(
								i.rd,
								c.readFp(i.rn, fmtOf(i.size)) if c.holds(i.cond)
								else c.readFp(i.rm, fmtOf(i.size))
							)
						else:
							c.writeFp(
								i.rd,
								c.readFp(i.rn, fmtOf(i.size)) if c.holds(i.cond)
								else c.readFp(i.rm, fmtOf(i.size))
							)
				else:
					if i.sf:
						if i.signed:
							c.writeFp(
								i.rd,
								c.readFp(i.rn, fmtOf(i.size)) if c.holds(i.cond)
								else c.readFp(i.rm, fmtOf(i.size))
							)
						else:
							c.writeFp(
								i.rd,
								c.readFp(i.rn, fmtOf(i.size)) if c.holds(i.cond)
								else c.readFp(i.rm, fmtOf(i.size))
							)
					else:
						if i.signed:
							c.writeFp(
								i.rd,
								c.readFp(i.rn, fmtOf(i.size)) if c.holds(i.cond)
								else c.readFp(i.rm, fmtOf(i.size))
							)
						else:
							c.writeFp(
								i.rd,
								c.readFp(i.rn, fmtOf(i.size)) if c.holds(i.cond)
								else c.readFp(i.rm, fmtOf(i.size))
							)
		FromInt:
			if i.setFlags:
				if i.pair:
					if i.sf:
						if i.signed:
							c.writeFp(i.rd, c.fpFromInt(fmtOf(i.size), c.x[i.rn], true, 64, i.imm2))
						else:
							c.writeFp(
								i.rd,
								c.fpFromInt(fmtOf(i.size), c.x[i.rn], false, 64, i.imm2)
							)
					else:
						if i.signed:
							c.writeFp(i.rd, c.fpFromInt(fmtOf(i.size), c.x[i.rn], true, 32, i.imm2))
						else:
							c.writeFp(
								i.rd,
								c.fpFromInt(fmtOf(i.size), c.x[i.rn], false, 32, i.imm2)
							)
				else:
					if i.sf:
						if i.signed:
							c.writeFp(i.rd, c.fpFromInt(fmtOf(i.size), c.x[i.rn], true, 64, i.imm2))
						else:
							c.writeFp(
								i.rd,
								c.fpFromInt(fmtOf(i.size), c.x[i.rn], false, 64, i.imm2)
							)
					else:
						if i.signed:
							c.writeFp(i.rd, c.fpFromInt(fmtOf(i.size), c.x[i.rn], true, 32, i.imm2))
						else:
							c.writeFp(
								i.rd,
								c.fpFromInt(fmtOf(i.size), c.x[i.rn], false, 32, i.imm2)
							)
			else:
				if i.pair:
					if i.sf:
						if i.signed:
							c.writeFp(i.rd, c.fpFromInt(fmtOf(i.size), c.x[i.rn], true, 64, i.imm2))
						else:
							c.writeFp(
								i.rd,
								c.fpFromInt(fmtOf(i.size), c.x[i.rn], false, 64, i.imm2)
							)
					else:
						if i.signed:
							c.writeFp(i.rd, c.fpFromInt(fmtOf(i.size), c.x[i.rn], true, 32, i.imm2))
						else:
							c.writeFp(
								i.rd,
								c.fpFromInt(fmtOf(i.size), c.x[i.rn], false, 32, i.imm2)
							)
				else:
					if i.sf:
						if i.signed:
							c.writeFp(i.rd, c.fpFromInt(fmtOf(i.size), c.x[i.rn], true, 64, i.imm2))
						else:
							c.writeFp(
								i.rd,
								c.fpFromInt(fmtOf(i.size), c.x[i.rn], false, 64, i.imm2)
							)
					else:
						if i.signed:
							c.writeFp(i.rd, c.fpFromInt(fmtOf(i.size), c.x[i.rn], true, 32, i.imm2))
						else:
							c.writeFp(
								i.rd,
								c.fpFromInt(fmtOf(i.size), c.x[i.rn], false, 32, i.imm2)
							)
		ToInt:
			if i.setFlags:
				if i.pair:
					if i.sf:
						if i.signed:
							c.x[i.rd] = c.fpToInt(
								fmtOf(i.size),
								c.readFp(i.rn, fmtOf(i.size)),
								i.imm2,
								i.opc,
								true,
								64
							)
							c.x[31] = 0
						else:
							c.x[i.rd] = c.fpToInt(
								fmtOf(i.size),
								c.readFp(i.rn, fmtOf(i.size)),
								i.imm2,
								i.opc,
								false,
								64
							)
							c.x[31] = 0
					else:
						if i.signed:
							c.x[i.rd] = (
								c.fpToInt(
									fmtOf(i.size),
									c.readFp(i.rn, fmtOf(i.size)),
									i.imm2,
									i.opc,
									true,
									32
								)
							) & 0xFFFF_FFFF
							c.x[31] = 0
						else:
							c.x[i.rd] = (
								c.fpToInt(
									fmtOf(i.size),
									c.readFp(i.rn, fmtOf(i.size)),
									i.imm2,
									i.opc,
									false,
									32
								)
							) & 0xFFFF_FFFF
							c.x[31] = 0
				else:
					if i.sf:
						if i.signed:
							c.x[i.rd] = c.fpToInt(
								fmtOf(i.size),
								c.readFp(i.rn, fmtOf(i.size)),
								i.imm2,
								i.opc,
								true,
								64
							)
							c.x[31] = 0
						else:
							c.x[i.rd] = c.fpToInt(
								fmtOf(i.size),
								c.readFp(i.rn, fmtOf(i.size)),
								i.imm2,
								i.opc,
								false,
								64
							)
							c.x[31] = 0
					else:
						if i.signed:
							c.x[i.rd] = (
								c.fpToInt(
									fmtOf(i.size),
									c.readFp(i.rn, fmtOf(i.size)),
									i.imm2,
									i.opc,
									true,
									32
								)
							) & 0xFFFF_FFFF
							c.x[31] = 0
						else:
							c.x[i.rd] = (
								c.fpToInt(
									fmtOf(i.size),
									c.readFp(i.rn, fmtOf(i.size)),
									i.imm2,
									i.opc,
									false,
									32
								)
							) & 0xFFFF_FFFF
							c.x[31] = 0
			else:
				if i.pair:
					if i.sf:
						if i.signed:
							c.x[i.rd] = c.fpToInt(
								fmtOf(i.size),
								c.readFp(i.rn, fmtOf(i.size)),
								i.imm2,
								i.opc,
								true,
								64
							)
							c.x[31] = 0
						else:
							c.x[i.rd] = c.fpToInt(
								fmtOf(i.size),
								c.readFp(i.rn, fmtOf(i.size)),
								i.imm2,
								i.opc,
								false,
								64
							)
							c.x[31] = 0
					else:
						if i.signed:
							c.x[i.rd] = (
								c.fpToInt(
									fmtOf(i.size),
									c.readFp(i.rn, fmtOf(i.size)),
									i.imm2,
									i.opc,
									true,
									32
								)
							) & 0xFFFF_FFFF
							c.x[31] = 0
						else:
							c.x[i.rd] = (
								c.fpToInt(
									fmtOf(i.size),
									c.readFp(i.rn, fmtOf(i.size)),
									i.imm2,
									i.opc,
									false,
									32
								)
							) & 0xFFFF_FFFF
							c.x[31] = 0
				else:
					if i.sf:
						if i.signed:
							c.x[i.rd] = c.fpToInt(
								fmtOf(i.size),
								c.readFp(i.rn, fmtOf(i.size)),
								i.imm2,
								i.opc,
								true,
								64
							)
							c.x[31] = 0
						else:
							c.x[i.rd] = c.fpToInt(
								fmtOf(i.size),
								c.readFp(i.rn, fmtOf(i.size)),
								i.imm2,
								i.opc,
								false,
								64
							)
							c.x[31] = 0
					else:
						if i.signed:
							c.x[i.rd] = (
								c.fpToInt(
									fmtOf(i.size),
									c.readFp(i.rn, fmtOf(i.size)),
									i.imm2,
									i.opc,
									true,
									32
								)
							) & 0xFFFF_FFFF
							c.x[31] = 0
						else:
							c.x[i.rd] = (
								c.fpToInt(
									fmtOf(i.size),
									c.readFp(i.rn, fmtOf(i.size)),
									i.imm2,
									i.opc,
									false,
									32
								)
							) & 0xFFFF_FFFF
							c.x[31] = 0
		_: c.float(i)
