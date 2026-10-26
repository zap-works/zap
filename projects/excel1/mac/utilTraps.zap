# long: the Toolbox's utilities, one arm each
#
# The Toolbox's smaller traps: strings, resources of the common types, packages, handles' copies,
# fixed-point numbers, the scrap, dates and the application's parameters.

import cpu

fn newStringHandle(s u8[]):
	h = newHandle(theZone(), u32(s.len + 1))
	writePascal(address(cpu.read32(h)), s)
	h

fn handleBytes(h u32):
	bytesAt(address(cpu.read32(h)), handleSize(h))

# a copy of the bytes into a handle of their size: 0 when there is no room
fn handleOf(bytes u8[]) u32:
	h = newHandle(theZone(), u32(bytes.len))
	if h == 0: return 0
	at = address(cpu.read32(h))
	for i, b in bytes:
		cpu.write8(at + u32(i), b)
	h

fn appendToHandle(h u32, bytes u8[]):
	old = i64(handleSize(h))
	e = setHandleSize(h, u32(old + bytes.len))
	if e != noErr: return e
	at = address(cpu.read32(h)) + u32(old)
	for i, b in bytes:
		cpu.write8(at + u32(i), b)
	noErr

fn fixedMul(a i64, b i64) u32:
	u32.wrap(a * b >> 16)

# Munger: in the handle from offset, the first ptr1's bytes found replaced by ptr2's (all of it
# replaced when ptr1 is 0, nothing inserted when ptr2 is 0): the offset after the replacement, -1
# when not found
fn munger(
	h u32,
	offset i64,
	find u8[],
	hasFind bool,
	put u8[],
	hasPut bool,
	replacedLength i64
):
	data = handleBytes(h)
	at = offset
	length = replacedLength
	if hasFind:
		found = -1
		i = offset
		while i + find.len <= data.len:
			if data[i..i + find.len] == find:
				found = i
				break
			i += 1
		if found < 0: return -1
		at = found
		length = find.len
	if not hasPut: return at
	end = (at + length).min(data.len)
	out = data[..at].copy()
	out.extend(put)
	out.extend(data[end..])
	setHandleSize(h, u32(out.len))
	p = address(cpu.read32(h))
	for i, b in out:
		cpu.write8(p + u32(i), b)
	data = []
	at + put.len

# long: a dispatch, an arm a trap
pub fn utilityTrap(n i64, trapWord i64, back u32) u32:
	match n:
		0x58, 0x5B, 0x59:
			b = popLong()
			a = popLong()
			resultLong(a & b if n == 0x58 else (a | b if n == 0x5B else a ^ b))
		0x5A: resultLong(~popLong())
		0x5C:
			count = popInt()
			v = popLong()
			resultLong(v << (count & 31) if count >= 0 else v >> (-count & 31))
		0x5D, 0x5E, 0x5F:
			bit = i64(popLong())
			at = popLong() + u32(bit / 8)
			mask = u32(0x80) >> (bit % 8)
			old = cpu.read8(at)
			if n == 0x5D:
				resultBool(old & mask != 0)
			else:
				cpu.write8(at, old | mask if n == 0x5E else old & ~mask)
		0x67:
			at = popLong()
			b = i64(i32.wrap(i64(popLong())))
			a = i64(i32.wrap(i64(popLong())))
			product = a * b
			cpu.write32(at, u32.wrap(product >> 32))
			cpu.write32(at + 4, u32.wrap(product))
		0x68:
			b = i64(i32.wrap(i64(popLong())))
			a = i64(i32.wrap(i64(popLong())))
			resultLong(fixedMul(a, b))
		0x69:
			denominator = popInt()
			numerator = popInt()
			resultLong(
				0x7FFF_FFFF if denominator == 0 else u32.wrap((numerator << 16) / denominator)
			)
		0x6C: resultWord((i64(i32.wrap(i64(popLong()))) + 0x8000) >> 16)
		0x106: resultLong(newStringHandle(pascalAt(popLong())))
		0x107:
			s = pascalAt(popLong())
			h = popLong()
			setHandleSize(h, u32(s.len + 1))
			writePascal(address(cpu.read32(h)), s)
		0x14E:
			pt = popLong()
			r = readRect(popLong())
			v, h = pointOf(pt)
			resultLong(pointValue(v.clamp(r.top, r.bottom - 1), h.clamp(r.left, r.right - 1)))
		0x14F:
			bv, bh = pointOf(popLong())
			av, ah = pointOf(popLong())
			resultLong(pointValue(av - bv, ah - bh))
		0x179, 0x17A, 0x189, 0x18A: popInt()
		0x17B: cpu.write32(resumeProcAt, popLong())
		0x18B:
			for i in 0..4:
				s = popLong()
				slot = daStringsAt + u32((3 - i) * 4)
				old = cpu.read32(slot)
				if old != 0: disposeHandle(old)
				cpu.write32(slot, newStringHandle(pascalAt(s)) if s != 0 else 0)
		0x1B6:
			popLong()
			resultWord(0)
		0x1B7: popInt()
		0x1B8, 0x1B9, 0x1BA, 0x1BB, 0x1BC:
			id = popInt()
			kind = match n:
				0x1B8: 0x5041_5420
				0x1B9: 0x4355_5253
				0x1BA: 0x5354_5220
				0x1BB: 0x4943_4F4E
				_: 0x5049_4354
			resultLong(getResource(kind, id, [], false))
		0x1C1:
			kind = i64(popLong())
			id = 128
			while findResource(kind, id, [], false) != none:
				id += 1
			resultWord(id)
		0x1C9:
			code = popInt()
			cpu.stop("SysError {code}")
		0x1CC:
			cpu.write32(teScrpHandleAt, newHandle(theZone(), 0))
			setWord(teScrpLengthAt, 0)
		0x1E0:
			putLength = i64(i32.wrap(i64(popLong())))
			put = popLong()
			findLength = i64(i32.wrap(i64(popLong())))
			find = popLong()
			offset = i64(popLong())
			h = popLong()
			found = bytesAt(find, findLength) if find != 0 else []
			replacement = bytesAt(put, putLength) if put != 0 else []
			replaced = findLength if findLength >= 0 else handleSize(h) - offset
			resultLong(
				u32.wrap(munger(h, offset, found, find != 0, replacement, put != 0, replaced))
			)
		0x1E1:
			copy = handleOf(handleBytes(cpu.a0))
			cpu.a0 = copy
			cpu.d0 = 0 if copy != 0 else u32.wrap(memFullErr)
		0x1E2:
			bytes = bytesAt(cpu.a0, cpu.d0)
			setHandleSize(cpu.a1, 0)
			cpu.d0 = u32.wrap(appendToHandle(cpu.a1, bytes))
		0x1E3:
			h = handleOf(bytesAt(cpu.a0, cpu.d0))
			cpu.a0 = h
			cpu.d0 = 0 if h != 0 else u32.wrap(memFullErr)
		0x1E4:
			cpu.d0 = u32.wrap(appendToHandle(cpu.a1, handleBytes(cpu.a0)))
			cpu.a0 = cpu.a1
		0x1EF:
			cpu.d0 = u32.wrap(appendToHandle(cpu.a1, bytesAt(cpu.a0, cpu.d0)))
			cpu.a0 = cpu.a1
		0x1E5: popInt()
		0x1E6: pass
		0x1E7, 0x1E8, 0x1E9, 0x1EA, 0x1EB, 0x1EC, 0x1ED, 0x1EE:
			h = getResource(0x5041_434B, n - 0x1E7, [], false)
			if h == 0: cpu.stop("no PACK {n - 0x1E7}")
			setFlag(h, lockedBit, true)
			cpu.push32(back)
			return address(cpu.read32(h))
		0x1F5:
			paramAt = popLong()
			refNumAt = popLong()
			nameAt = popLong()
			writePascal(nameAt, pascalAt(curApNameAt))
			setWord(refNumAt, word(curApRefNumAt))
			cpu.write32(paramAt, cpu.read32(appParmHandleAt))
		0x1F9: resultLong(scrapSizeAt)
		0x1FA, 0x1FB, 0x1FC: resultLong(0)
		0x1FD:
			popLong()
			popLong()
			popLong()
			resultLong(u32.wrap(-102))
		0x1FE:
			popLong()
			popLong()
			popLong()
			resultLong(0)
		0x1FF: cpu.stop("Debugger")
		_: return unimplemented(trapWord, back)
	back
