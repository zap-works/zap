# The 65816's registers as the recompiled functions read and write them: the accumulator (C, its
# low byte A), the index registers, the stack pointer, the direct page and the data bank; the
# program bank is where the code is, known when translating. The widths (emulation, M, X) are
# known when translating too: here only what a push of the status register or a pull of one needs.
# The flags are kept as four booleans and the rest of the status register as its bits.

import recomp.snes.console

pub mut a u16 = 0
pub mut x u16 = 0
pub mut y u16 = 0
pub mut s u16 = 0x01FF
pub mut d u16 = 0
pub mut dbr u8 = 0

pub mut n bool = false
pub mut v bool = false
pub mut z bool = false
pub mut c bool = false
pub mut irqDisabled bool = true
pub mut decimal bool = false
pub mut e bool = true   # emulation mode, as the CPU starts

# where the last return went, bank << 16 | pc: each call compares it with the address after it,
# and a function returns when it differs (a return past the function that made it)
pub mut ret u32 = 0

# What the recompiled program gives the CPU: the function at an address called in widths (bits
# e, m, x; another value calls it in the widths it starts in), false when there is none; the same
# only in those widths; the interpreter's step of one instruction (interpret.zap); a stop with
# the reason.
pub type Hooks:
	call fn(u32, u32) bool
	callExact fn(u32, u32) bool = noCall
	step fn(u32, u32) u32 = noStep
	stop fn(str) = stopHere

fn noCall(at u32, widths u32):
	eprint("no function to call at 0x{at:06X} ({widths}): the recompiled program has not started")
	false

fn stopHere(why str):
	fail(why)

fn noStep(at u32, widths u32) u32:
	stopHere("no interpreter to run 0x{at:06X} in widths {widths}")
	leaving

pub mut hooks = Hooks(call = noCall)

# the widths the dispatcher reads as "those the function starts in"
pub anyWidths u32 = 0xFF

# `--trace N`: from frame N on, each recompiled function entered is printed (its address and the
# frame), to find where the program's path parts from the original's; `--steps N` each instruction
# too, with the master cycle it starts at, as Mesen 2's trace logger lists them
pub mut tracing = false
mut traceFrom = -1
mut stepsFrom = -1

pub fn stepped(at u32):
	if stepsFrom < 0 or console.frameCount < stepsFrom: return
	print("{console.cycles} {at:06X} a={a:04X} x={x:04X} y={y:04X} s={s:04X}")

pub fn entered(at u32):
	if console.frameCount < traceFrom: return
	print("{console.frameCount} {console.cycles} {at:06X} a={a:04X} x={x:04X} y={y:04X} s={s:04X} d={d:04X} b={dbr:02X}")

# A jump to an address the translation did not know: the function there translated in the widths
# the code runs in, else the code there interpreted (interpret.zap); in widths not known
# (anyWidths) the function there in those it starts in.
pub fn go(at u32, widths u32):
	if widths == anyWidths:
		if hooks.call(at, widths): return
		interpret(at, currentWidths(), true)
		return
	goFrom(at, widths)

pub fn noLabel(pc u32, f str):
	hooks.stop("no label 0x{pc:08X} in {f}")

pub fn unsupported(at u32, what str):
	hooks.stop("{what} at 0x{at:06X}: no recompiled code runs it")

# The stack, in bank 0; in emulation mode it stays in page 1.
pub fn push8(b u8):
	console.cpuWrite(s, b)
	s = 0x100 | ((s - 1) & 0xFF) if e else s - 1

pub fn push16(w u16):
	push8(u8.wrap(w >> 8))
	push8(u8.wrap(w))

pub fn pull8() u8:
	s = 0x100 | ((s + 1) & 0xFF) if e else s + 1
	console.cpuRead(s)

pub fn pull16() u16:
	lo = pull8()
	lo | (u16(pull8()) << 8)

# The addresses of the modes: the direct page and the stack in bank 0 (their sums wrap at 16
# bits), the others in the data bank, an index carrying into the bank above; and the internal
# cycles they take: a direct page off a page boundary one, an index added to the direct page or
# the stack one, an index added to an address one where it writes, its index is 16 bits or it
# crosses a page.
pub fn direct(off u32) u32:
	if d & 0xFF != 0: console.idle()
	(d + off) & 0xFFFF

pub fn directIndexed(off u32, index u16) u32:
	if d & 0xFF != 0: console.idle()
	console.idle()
	(d + off + index) & 0xFFFF

pub fn stackRelative(off u32) u32:
	console.idle()
	(s + off) & 0xFFFF

pub fn data(addr u32) u32:
	(u32(dbr) << 16) | addr

pub fn indexed(addr u32, index u16) u32:
	(addr + index) & 0xFF_FFFF

# an 8-bit index read through: a page crossed costs the internal cycle
pub fn indexedRead(addr u32, index u16) u32:
	at = (addr + index) & 0xFF_FFFF
	if (at ^ addr) & 0xFF00 != 0: console.idle()
	at

pub fn indexedIdle(addr u32, index u16) u32:
	console.idle()
	(addr + index) & 0xFF_FFFF

# The data's accesses, a bus cycle a byte (a 16-bit one low byte first, a read-modify-write's
# write high byte first); those of bank 0 wrap at FFFF.
pub fn readData8(at u32) u8:
	console.cpuRead(at)

pub fn readData16(at u32) u16:
	lo = console.cpuRead(at)
	lo | (u16(console.cpuRead((at + 1) & 0xFF_FFFF)) << 8)

pub fn writeData8(at u32, v u8):
	console.cpuWrite(at, v)

pub fn writeData16(at u32, w u16):
	console.cpuWrite(at, u8.wrap(w))
	console.cpuWrite((at + 1) & 0xFF_FFFF, u8.wrap(w >> 8))

pub fn modifyData16(at u32, w u16):
	console.cpuWrite((at + 1) & 0xFF_FFFF, u8.wrap(w >> 8))
	console.cpuWrite(at, u8.wrap(w))

pub fn readData16Bank0(at u32) u16:
	lo = console.cpuRead(at)
	lo | (u16(console.cpuRead((at + 1) & 0xFFFF)) << 8)

pub fn writeData16Bank0(at u32, w u16):
	console.cpuWrite(at, u8.wrap(w))
	console.cpuWrite((at + 1) & 0xFFFF, u8.wrap(w >> 8))

pub fn modifyData16Bank0(at u32, w u16):
	console.cpuWrite((at + 1) & 0xFFFF, u8.wrap(w >> 8))
	console.cpuWrite(at, u8.wrap(w))

pub fn read24Bank0(at u32) u32:
	lo = u32(readData16Bank0(at))
	lo | (u32(console.cpuRead((at + 2) & 0xFFFF)) << 16)

# a pointer of bank 0 to the data bank
pub fn pointer(at u32) u32:
	data(readData16Bank0(at))

# The status register: the flags, M and X (the widths, as the translation knows them), D and I.
type Status bits u8:
	n bool = 7
	v bool = 6
	m bool = 5
	x bool = 4
	decimal bool = 3
	irqDisabled bool = 2
	z bool = 1
	c bool = 0

pub fn status(widths u8) u8:
	u8(Status(n, v, decimal, irqDisabled, z, c)) | widths

pub fn setStatus(p u8):
	flags = Status(p)
	n = flags.n
	v = flags.v
	decimal = flags.decimal
	irqDisabled = flags.irqDisabled
	z = flags.z
	c = flags.c
	if not e and flags.x:
		x &= 0xFF
		y &= 0xFF

# plp where the widths are not known: those it pulls
pub fn pullStatusAny():
	p = pull8()
	setStatus(p)
	widthsNow = 7 if e else u32(p >> 4) & 3

# rep and sep where the operand is not known: its bits of the status cleared or set, the widths
# with them
pub fn changeStatus(bits u8, set bool):
	p = status(u8((widthsNow << 4) & 0x30))
	pulled = p | bits if set else p & ~bits
	setStatus(pulled)
	if not e: widthsNow = u32(pulled >> 4) & 3

# plp, which the translation follows in the widths php kept. Other widths (a status the code
# built itself): the code after it, at `next`, goes on interpreted in those, and the translated
# function leaves as a jump would. Whether it did.
pub fn pullStatus(widths u8, next u32) bool:
	p = pull8()
	setStatus(p)
	if e or p & 0x30 == widths: return false
	interpret(next, u32(p >> 4) & 3, true)
	true

# xce: the carry and the emulation bit swapped; emulation mode keeps 8-bit index registers and
# the stack in page 1
pub fn exchangeCarry():
	t = c
	c = e
	e = t
	if e:
		x &= 0xFF
		y &= 0xFF
		s = 0x100 | (s & 0xFF)
	widthsNow = 7 if e else widthsNow & 3

# The returns: where they go kept in ret, the widths the code returns in in widthsNow.
pub fn returnShort(bank u32, widths u32):
	ret = (bank << 16) | (pull16() + 1)
	widthsNow = widths

pub fn returnLong(widths u32):
	widthsNow = widths
	pc = pull16() + 1
	ret = (u32(pull8()) << 16) | pc

pub fn returnInterrupt():
	p = pull8()
	setStatus(p)
	widthsNow = 7 if e else u32(p >> 4) & 3
	pc = pull16()
	bank = 0 if e else pull8()
	ret = (u32(bank) << 16) | pc

# The arithmetic: binary, or in decimal mode a nibble at a time as the 65816 adjusts them (and as
# Mesen 2 computes them, the overflow from the binary sum before the last nibble's adjust).
pub fn adc8(b u8):
	if decimal: return decimalAdd(i64(u8.wrap(a)), i64(b), 2, false)
	lo = u8.wrap(a)
	r = u16(lo) + u16(b) + (1 if c else 0)
	out = u8.wrap(r)
	c = r > 0xFF
	v = ~(lo ^ b) & (lo ^ out) & 0x80 != 0
	setA8(out)

pub fn adc16(b u16):
	if decimal: return decimalAdd(i64(a), i64(b), 4, false)
	r = u32(a) + u32(b) + (1 if c else 0)
	out = u16.wrap(r)
	c = r > 0xFFFF
	v = ~(a ^ b) & (a ^ out) & 0x8000 != 0
	setA16(out)

pub fn sbc8(b u8):
	if decimal: return decimalAdd(i64(u8.wrap(a)), i64(~b), 2, true)
	adc8(~b)

pub fn sbc16(b u16):
	if decimal: return decimalAdd(i64(a), i64(~b), 4, true)
	adc16(~b)

# `nibbles` nibbles of x plus those of y (y the ones' complement of the operand when subtracting)
# with the carry, each nibble adjusted by 6 past 9 (an add), or by -6 when a subtraction's nibble
# does not carry
fn decimalAdd(x i64, y i64, nibbles i64, subtracting bool):
	result = (x & 0x0F) + (y & 0x0F) + (1 if c else 0)
	for k in 0..nibbles:
		mask = 0xF << (4 * k)
		top = (0x10 << (4 * k)) - 1
		if k > 0:
			result = (x & mask) + (y & mask) + ((0x10 << (4 * (k - 1))) if c else 0) +
				(result & (top >> 4))
		if k == nibbles - 1:
			sign = 0x8 << (4 * k)
			v = ~(x ^ y) & (x ^ result) & sign != 0
		if subtracting:
			if result <= top: result -= 6 << (4 * k)
		elif result > (0x9 << (4 * k)) | (top >> 4):
			result += 6 << (4 * k)
		c = result > top
	if nibbles == 2:
		setA8(u8.wrap(result))
	else:
		setA16(u16.wrap(result))

fn setA8(r u8):
	a = (a & 0xFF00) | u16(r)
	n = r >= 0x80
	z = r == 0

fn setA16(r u16):
	a = r
	n = r >= 0x8000
	z = r == 0

pub fn compare8(r u8, b u8):
	c = r >= b
	z = r == b
	n = r - b >= 0x80

pub fn compare16(r u16, b u16):
	c = r >= b
	z = r == b
	n = r - b >= 0x8000

# mvn (step 1) and mvp (step -1) at `at`, in the widths (the status register's M and X): A + 1
# bytes from bank src at X to bank dst at Y, the index registers as wide as X says; the data bank
# left at dst. Each byte its instruction's three fetches, its read and write and two internal
# cycles; an interrupt may come between two bytes, as the instruction runs again for each: it
# returns to the move, which goes on. Whether the code returns, unwinding.
pub fn moveBlock(src u8, dst u8, step i64, widths u8, at u32) bool:
	dbr = dst
	loop:
		console.fetch(3, at)
		moved = console.cpuRead((u32(src) << 16) | x)
		console.cpuWrite((u32(dst) << 16) | y, moved)
		console.idle()
		console.idle()
		x = u16.wrap(x + step)
		y = u16.wrap(y + step)
		if widths & 0x10 != 0:
			x &= 0xFF
			y &= 0xFF
		a -= 1
		if a == 0xFFFF: return false
		if console.cycles >= console.eventDue and poll(at, widths): return true

# two bytes of a bank, the second wrapping to 0000 after FFFF (jmp (a,x) reads its pointer so)
pub fn read16In(bank u32, at u32) u16:
	lo = console.cpuRead(bank | (at & 0xFFFF))
	lo | (u16(console.cpuRead(bank | ((at + 1) & 0xFFFF))) << 8)
