# 14.3 Performance model
#
# What the backend does that a program can count on. None of it changes what a program computes:
# the test cited after each item runs the shapes it covers and compares the results, and a
# generated shape is seen with `ZAP_RUN=disasm` (13.2).
#
# - Bounds are always checked; a check the compiler proves (a counter within a list it does not
#   resize, a known range within a fixed array, an index rising with the counter, a byte into a
#   table of 256) is removed or made once before the loop, its error then before the first step
#   (tests/containers/hoist.zap).
# - A `for` with known bounds and few steps is unrolled: the written-out form gains nothing
#   (tests/containers/unroll.zap). A loop over a list steps the element's address
#   (forElems.zap), and an element the body reads first is located once per step (hoist.zap).
# - Element-wise arithmetic on lists of one number type runs in SIMD lanes; a signed lane's
#   overflow stops the program as the scalar code does, and a float sum is split into lanes only
#   under `use fusedMultiplyAdd` (3.1), the others' order kept (tests/vectors/plainLoops.zap).
#   A nest that writes rows runs two rows at once when a guard proves no index or integer leaves
#   its range, else as written (tests/vectors/jam.zap).
# - `f32` stays `f32` in registers (tests/numbers/f32.zap); two `f64` operations alike on
#   adjacent words are one, each lane exact (tests/ir/pairs.zap).
# - Small functions, struct operators and a plain function called in a loop are expanded at the
#   call site; a fast path pays for no frame it does not reach (tests/numbers/inlinedFloats.zap).
# - A computation made again in a stretch of code (an operation, a load, a check, a pure call)
#   reads the first one's result.
# - A `match` of four or more integer literals or plain variants is one jump (tests/ir/switches.zap).
# - A call in tail position to a function of the program is a jump: such a recursion runs in
#   constant stack, and an error's trace no longer lists the frames it left (tests/ir/tailCalls.zap).
# - A module variable's scalar a function only loads and stores lives in a register between calls
#   (tests/ir/moduleScalars.zap).
# - A counter's `c / d` and `c % d` by a `d` the loop does not assign are divided once and carried
#   (tests/numbers/divCarried.zap); an affine recurrence `x = x * A + C` runs eight turns a step
#   (tests/ir/affine.zap).
# - Module variables take no bytes of the executable, and one of zero bytes no code; `fill(N, x)`
#   of an array is a few block copies whatever N.
# - `+ - * <<` of `u32` are 32-bit instructions; `rotateLeft`, `rotateRight`, `byteSwap` and
#   `leadingZeros` are one each (3.1).
# - A function of thousands of blocks compiles in time and memory near its size (tests/ir/huge.zap).
# - An overflow or bounds check that the values' ranges prove never fails is removed: a narrow
#   load's width, a branch's comparison where it holds (`i < n` keeps `i + 1` inside, and `xs[i]`
#   too once `i` is never negative), a check passed before. A narrow sum's check that it fits is one
#   comparison with the end it may pass (the tests below). Where `i` may be negative, `while i <
#   xs.len` and the `xs[i]` its turn starts with are one comparison, unsigned, the way out stopping
#   the program when `i` is negative.
# - A loop counted by a constant step proves what its checks of the counter plus a constant need
#   over its turns (an index below a bound it does not assign, a sum that must not overflow, a
#   count added to once a turn): from the ranges when they suffice, else a small loop that calls
#   nothing tests it once before a copy without those checks, running as written when the test
#   fails (tests/ir/guards.zap).

import fs

test "a check and a load made again read the first":
	listing = disassembly(
		"fn twice(xs i64[], i i64) i64:\n\txs[i] + xs[i]\n\nfns = [twice]\nprint(fns[0]([1, 2], 1))\n",
		"twice"
	)
	expect listing.split("jae").len == 2 and listing.split("*8]").len == 2   # one check, one load

test "an array of one value repeated is a few copies, a zero one none":
	listing = disassembly(
		"fn fill(k i64) i64:\n\ta i64[5000] = fill(5000, k)\n\ta[4999] += 1\n\tz f64[3000] = zeros(3000)\n\tz[k] = 1.5\n\ta[0] + a[4999] + i64(z[k])\n\nfns = [fill]\nprint(fns[0](3))\n",
		"fill"
	)
	expect listing.lines().len < 120

# the executable of a program of a module array of n zeros
fn zerosBuild(n i64):
	file = "{testDir()}zeros.zap"
	_ = fs.writeFile(
		file,
		"mut big u8[{n}] = fill({n}, u8(0))\n\nfn last() u8:\n\tbig[{n - 1}]\n\nprint(last())\n"
	)
	Process.output("{zapPath()} build {file}")
	fs.readFile(builtExe("zeros")) ?? ""

test "a module array of zeros takes no code nor file bytes":
	big = zerosBuild(100_000)
	small = zerosBuild(1)
	expect not small.isEmpty and big.len <= small.len + 4096   # (at most the data's next page)

# the instructions of the listing's innermost loop: from its aligned top to the jump back
fn loopOf(listing str):
	lines = listing.lines()
	top = 0
	for i, line in lines:
		if line.startsWith("nop") and i + 1 < lines.len and not lines[i + 1].startsWith("nop"):
			top = i + 1
	end = top
	while end < lines.len and not lines[end].startsWith("jl "):
		end += 1
	lines[top..end].map(.copy())

test "rising indexes and byte tables are checked before the loop":
	body = loopOf(disassembly("alphabet = \"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/\"\n\nfn enc(d u8[], mut out u8[], whole i64):\n\tfor g in 0..whole:\n\t\tv = u32(d[g * 3]) << 16 | u32(d[g * 3 + 1]) << 8 | d[g * 3 + 2]\n\t\tout[g * 2] = alphabet[i64(v >> 18)]\n\t\tout[g * 2 + 1] = alphabet[i64(v & 63)]\n\nmut o u8[] = zeros(4)\nenc([1, 2, 3, 4, 5, 6], o, 2)\nprint(o)\n", "enc"))
	expect not body.isEmpty and not body.any(.startsWith("jae") or .startsWith("jo "))
	table = loopOf(disassembly("fn look(t u8[]) i64:\n\tvalues u8[] = fill(256, 255)\n\tvalues[65] = 0\n\ts = 0\n\tfor g in 0..t.len:\n\t\ts += i64(values[i64(t[g])])\n\ts\n\nprint(look([65, 66]))\n", "look"))
	expect not table.isEmpty and not table.any(.startsWith("jae"))

test "a map's steps store with no test of the room, its length in a register":
	body = loopOf(
		disassembly(
			"fn doubled(n i64) i64[]:\n\t(0..n).map(i: i * 2 + 1)\n\nprint(doubled(5))\n",
			"doubled"
		)
	)
	expect not body.isEmpty and not body.any(.startsWith("call") or "rsp" in it)

test "an affine recurrence runs eight turns a step":
	listing = disassembly("fn noise(n i64) u8[]:\n\tx u32 = 42\n\t(0..n).map(_:\n\t\tx = x * 1_103_515_245 + 12_345\n\t\tu8.wrap(x >> 16)\n\t)\n\nfns = [noise]\nprint(fns[0](10))\n", "noise")
	expect listing.split("imul").len - 1 >= 9   # the step's eight, the loop's one

test "a dense match is a jump through a table":
	listing = disassembly(
		"fn pick(x i64) i64:\n\tmatch x:\n\t\t0: 5\n\t\t1: 7\n\t\t2: 9\n\t\t3: 1\n\t\t5: 2\n\t\t_: 0\n\nfns = [pick]\nprint(fns[0](3))\n",
		"pick"
	)
	expect "jmp      rax" in listing and listing.split("cmp").len == 2   # one range check

test "a tail call is a jump":
	listing = disassembly(
		"fn down(n i64, acc i64) i64:\n\tif n == 0: return acc\n\tdown(n - 1, acc + 1)\n\nprint(down(3, 0))\n",
		"down"
	)
	expect listing.split("call").len == listing.split("jo ").len   # the calls but the checks' exits

test "a u32 sum is a 32-bit add, a rotation one rol":
	listing = disassembly(
		"fn mix(a u32, b u32) u32:\n\t(a + b).rotateLeft(5)\n\nfns = [mix]\nprint(fns[0](1, 2))\n",
		"mix"
	)
	expect "rol" in listing and listing.lines().any(.startsWith("add") and .endsWith("d"))   # add r32, r32

test "words of zero are stored two at a time":
	listing = disassembly(
		"fn named(n i64) i64:\n\ts = \"n\{n}\"\n\ts.len\n\nfns = [named]\nprint(fns[0](3))\n",
		"named"
	)
	expect "vxorps" in listing and "vmovups" in listing and "vmovq" in listing

# - A lambda or a function by name given to a `fn` parameter the callee calls or passes on runs in
#   an instance made for it, as a generic's type arguments make one: the call allocates nothing,
#   its captures in the caller's frame. A lambda that reads `self`, or a parameter the callee
#   stores or returns, keeps the call through the pointer (tests/ir/givenFns.zap).
# - A function is pure when nothing it does or calls reaches outside the program, reads or changes
#   a module variable (`args` is one), calls a stored function value or changes a parameter;
#   allocating does not count. A pure call over numbers and bools is an operation: made once for
#   the same arguments, taken out of a loop that does not change them, dropped when unused
#   (`ZAP_RUN=purity` says why; tests/ir/pureCalls.zap).
# - Division by a constant is a multiplication and a shift, with no zero check
#   (tests/fuzz/divisions.zap); small forms are one instruction (tests/numbers/peepholes.zap).
# - A list literal lent to a read-only parameter, its elements owning nothing, has no heap block.

type Pair:
	x f32
	y f32

fn total(xs i64[]):
	s = 0
	for x in xs:
		s += x
	s

fn spread(ps Pair[], k i64):
	s = f32(0.0)
	for p in ps:
		s += p.x * f32(k) + p.y
	s

fn grow(mut xs i64[]):
	xs.push(4)

test "a list literal lent to a read parameter allocates nothing":
	a = 3
	before = allocations()
	t = 0
	for i in 0..1000:
		t += total([i, a, 7])
	r = spread([Pair(x = 1.0, y = 2.0), Pair(x = 0.5, y = 0.25)], total([1, 2]))
	made = allocations() - before
	xs = [1, 2, 3]
	grow(xs)
	print("{t} {r} {made} {xs}")
	prints "509500 6.75 0 [1, 2, 3, 4]"

# - A list literal whose elements own nothing is built in the frame, with no heap block, where it
#   is only read: lent to a read parameter, looped over, or read by a pipeline or `len`.

fn shifted(x i64):
	s = 0
	for shift in [0, 5, 10]:
		s += x >> shift
	s + [1, 2, x].map(it * 2).sum() + [4, x].len

test "a list literal a loop or a pipeline reads allocates nothing":
	before = allocations()
	t = 0
	for i in 0..1000:
		t += shifted(i)
	made = allocations() - before
	print("{t} {made}")
	prints "1521628 0"

# - String equality compares the lengths first; an interpolated string and `join` size their block
#   once.
# - A pipeline is one loop per chain (7.2), its lambdas' outer subexpressions computed once before
#   it; one that may stop the program stays in the loop (tests/containers/pipeLoop.zap).

fn safeDivide(xs i64[], d i64):
	xs.map(it / d).sum()

test "a divisor is read only when there are elements":
	expect safeDivide([], 0) == 0
	expect safeDivide([10, 20], 5) == 6

test "a check the ranges prove goes, a narrow sum's is one comparison":
	listing = disassembly(
		"fn steps(v i64[], k i64) i64:\n\ts = 0\n\tj = 0\n\twhile j < v.len:\n\t\ts += v[j]\n\t\tj += k.max(1)\n\ts\n\nfns = [steps]\nprint(fns[0]([1, 2, 3], 1))\n",
		"steps"
	)
	expect not listing.lines().any(.startsWith("jae"))   # j never negative, below v.len
	bump = disassembly(
		"fn bump(c i8[], i i64) i8:\n\tc[i] + 1\n\nfns = [bump]\nprint(fns[0]([126], 0))\n",
		"bump"
	)
	expect bump.split("movsx").len == 2   # the load's only: no wrap compared with the sum

test "a counted loop's checks are tested once before a copy without them":
	listing = disassembly(
		"fn total(v i64[], n i64) i64:\n\ts = 0\n\ti = 0\n\twhile i < n:\n\t\ts ^= v[i + 1]\n\t\ti += 1\n\ts\n\nfns = [total]\nprint(fns[0]([1, 2, 3], 2))\n",
		"total"
	)
	lines = listing.lines()
	expect lines.count(.startsWith("jl ")) == 2   # the copy and the loop as written
	expect lines.count(.startsWith("jae")) == 2   # the guard's test and the written loop's check

fn jumps(v i64[]):
	s = 0
	i = 0
	while i < v.len:
		i = v[i]
		s ^= i
	s

test "a loop's test and the index its turn starts with are one comparison":
	listing = disassembly(
		"fn jumps(v i64[]) i64:\n\ts = 0\n\ti = 0\n\twhile i < v.len:\n\t\ti = v[i]\n\t\ts ^= i\n\ts\n\nfns = [jumps]\nprint(fns[0]([1, 2, 5]))\n",
		"jumps"
	)
	expect listing.split("\njb ").len == 2 and listing.split("\njae").len == 2   # (in, past)
	expect jumps([1, 2, 5]) == 6 and jumps([3]) == 3 and jumps([]) == 0

test "an index below zero at a loop's test still stops" stops IndexOutOfBounds:
	print(jumps([1, -5, 2]))

test "a narrow sum past its end still stops" stops IntegerOverflow:
	fn bump(c i8[], i i64) i8:
		c[i] + 1
	print(bump([127], args.len))

test "a narrow difference past its end still stops" stops IntegerOverflow:
	fn drop(c i16[], i i64) i16:
		c[i] - 1
	print(drop([-32_768], args.len))

test "an index below the length but negative still stops" stops IndexOutOfBounds:
	fn at(xs i64[], i i64) i64:
		if i < xs.len: return xs[i]
		0
	print(at([1, 2], args.len - 1))

# - `(a, b) = (x, y)` of scalars makes no tuple (tests/basics/tupleAssign.zap); a `match` on an enum
#   reads its tag once (tests/basics/match.zap).
# - What a program drops is used again without being asked: freed blocks by later ones of their
#   size, wholly free chunks returned to the system (tests/memory/chunks.zap); a short str has no
#   block (14.2); `xs = xs.filter(p)`, `.map(f)`, `.sortedBy(k)` and a `replace` that does not grow
#   work in the old block (tests/containers/inPlace.zap); a list a loop's binding makes takes the
#   block it had the turn before (tests/memory/recycle.zap); a statement of a loop that keeps
#   nothing it allocates allocates from a region given back whole (tests/memory/regions.zap).
#   `allocations()` counts blocks, so a stretch of code is measured by two readings.

test "allocations counts the blocks made":
	before = allocations()
	xs = (0..10).map("n{it}")
	expect xs.len == 10
	expect allocations() - before > 0
