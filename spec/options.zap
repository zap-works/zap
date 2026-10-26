# 2.6 Options
#
# `use` followed by option names is the one way to set a compiler option, the same for a file, a
# function and a block: it is the first line of its scope and holds to the scope's end, blocks
# inside included (a file's: after its imports, its functions and its statements alike,
# tests/numbers/fusedFile.zap; a `fn`'s or a test's:
# that body; a `for`, `if`, `loop`, `match` arm or any other block's: that block). Anywhere else
# it is an error, so a scope's options are read at its top.

fn fused(a f64):
	use fusedMultiplyAdd
	a * 10.0 - 1.0

fn blocks(a f64):
	inner = 0.0
	deeper = 0.0
	if a > 0.0:
		use fusedMultiplyAdd
		inner = a * 10.0 - 1.0
		loop 1:
			deeper = a * 10.0 - 1.0
	outer = a * 10.0 - 1.0
	(inner, deeper, outer)

fn loopBody(a f64):
	acc = 0.0
	loop 1:
		use fusedMultiplyAdd
		acc = a * 10.0 - 1.0
	acc

test "an option holds to its scope's end, blocks inside included":
	inner, deeper, outer = blocks(0.1)
	expect inner == fused(0.1)
	expect deeper == fused(0.1)
	expect not (outer == fused(0.1))
	expect loopBody(0.1) == fused(0.1)

test "use is the first line of its scope" refuses UseNotFirst:
	fn f(x f64) f64:
		y = x
		use fusedMultiplyAdd
		y * 2.0 + 1.0

	print(f(1.0))

# The names are a closed set (std `syntax.options`), no library adds one, and each names the exact
# operation or guarantee it changes, never an adjective such as fast or unsafe. A departure from
# the safe default: `fusedMultiplyAdd` (3.1). Promises: `noAllocation`, `noLocks`, `noStops`.

# A promise is checked through every call the scope makes once the bodies are, user functions and
# the runtime's alike, and its error names the chain of calls to the offender. The rules are
# conservative: what the compiler cannot follow is refused. A function that ends the program
# (`fail`) is followed no further.
#
# `noAllocation`: nothing reached allocates: no list or map literal, no string built from parts, no
# lambda that captures, no `Box`, no call of a function value, no built-in call that gives a list, a
# map, a string or a box or grows a list or a map, and no function reaching the runtime's allocator.
# `noLocks`: nothing reached waits: no call of a function value and no function reaching a wait of
# the system (the channels, `sleepMs`, a socket's wait, a background job).

fn dot(xs f64[], ys f64[]):
	use noAllocation, noLocks
	acc = 0.0
	for i, x in xs:
		acc += x * ys[i]
	acc

fn largest(xs i64[]):
	best = 0
	for x in xs:
		use noAllocation
		if x > best:
			best = x
		if x < -1000:
			fail("too small")
	best

test "noAllocation and noLocks kept":
	expect dot([1.0, 2.0, 3.0], [4.0, 5.0, 6.0]) == 32
	expect largest([1, 3, 2]) == 3

test "noAllocation refuses a list literal" refuses OptionBroken("`use noAllocation` is broken: a list literal"):
	fn f(n i64) i64:
		use noAllocation
		xs = [n, n]
		xs[0]

	print(f(1))

test "noAllocation names the chain of calls" refuses OptionBroken("`use noAllocation` is broken by this call: grow -> fill -> push, which grows a i64[]"):
	fn fill(mut xs i64[]):
		xs.push(1)

	fn grow(mut xs i64[]):
		fill(xs)

	fn work(mut xs i64[]):
		use noAllocation
		grow(xs)

	mut xs i64[] = []
	work(xs)
	print(xs.len)

test "noLocks names the chain of calls" refuses OptionBroken("`use noLocks` is broken by this call: take -> receive -> ringReceive -> receiveSlot -> ring -> AcquireSRWLockExclusive, which waits"):
	fn take(ch Channel<i64>) i64:
		ch.receive() ?? 0

	fn work(ch Channel<i64>) i64:
		use noLocks
		take(ch)

	ch = Channel<i64>(1)
	_ = ch.send(1)
	print(work(ch))

test "a promise refuses a call of a function value" refuses OptionBroken("`use noLocks` is broken: a call of a function value"):
	fn g(h fn(i64) i64) i64:
		use noLocks
		h(1)

	print(g(x: x))

# `noStops`: nothing reached stops the program (6.6): each `+ - *` and negation of signed integers
# proven not to overflow, each divisor not 0 (nor -1 under the type's minimum), each shift's count
# inside the width, each conversion into a narrower or a range type inside it, each index and slice
# inside, each range's step positive; no `fail` or `exit`, no `m[k]`, no call of a function value,
# no function on a cycle of calls (its stack may overflow). A loop that may never end, and memory
# that runs out, do not count as stops.
#
# What it proves: an integer lies in its type's bounds (a range type's, a narrower width's), a
# literal, a constant and an immutable local bound to a number in their value, a conversion in its
# operand, `x & mask` in `0..=mask`, `x % n` below `n`, `1 << n` and arithmetic in what their
# operands give when that fits the type; unsigned `+ - *` wrap and floats never stop. An index is
# inside a fixed array, or a module's constant list, when its value is proven so.
#
# A check against a list's or a text's length proves the indexes it bounds, where it holds: in an
# `if`'s block (and an `if`'s value), after an `if` that leaves, in a `while`'s body, on the right
# of `and`, in `for i in a..xs.len` (or `..n.min(xs.len)`). It compares sums of one index, one
# length and numbers: `i < xs.len`, `at + 4 <= d.len`, `d.len - at < 4` failing, `not
# xs.isEmpty`, `xs.len == n`; a name bound to `xs.len - k` reads as it. What it proves: `xs[i]`
# and `xs[i + k]` (the index's own range keeping it from going below 0), `xs[xs.len - k]`,
# `xs[a..b]`, `xs.loadWord(i)`, and that the index plus or minus a small number never overflows (a
# length is below 2^62). A fact ends where its index or its list's length may change: a
# statement that may change them (an assignment, a `mut` argument or borrow, a method that changes
# the list or what holds it, a call of a function value), a loop whose body may, a lambda's body
# for what is `mut`; writing an element keeps the length.
#
# The runtime's own arithmetic and indexes are trusted: it stops only through its explicit checks
# of what the program hands it, so its readers of bytes say how: `d.u32le(at)` stops past the end,
# a `Reader` gives 0 and notes `short`, a JSON cursor outside its text reads nothing. The standard
# library's decoders (`deflate.inflateZlib`, `image.decodePng`, `json.parse`) are written under
# `noStops`: a damaged or hostile input gives an error, never a stop.

type Percent = i64 in 0..=100

fn product(a i32, b i32):
	use noStops
	i64(a) * i64(b) + 1

fn low(a i64) i32:
	use noStops
	a & 0xFFFF

fn table(a i64, b n64, t u8[16]):
	use noStops
	sum u64 = 0
	for i in 0..16:
		sum += t[i]
	i64(t[a & 15]) - i64(t[b % 16]) / 3 + i64(t[3]) + i64(sum & 0xFFFF)

fn fnv(xs u8[]):
	use noStops
	h u32 = 2_166_136_261
	for x in xs:
		h = (h ^ x) * 16_777_619
	h

fn health(p Percent, bonus u8):
	use noStops
	p * 2 + i64(bonus)

fn scaled(mut xs f64[], k f64):
	use noStops
	for i, x in xs:
		xs[i] = x * k
	for i in 0..xs.len:
		xs[i] += xs[i].max(0.0)

fn smallest(xs i64[]):
	use noStops
	best = xs.first ?? 0
	for x in xs:
		best = best.min(x)
	best

fn named(m {str: i64}, k str):
	use noStops
	m.get(k) ?? 0

fn word(d u8[], at n64) u32:
	use noStops
	if d.len - at < 4: return 0
	d[at] | u32(d[at + 3]) << 8

fn spaces(s str) n64:
	use noStops
	n = s.len
	i n64 = 0
	while i < n and s[i] == ' ':
		i += 1
	i

fn at(xs i64[], i n64):
	use noStops
	if xs.isEmpty: return 0
	xs[i] if i < xs.len else xs[0]

fn halvings(n u64) i64:
	use noStops
	left = n
	count = 0.0
	while left > 0:
		left >>= 1
		count += 1.0
	i64(left)

widths = [1, 2, 4, 8]
maskBits = 3

# the bytes after a header of n (its first byte), the header's own last word; nothing when cut
fn body(d u8[]) (u8[], u64):
	use noStops
	if d.isEmpty: return ([], 0)
	n = d[0]
	if d.len - n < 9: return ([], 0)
	(d[n + 1..].copy(), d.loadWord(n + 1))

# a byte's width, from a constant list
fn widthOf(b u8):
	use noStops
	widths[b & maskBits]

# the sum of the bytes, and of the first 64's widths: sums in loops of a bounded count
fn sums(d u8[]):
	use noStops
	total = 0
	for b in d:
		total += b
	widthSum = 0
	for i in 0..d.len.min(64):
		widthSum += widthOf(d[i]).clamp(0, 8)
	(total, widthSum)

test "code under noStops computes what it computed with its checks":
	xs = [1.0, -2.0]
	scaled(xs, 2.0)
	row u8[16] = fill(16, 3)
	expect product(-7, 9) == -62
	expect low(65_537) == 1
	expect table(5, 7, row) == 53
	expect fnv([1]) == 67_918_732
	print("{health(Percent(40), 3)} {xs} {smallest([3, 1])} {named({"a": 2}, "a")} {halvings(8)}")
	expect word == {([1, 2, 3, 4], 0): 1025, ([1], 0): 0}
	expect spaces("  a") == 2
	expect at == {([5, 6], 1): 6, ([5], 3): 5}
	print("{body([0, 1, 0, 0, 0, 0, 0, 0, 0, 7])} {body([3])} {sums([0, 1, 2, 3, 7])}")
	prints """
		83 [4, -4] 1 2 0
		([1, 0, 0, 0, 0, 0, 0, 0, 7], 1) ([], 0) (13, 23)
		"""

test "noStops names the operation and the fact missing" refuses OptionBroken("`use noStops` is broken: a + not proven not to overflow i64"):
	fn add(a i64, b i64) i64:
		use noStops
		a + b

	print(add(1, 2))

test "noStops refuses a recursion" refuses OptionBroken("`use noStops` is broken: depth, which calls itself again (its stack may overflow)"):
	fn depth(n i64) i64:
		depth(n / 2) if n > 0 else 0

	fn work(n i64) i64:
		use noStops
		depth(n)

	print(work(4))

test "a sum is proven only in a loop of a known count" refuses OptionBroken("`use noStops` is broken: a + not proven not to overflow i64"):
	fn total(d u8[]) i64:
		use noStops
		sum = 0
		i n64 = 0
		while i < d.len:
			sum += d[i]
			i += 1
		sum

	print(total([1]))

test "a fact about a length ends where the list may change" refuses OptionBroken("`use noStops` is broken: an index not proven inside its i64[]"):
	fn last(mut xs i64[]) i64:
		use noStops
		if xs.len < 2: return 0
		end = xs.len - 1
		_ = xs.pop()
		xs[end]

	mut ys = [1, 2]
	print(last(ys))

test "a check against a length ends where the index may change" refuses OptionBroken("`use noStops` is broken: an index not proven inside its i64[]"):
	fn walk(xs i64[]) i64:
		use noStops
		i = 0
		s = 0
		if i < xs.len:
			loop 2:
				s = xs[i]
				i = s % 3
		s

	print(walk([1]))

test "a check against a length proves only the indexes below it" refuses OptionBroken("`use noStops` is broken: an index not proven inside its i64[]"):
	fn last(xs i64[], i n64) i64:
		use noStops
		xs[i] if i <= xs.len else 0

	print(last([1], 0))

test "an index is proven only while a call cannot shorten the list" refuses OptionBroken("`use noStops` is broken: an index not proven inside its i64[]"):
	fn shorten(mut xs i64[]):
		_ = xs.pop()

	fn drain(mut xs i64[]) i64:
		use noStops
		s = 0
		for i, x in xs:
			s = s | x
			shorten(xs)
		s

	mut xs = [1, 2]
	print(drain(xs))
