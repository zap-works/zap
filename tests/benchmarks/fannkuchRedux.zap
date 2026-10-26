# fannkuch-redux: every permutation of 1..n, counting the flips that bring 1 to the front. A
# permutation is a Simd<16, u8>: a flip is a shuffle by a mask computed in registers from the leading
# element, the step to the next permutation one shuffle through a table of masks picked by the
# level whose count goes up, the counts sixteen bytes of their own. The
# permutations are split into chunks by index (the factorial number system gives the first
# permutation of a chunk), and the chunks run on every processor through .parallel(). Prints the
# checksum and the maximum flip count.
import problems

fn factorials(n i64):
	(0..=n).map((1..=it).reduce(1, (f, k): f * k))

# the shuffle masks, sixteen bytes each: step[i] the rotations of the first 2, 3, .. i+1 elements
# left by one, one after the other (rots[i] rotates the first i+1), the step when the count of
# level i goes up and those below it start again; step[0] the identity
fn stepMasks():
	rots = (0..16).flatMap(i: (0..16).map(u8(it + 1 if it < i else 0 if it == i else it)))
	steps u8[] = zeros(256)
	m = rots.load16(0)   # the identity
	for i in 0..16:
		m = m.shuffle(rots.load16(i * 16))   # p.shuffle(a).shuffle(b) is p.shuffle(a.shuffle(b))
		steps.store16(i * 16, m)
	steps

# the permutation with the given index (as sixteen bytes) and the count array that continues from it
fn firstPermutation(n i64, fact i64[], index i64, mut count i64[]):
	p = (0..16).map(u8(it))
	idx = index
	for i in 1..n:
		k = n - i   # from the last position down
		d = idx / fact[k]
		count[k] = d
		idx %= fact[k]
		before = p.copy()
		for j in 0..=(k):
			p[j] = before[(j + d) % (k + 1)]   # the first k+1 rotated left by d
	p

# the checksum and the most flips of one chunk of permutations
fn runChunk(n i64, fact i64[], steps u8[], chunk i64, task i64):
	idxMin = task * chunk
	idxMax = (idxMin + chunk).min(fact[n])
	count = zeros(16)
	perm = firstPermutation(n, fact, idxMin, count).load16(0)
	counts = count.map(u8(it)).load16(0)
	ramp = steps.load16(0)   # 0, 1, .. 15
	zero = Simd<16>(0)
	high = Simd<16>(128)
	maxFlips = 1
	checksum = 0
	for i in idxMin..idxMax:
		first = perm.lane(0)
		if first != 0:
			# a flip reverses the first `first`+1 elements: lane j takes lane first-j when
			# j <= first (the difference is negative past it, so the blend keeps j); the
			# element at `first` leads afterwards, fetched for the test before the flip
			cur = perm
			lead = perm.shuffle(zero)   # lane 0 in every lane
			f = 0
			top = first
			while top != 0:
				idx = lead - ramp
				next = cur.shuffle(lead)
				cur = cur.shuffle(idx.blend(ramp, idx))
				lead = next
				top = next.lane(0)
				f += 1
			maxFlips = maxFlips.max(f)
			checksum += f if (i & 1) == 0 else -f
		if i + 1 < idxMax:
			# the next permutation: the first level whose count is below it goes up, those under it
			# back to 0 (the count of level j is lane j)
			level = ((counts - ramp) & high).eqMask(high).trailingZeros()
			split = Simd<16>(u8(level))
			counts = counts.blend(zero, ramp - split) - ramp.eqBytes(split)
			perm = perm.shuffle(steps.load16(level * 16))
	(checksum, maxFlips)

n = arg(0, 7)
fact = factorials(n)
steps = stepMasks()
chunk = ((fact[n] + 149) / 150).max(1)
tasks = (fact[n] + chunk - 1) / chunk
parts = (0..tasks).parallel().map(task: runChunk(n, fact, steps, chunk, task))
mut checksum = 0
mut maxFlips = 0
for (sum, flipped) in parts:
	checksum += sum
	maxFlips = maxFlips.max(flipped)
print(checksum)
print("Pfannkuchen({n}) = {maxFlips}")

test "the flips of every permutation give the known checksum and most flips":
	main()
	prints """
	    228
	    Pfannkuchen(7) = 16
	    """

test "the C, Rust and Python programs print the same bytes":
	expect problems.agree("fannkuchRedux")
