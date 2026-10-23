# What the cryptographic extension does: AES rounds, SHA-1 and SHA-256 steps (FIPS 197 and
# 180-4, as the Arm ARM's pseudocode orders them). Words are 32 bits in a u64.

import cipher
import recomp.switch.arm64

fn rol32(x u64, n i64) u64:
	u32(x & mask32).rotateLeft(n)

fn ror32(x u64, n i64) u64:
	u32(x & mask32).rotateRight(n)

# the state's bytes in the order ShiftRows (or its inverse) puts them
fn shiftedRows(s Vec, inverse bool):
	out = Vec()
	for column in 0..4:
		for row in 0..4:
			from = (column - row + 4) % 4 if inverse else (column + row) % 4
			out.setLane(8, row + 4 * column, s.lane(8, row + 4 * from))
	out

fn substituted(s Vec, inverse bool):
	out = Vec()
	for k in 0..16:
		b = i64(s.lane(8, k))
		out.setLane(8, k, cipher.inverseSbox[b] if inverse else cipher.sbox[b])
	out

# MixColumns, or its inverse
fn mixedColumns(s Vec, inverse bool):
	coef = [14, 11, 13, 9] if inverse else [2, 3, 1, 1]
	out = Vec()
	for column in 0..4:
		for row in 0..4:
			sum = 0
			for j in 0..4:
				sum ^= cipher.gmul(i64(s.lane(8, 4 * column + j)), coef[(j - row + 4) % 4])
			out.setLane(8, 4 * column + row, u64(sum))
	out

pub fn aes(mut c Cpu, i arm64.Instr):
	a = c.vecRead(i.rn)
	d = c.vecRead(i.rd)
	r = match i.opc:
		4:
			x = Vec(lo = d.lo ^ a.lo, hi = d.hi ^ a.hi)
			x.shiftedRows(false).substituted(false)
		5:
			x = Vec(lo = d.lo ^ a.lo, hi = d.hi ^ a.hi)
			x.shiftedRows(true).substituted(true)
		6: a.mixedColumns(false)
		_: a.mixedColumns(true)
	c.vecWrite(i.rd, r, true)

fn choose(x u64, y u64, z u64):
	((y ^ z) & x) ^ z

fn parity(x u64, y u64, z u64):
	x ^ y ^ z

fn majority(x u64, y u64, z u64):
	(x & y) | ((x | y) & z)

# Y:X (a word and four) rotated left by one word: X moves up, Y enters below, X's top word is
# the new Y
fn rotatedWord(x Vec, y u64):
	out = Vec()
	out.setLane(32, 0, y)
	for k in 1..4:
		out.setLane(32, k, x.lane(32, k - 1))
	(out, x.lane(32, 3))

# SHA1C, SHA1P, SHA1M: four rounds with the choose, parity or majority function
fn sha1Rounds(mut c Cpu, i arm64.Instr):
	x = c.vecRead(i.rd)
	y = c.vecRead(i.rn).lane(32, 0)
	w = c.vecRead(i.rm)
	for e in 0..4:
		x1 = x.lane(32, 1)
		x2 = x.lane(32, 2)
		x3 = x.lane(32, 3)
		t = match i.opc:
			0: choose(x1, x2, x3)
			1: parity(x1, x2, x3)
			_: majority(x1, x2, x3)
		y = (y + rol32(x.lane(32, 0), 5) + t + w.lane(32, e)) & mask32
		x.setLane(32, 1, rol32(x1, 30))
		nextX, nextY = x.rotatedWord(y)
		x = nextX
		y = nextY
	c.vecWrite(i.rd, x, true)

fn sha1Schedule0(mut c Cpu, i arm64.Instr):
	d = c.vecRead(i.rd)
	a = c.vecRead(i.rn)
	w = c.vecRead(i.rm)
	t = Vec(lo = d.hi, hi = a.lo)
	c.vecWrite(i.rd, Vec(lo = t.lo ^ d.lo ^ w.lo, hi = t.hi ^ d.hi ^ w.hi), true)

# SHA256H and SHA256H2: four rounds of the hash; the first returns the new abcd, the second efgh
fn sha256Rounds(mut c Cpu, i arm64.Instr):
	first = i.opc == 4
	x = c.vecRead(i.rd) if first else c.vecRead(i.rn)
	y = c.vecRead(i.rn) if first else c.vecRead(i.rd)
	w = c.vecRead(i.rm)
	for e in 0..4:
		y0 = y.lane(32, 0)
		x0 = x.lane(32, 0)
		sigma1 = ror32(y0, 6) ^ ror32(y0, 11) ^ ror32(y0, 25)
		sigma0 = ror32(x0, 2) ^ ror32(x0, 13) ^ ror32(x0, 22)
		chs = choose(y0, y.lane(32, 1), y.lane(32, 2))
		maj = majority(x0, x.lane(32, 1), x.lane(32, 2))
		t = (y.lane(32, 3) + sigma1 + chs + w.lane(32, e)) & mask32
		x.setLane(32, 3, (t + x.lane(32, 3)) & mask32)
		y.setLane(32, 3, (t + sigma0 + maj) & mask32)
		# <Y, X> rotated left by a word, both registers moving up
		newX = Vec()
		newY = Vec()
		newX.setLane(32, 0, y.lane(32, 3))
		newY.setLane(32, 0, x.lane(32, 3))
		for k in 1..4:
			newX.setLane(32, k, x.lane(32, k - 1))
			newY.setLane(32, k, y.lane(32, k - 1))
		x = newX
		y = newY
	c.vecWrite(i.rd, x if first else y, true)

fn sha1Schedule1(mut c Cpu, i arm64.Instr):
	d = c.vecRead(i.rd)
	a = c.vecRead(i.rn)
	t = Vec()
	for k in 0..4:
		t.setLane(32, k, d.lane(32, k) ^ (a.lane(32, k + 1) if k < 3 else 0))
	out = Vec()
	for k in 0..4:
		out.setLane(32, k, rol32(t.lane(32, k), 1))
	out.setLane(32, 3, out.lane(32, 3) ^ rol32(t.lane(32, 0), 2))
	c.vecWrite(i.rd, out, true)

fn sha256Schedule0(mut c Cpu, i arm64.Instr):
	d = c.vecRead(i.rd)
	a = c.vecRead(i.rn)
	out = Vec()
	for k in 0..4:
		elt = d.lane(32, k + 1) if k < 3 else a.lane(32, 0)
		mixed = ror32(elt, 7) ^ ror32(elt, 18) ^ (elt >> 3)
		out.setLane(32, k, (d.lane(32, k) + mixed) & mask32)
	c.vecWrite(i.rd, out, true)

fn sha256Schedule1(mut c Cpu, i arm64.Instr):
	d = c.vecRead(i.rd)
	a = c.vecRead(i.rn)
	w = c.vecRead(i.rm)
	out = Vec()
	for e in 0..4:
		elt = w.lane(32, e + 2) if e < 2 else out.lane(32, e - 2)
		mixed = ror32(elt, 17) ^ ror32(elt, 19) ^ (elt >> 10)
		t0 = a.lane(32, e + 1) if e < 3 else w.lane(32, 0)
		out.setLane(32, e, (mixed + d.lane(32, e) + t0) & mask32)
	c.vecWrite(i.rd, out, true)

pub fn shaThree(mut c Cpu, i arm64.Instr):
	match i.opc:
		0, 1, 2: c.sha1Rounds(i)
		3: c.sha1Schedule0(i)
		4, 5: c.sha256Rounds(i)
		_: c.sha256Schedule1(i)

pub fn shaTwo(mut c Cpu, i arm64.Instr):
	match i.opc:
		0: c.vecWrite(i.rd, Vec(lo = rol32(c.vecRead(i.rn).lane(32, 0), 30)), false)
		1: c.sha1Schedule1(i)
		_: c.sha256Schedule0(i)
