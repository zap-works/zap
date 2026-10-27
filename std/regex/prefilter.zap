# What a search can skip before any automaton runs: the positions where no match can begin. From
# the pattern's start state come the bytes a match can begin with and the pairs of bytes it can
# begin with. A scan passes over positions whose pair cannot begin one; when the pairs are few
# enough to be written as a handful of "one of these bytes, then one of those" tests, 32 positions
# are judged at once with vector comparisons.

# the most tests (bytes compared) a vector filter makes for 32 positions
maxVectorTests = 24

# the most paths of first bytes a match may begin with that are listed to build the vector filter
maxPaths = 64

# one test of the vector filter: the first byte is one of `firsts`, the next one of `seconds`
# the one after one of `thirds` and the next of `fourths`, a list left empty standing for any byte
type Bucket:
	firsts u8[]
	seconds u8[]
	thirds u8[]
	fourths u8[]

pub type Prefilter:
	canStart u8[]   # 256 bytes, then the end of the text: 1 where a match can begin
	pairs u8[]   # first byte * 256 + second: 1 where a match can begin
	buckets Bucket[]   # empty when a few such tests do not tell where a match can begin
	vectors Simd<32, u8>[]   # the buckets' bytes, spread over a vector each, in order
	single i64   # the byte every match begins with and nothing more is known, else -1

	# the first position at or after p, in 32 at a time, where some bucket's test holds; where the
	# text is too near its end for a block, the position the scan stopped at
	fn vectorSkip(text u8[], p0 i64):
		p = p0
		limit = text.len - 35
		while p <= limit:
			a = text.load32(p)
			b = text.load32(p + 1)
			c = text.load32(p + 2)
			d = text.load32(p + 3)
			found = 0
			at = 0
			for bucket in buckets:
				here = -1
				if not bucket.firsts.isEmpty:
					here = 0
					for k in 0..bucket.firsts.len:
						here |= a.eqMask(vectors[at + k])
					at += bucket.firsts.len
				if not bucket.seconds.isEmpty:
					next = 0
					for k in 0..bucket.seconds.len:
						next |= b.eqMask(vectors[at + k])
					at += bucket.seconds.len
					here &= next
				if not bucket.thirds.isEmpty:
					after = 0
					for k in 0..bucket.thirds.len:
						after |= c.eqMask(vectors[at + k])
					at += bucket.thirds.len
					here &= after
				if not bucket.fourths.isEmpty:
					last = 0
					for k in 0..bucket.fourths.len:
						last |= d.eqMask(vectors[at + k])
					at += bucket.fourths.len
					here &= last
				found |= here
			if found != 0: return p + found.trailingZeros()
			p += 32
		p

	# The first position at or after p where a match can begin, or n: a pair of bytes that cannot
	# begin one is passed over; the last byte is judged alone.
	fn skip(text u8[], p0 i64):
		if single >= 0: return findByte(text, u8(single), p0)
		p = p0
		last = text.len - 1
		if not buckets.isEmpty:
			# a candidate close by is found by the pairs, a far one by the vectors
			stop = (p + 8).min(last)
			while p < stop and pairs[(i64(text[p]) << 8) + text[p + 1]] == 0:
				p += 1
			if p == stop:
				p = self.vectorSkip(text, p)
		while p < last and pairs[(i64(text[p]) << 8) + text[p + 1]] == 0:
			p += 1
		if p == last and canStart[text[p]] == 0: p += 1
		p

# the bytes of a class of the automaton
type ClassBytes:
	values u8[]

fn classBytes(a Dfa):
	bytes = []
	loop a.nfa.classes:
		bytes.push(ClassBytes(values = []))
	for b in 0..256:
		bytes[a.nfa.classOf[b]].values.push(b)
	bytes

# the classes of the first bytes of a match, -1 where the match is over or may go on with any byte
type Path:
	first i64
	second i64
	third i64
	fourth i64

# the classes that can begin a match, as paths of up to `depth` bytes
fn startPaths(mut a Dfa, depth i64):
	paths = []
	for kind in 0..3:
		start = a.startAt(kind)
		if a.matching[start] == 1 or a.waits(start): return []
		a.extendPaths(paths, Path(-1, -1, -1, -1), start, 0, depth)
	if paths.len > maxPaths: return []
	paths

# the paths that go on from state s, which is after `place` bytes of `prefix`
fn extendPaths(mut dfa Dfa, mut paths Path[], prefix Path, s i64, place i64, depth i64):
	for c in 0..dfa.nfa.classes:
		if paths.len > maxPaths: return
		t = dfa.go(s, c)
		if t == 0: continue
		path = Path(
			c if place == 0 else prefix.first,
			c if place == 1 else prefix.second,
			c if place == 2 else prefix.third,
			c if place == 3 else prefix.fourth
		)
		if place + 1 == depth or dfa.holdsMore(t):
			paths.push(path)
		else:
			dfa.extendPaths(paths, path, t, place + 1, depth)

# whether a match may be over, or wait for the end of the text, in state s: nothing is known of
# the next byte
fn holdsMore(dfa Dfa, s i64):
	more = dfa.matching[s] == 1 or (dfa.flags[s] & flagLagging) != 0
	for k in dfa.at[s]..dfa.at[s] + dfa.size[s]:
		if dfa.nfa.kind[dfa.members[k]] != stByte: more = true
	more

# the union of the bytes of the classes in the list, empty when it is all bytes
fn unionBytes(bytes ClassBytes[], classes i64[]):
	union = []
	for c in classes:
		if c >= 0: union.extend(bytes[c].values)
	if union.len == 256: return []
	union

# the buckets of the paths, or none when they take too many tests: the first classes that share
# the rest of their path are one bucket
fn bucketsOf(bytes ClassBytes[], paths Path[]):
	buckets = []
	done u8[] = zeros(paths.len)
	tests = 0
	for i in 0..paths.len:
		if done[i] == 1: continue
		firsts = []
		for k in i..paths.len:
			if done[k] == 0 and paths[k].second == paths[i].second and
				paths[k].third == paths[i].third and paths[k].fourth == paths[i].fourth:
				firsts.push(paths[k].first)
				done[k] = 1
		bucket = Bucket(
			firsts = unionBytes(bytes, firsts),
			seconds = unionBytes(bytes, [paths[i].second]),
			thirds = unionBytes(bytes, [paths[i].third]),
			fourths = unionBytes(bytes, [paths[i].fourth])
		)
		if bucket.firsts.len > 8 or bucket.seconds.len > 8 or bucket.thirds.len > 8 or
			bucket.fourths.len > 8:
			return []
		tests += bucket.firsts.len + bucket.seconds.len + bucket.thirds.len + bucket.fourths.len
		if tests > maxVectorTests: return []
		buckets.push(bucket)
	buckets

# the prefilter of a pattern whose anchored automaton is a
fn prefilterOf(mut a Dfa):
	canStart = a.startBytes()
	pairs = a.startPairs()
	bytes = a.classBytes()
	buckets = []
	for depth in [4, 3, 2, 1]:
		if buckets.isEmpty:
			buckets = bucketsOf(bytes, a.startPaths(depth))
	vectors = []
	for bucket in buckets:
		for b in bucket.firsts:
			vectors.push(Simd<32, u8>(b))
		for b in bucket.seconds:
			vectors.push(Simd<32, u8>(b))
		for b in bucket.thirds:
			vectors.push(Simd<32, u8>(b))
		for b in bucket.fourths:
			vectors.push(Simd<32, u8>(b))
	only = -1
	if buckets.len == 1 and buckets[0].firsts.len == 1 and buckets[0].seconds.isEmpty:
		only = buckets[0].firsts[0]
	Prefilter(canStart, pairs, buckets, vectors, single = only)

# The first position at or after p holding the byte b, or n, 32 bytes at a time.
fn findByte(text u8[], b u8, p0 i64):
	wide = Simd<32, u8>(b)
	n = text.len
	p = p0
	while p + 32 <= n:
		hits = text.load32(p).eqMask(wide)
		if hits != 0: return p + hits.trailingZeros()
		p += 32
	while p < n and text[p] != b:
		p += 1
	p
