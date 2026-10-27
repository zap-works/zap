# The parsed pattern as a Thompson NFA, built backwards: `emit(node, next)` gives the state that
# runs the node and then goes to `next`. A split lists its two targets in priority order (the
# preferred first), which is what leftmost-first matching reads. State 0 is the match.

stByte = 0   # x: the set, y: the next state
stSplit = 1   # x: the preferred next state, y: the other
stMatch = 2
stHead = 3   # x: the next state, taken at the start of the scan
stTail = 4   # x: the next state, taken at its end
stBound = 5   # x: the next state, taken at a word's edge (y 0) or where there is none (y 1)
stAdvance = 7   # x: the next state, taken once a byte has been read since the scan began (the search for a match that is not empty)
stLoopBack = 8   # x: the next iteration, y: the state after the loop, z: the iteration's first state: taken after an iteration's body, y when z was reached already (the iteration read no byte)
stTrailBefore = 9   # a match that ends before the text's last byte, a newline (a `$` held there): the match, when the text ends after that byte
stTrailAfter = 10   # the same for a match that ends after that byte
stSave = 6   # x: the next state; y: the capture slot that takes the position (only in the captures' NFA)

maxStates = 200_000
maxDoubled = 20_000   # a loop whose body can match nothing is built twice below this many states

type Nfa:
	kind i64[] = [stMatch]
	x i64[] = [0]
	z i64[] = [0]   # the third operand of stLoopBack
	y i64[] = [0]
	start i64 = 0
	sets u8[] = []   # 256 bytes a set
	classOf u8[] = []   # the class of each byte: bytes no set tells apart share one
	reps i64[] = []   # a byte of each class
	classes i64 = 0
	bounds bool = false   # the pattern has a word edge (b or B after a backslash): a state knows whether the byte before it was a word byte
	asciiBounds bool = false   # the word edges are ASCII's: the flag `a`
	quits bool = false   # the pattern has word edges, which a scan cannot judge beside a byte that is not ASCII: it gives up there
	trailing bool = false   # a `$` also holds before the text's last byte when that is a newline
	reverse bool = false   # the automaton of the reversed pattern
	trailBefore i64 = 0   # the states stTrailBefore and stTrailAfter
	trailAfter i64 = 0
	lines bool = false   # `^` and `$` also hold at the ends of lines: a newline is a class of its own

	# the bytes grouped by the sets that hold them
	fn classify():
		setCount = sets.len / 256
		classOf = zeros(256)
		for b in 0..256:
			found = -1
			for k, rep in reps:
				same = true
				r = rep
				for s in 0..setCount:
					if sets[s * 256 + b] != sets[s * 256 + r]:
						same = false
						break
				if same:
					found = k
					break
			if found < 0:
				found = reps.push(b)
			classOf[b] = u8(found)
		classes = reps.len

type Builder:
	nodes Node[]
	classCodes i64[]   # the code point ranges of the classes, as the parser has them
	classEnds i64[]
	nfa Nfa
	reverse bool   # the automaton of the reversed pattern, to be run backwards
	saves bool   # the groups' positions are saved: the automaton that reads the captures of a match
	error str = ""
	rangeSets {i64: i64} = {}   # the set of a byte range (low * 256 + high) that is in the NFA already

	# the index of the set of the bytes from lo to hi, added to the NFA when new
	fn rangeSet(lo i64, hi i64):
		if rangeSets.get(lo * 256 + hi) is known: return known
		members u8[] = zeros(256)
		for b in lo..=hi:
			members[b] = 1
		nfa.sets.extend(members)
		rangeSets[lo * 256 + hi] = nfa.sets.len / 256 - 1
		nfa.sets.len / 256 - 1

	# The states that read one character of the class and go to next: one for its ASCII members, and a
	# chain for each way of writing the others in UTF-8, the chains sharing the states they end alike.
	fn emitClass(index i64, next i64):
		ranges = classCodes[(0 if index == 0 else classEnds[index - 1])..classEnds[index]]
		ascii u8[] = zeros(256)
		anyAscii = false
		sequences = []
		for k in 0..ranges.len / 2:
			if ranges[2 * k] < 0x80:
				for c in ranges[2 * k]..=ranges[2 * k + 1].min(0x7F):
					ascii[c] = 1
				anyAscii = true
			if ranges[2 * k + 1] >= 0x80:
				utf8Sequences(ranges[2 * k].max(0x80), ranges[2 * k + 1], sequences)
		entries = []
		if anyAscii or sequences.isEmpty:
			nfa.sets.extend(ascii)
			entries.push(self.state(stByte, nfa.sets.len / 256 - 1, next))
		sharedEnds {i64: i64} = {}
		at = 0
		while at < sequences.len:
			n = sequences[at]
			state = next
			for step in 0..n:
				k = step if reverse else n - 1 - step
				set = self.rangeSet(sequences[at + 1 + 2 * k], sequences[at + 2 + 2 * k])
				key = set * 1_048_576 + state
				if sharedEnds.get(key) is known:
					state = known
				else:
					state = self.state(stByte, set, state)
					sharedEnds[key] = state
			entries.push(state)
			at += 1 + 2 * n
		chain = entries[len - 1]
		for k in 2..=entries.len:
			chain = self.state(stSplit, entries[len - k], chain)
		chain

	fn state(kind i64, x i64, y i64, z i64 = 0):
		if nfa.kind.len >= maxStates:
			if error.isEmpty: error = "regex: the pattern needs too many states"
			return 0
		nfa.kind.push(kind)
		nfa.x.push(x)
		nfa.y.push(y)
		nfa.z.push(z)
		nfa.kind.len - 1

	# a split to a and b, the lazy form preferring b
	mut fn split(a i64, b i64, lazy bool) i64:
		if lazy: return self.state(stSplit, b, a)
		self.state(stSplit, a, b)

	# The loop of a repetition of the child: it returns the loop's split, or, for a `+`, the body
	# that is run first. The body ends in a state that goes back to the split, or past the loop when
	# the iteration read no byte (the split has been reached already), as Python takes the match
	# of an empty iteration once and stops.
	mut fn star(child i64, next i64, lazy bool, bodyFirst bool = false):
		loop_ = self.state(stSplit, 0, 0)
		other = self.state(stSplit, 0, 0) if self.nullable(child) and nfa.kind.len < maxDoubled
			else loop_
		body = self.emit(child, self.state(stLoopBack, other, next, loop_))
		nfa.x[loop_] = next if lazy else body
		nfa.y[loop_] = body if lazy else next
		if other != loop_:
			# a body that can read nothing has a second copy for the iteration after this one, so an
			# empty iteration is tried on states the one before has not reached
			again = self.emit(child, self.state(stLoopBack, loop_, next, other))
			nfa.x[other] = next if lazy else again
			nfa.y[other] = again if lazy else next
		body if bodyFirst else loop_

	# whether the node can match without reading a byte
	fn nullable(node i64) bool:
		n = nodes[node]
		if n.kind == nodeSet or n.kind == nodeClass: return false
		if n.kind == nodeCat: return self.nullable(n.a) and self.nullable(n.b)
		if n.kind == nodeAlt: return self.nullable(n.a) or self.nullable(n.b)
		if n.kind == nodePlus or n.kind == nodeGroup: return self.nullable(n.a)
		if n.kind == nodeRepeat: return n.b == 0 or self.nullable(n.a)
		true

	fn emit(node i64, next i64) i64:
		n = nodes[node]
		if n.kind == nodeEmpty: return next
		if n.kind == nodeSet: return self.state(stByte, n.a, next)
		if n.kind == nodeClass: return self.emitClass(n.a, next)
		if n.kind == nodeCat:
			if reverse: return self.emit(n.b, self.emit(n.a, next))
			return self.emit(n.a, self.emit(n.b, next))
		if n.kind == nodeAlt:
			left = self.emit(n.a, next)
			return self.split(left, self.emit(n.b, next), false)
		if n.kind == nodeStar: return self.star(n.a, next, n.lazy)
		if n.kind == nodePlus: return self.star(n.a, next, n.lazy, true)
		if n.kind == nodeQuest:
			body = self.emit(n.a, next)
			return self.split(body, next, n.lazy)
		if n.kind == nodeBound: return self.state(stBound, next, n.a)
		if n.kind == nodeGroup:
			if not saves: return self.emit(n.a, next)
			close = self.state(stSave, next, 2 * n.b + 1)
			return self.state(stSave, self.emit(n.a, close), 2 * n.b)
		if n.kind == nodeHead: return self.state(stTail if reverse else stHead, next, 0)
		if n.kind == nodeTail: return self.state(stHead if reverse else stTail, next, 0)
		# a repetition: the optional copies nested, then the required ones before them
		tail = next
		if n.c < 0:
			tail = self.star(n.a, next, n.lazy)
		else:
			loop n.c - n.b:
				gate = self.state(stSplit, 0, 0)
				body = self.emit(
					n.a,
					self.state(stLoopBack, tail, next, gate) if tail != next else tail
				)
				nfa.x[gate] = next if n.lazy else body
				nfa.y[gate] = body if n.lazy else next
				tail = gate
		loop n.b:
			tail = self.emit(n.a, tail)
		tail

# The NFA of the pattern: forward, with a lazy `.*` before it so that a scan finds a match
# anywhere (`unanchored`), or for the reversed pattern, run backwards from where a match ends; with
# `saves`, the positions of the groups are saved (the automata that find a match have no use for them).
fn buildNfa(p Parser, reverse bool, unanchored bool, saves bool = false) Nfa ? str:
	b = Builder(
		nodes = p.nodes.copy(),
		classCodes = p.classCodes.copy(),
		classEnds = p.classEnds.copy(),
		nfa = Nfa(sets = p.sets.copy()), reverse, saves)
	entry = b.emit(p.root, b.state(stAdvance, 0, 0))
	if unanchored:
		any = b.nfa.sets.len / 256
		b.nfa.sets.extend(fill(256, 1))
		loop_ = b.state(stSplit, entry, 0)
		step = b.state(stByte, any, loop_)
		b.nfa.y[loop_] = step
		b.nfa.start = loop_
	else:
		b.nfa.start = entry
	if not b.error.isEmpty: return b.error
	b.nfa.reverse = reverse
	b.nfa.trailing = p.hasTail and not p.multiline
	if b.nfa.trailing and not reverse:
		b.nfa.trailBefore = b.state(stTrailBefore, 0, 0)
		b.nfa.trailAfter = b.state(stTrailAfter, 0, 0)
	if p.multiline or b.nfa.trailing:
		b.nfa.lines = p.multiline
		newline u8[] = zeros(256)
		newline[10] = 1
		b.nfa.sets.extend(newline)
	if p.hasBounds:
		b.nfa.bounds = true
		b.nfa.asciiBounds = p.asciiOnly
		b.nfa.quits = not p.asciiOnly
		word u8[] = zeros(256)
		for c in 0..256:
			if isWordByte(c): word[c] = 1
		b.nfa.sets.extend(word)
		if b.nfa.quits:
			high u8[] = zeros(256)
			for c in 0x80..256:
				high[c] = 1
			b.nfa.sets.extend(high)
	b.nfa.classify()
	b.nfa
