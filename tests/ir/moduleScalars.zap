# Module scalars kept in vregs between calls: each value a function stores is in memory again
# before any call (which may read or change it), before a return, and wherever a way goes on to
# a block that loads it from memory.

mut r0 u32 = 0
mut r1 u32 = 5
mut zero = false
mut carry = false
mut count = 0
mut seen i64[] = []

type Point:
	x i64
	y i64

mut at = Point(x = 0, y = 0)

fn getR(i i64):
	r0 if i == 0 else r1

fn setR(i i64, v u32):
	if i == 0:
		r0 = v
	else:
		r1 = v

# an interpreter's loop: the flags set in one arm of a switch, read in another a turn later
fn interpret(code i64[]):
	i = 0
	while i < code.len:
		kind = code[i]
		a = code[i + 1]
		i += 2
		ra = getR(a)
		match kind:
			0: setR(a, ra + 1)
			1: setR(a, ra - 1)
			10:
				zero = ra == 0
				carry = ra < 3
			11:
				if zero: setR(a, ra + 7)
			_: pass

fn flags():
	"{r0} {r1} {zero} {carry}"

# a callee that reads what the caller just stored
fn counted():
	count * 10

fn bumps(n i64):
	total = 0
	for k in 0..n:
		count += 1
		total += counted()
		if k % 2 == 0: count += 100
	total

# fields of a module struct, a module list's header, and a store on one way only
fn walk(n i64):
	for k in 0..n:
		at.x += k
		if k % 3 == 0:
			at.y = at.x
		seen.push(at.y)

# stored, then returned without a call: the store reaches memory
fn setOnly(v u32):
	r0 = v
	if v > 10: return true
	r1 = v * 2
	false

test "flags set in one arm of a switch and read in another":
	interpret([10, 0, 11, 1, 10, 1, 11, 0, 0, 0, 1, 1])
	expect flags() == "1 11 false false"

test "a store reaches memory before a call that reads it":
	expect bumps(4) == 4100
	expect count == 204

test "fields of a module struct and a module list's header":
	walk(7)
	print("{at.x} {at.y} {seen}")
	prints "21 21 [0, 0, 0, 6, 6, 6, 21]"

test "a store before a return":
	expect setOnly(20)
	expect r0 == 20
	expect not setOnly(3)
	expect r0 == 3
	expect r1 == 6
