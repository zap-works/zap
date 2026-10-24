# The parsed pattern as a Thompson NFA, built backwards: `emit(node, next)` gives the state that
# runs the node and then goes to `next`. A split lists its two targets in priority order (the
# preferred first), which is what leftmost-first matching reads. State 0 is the match.

stByte = 0   # x: the set, y: the next state
stSplit = 1   # x: the preferred next state, y: the other
stMatch = 2
stHead = 3   # x: the next state, taken at the start of the scan
stTail = 4   # x: the next state, taken at its end

maxStates = 200_000

type Nfa:
	kind i64[] = [stMatch]
	x i64[] = [0]
	y i64[] = [0]
	start i64 = 0
	sets u8[] = []   # 256 bytes a set
	classOf u8[] = []   # the class of each byte: bytes no set tells apart share one
	reps i64[] = []   # a byte of each class
	classes i64 = 0
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
	nfa Nfa
	reverse bool   # the automaton of the reversed pattern, to be run backwards
	error str = ""

	fn state(kind i64, x i64, y i64):
		if nfa.kind.len >= maxStates:
			if error.isEmpty: error = "regex: the pattern needs too many states"
			return 0
		nfa.kind.push(kind)
		nfa.x.push(x)
		nfa.y.push(y)
		nfa.kind.len - 1

	# a split to a and b, the lazy form preferring b
	mut fn split(a i64, b i64, lazy bool) i64:
		if lazy: return self.state(stSplit, b, a)
		self.state(stSplit, a, b)

	mut fn star(child i64, next i64, lazy bool):
		loop_ = self.state(stSplit, 0, 0)
		body = self.emit(child, loop_)
		nfa.x[loop_] = next if lazy else body
		nfa.y[loop_] = body if lazy else next
		loop_

	fn emit(node i64, next i64) i64:
		n = nodes[node]
		if n.kind == nodeEmpty: return next
		if n.kind == nodeSet: return self.state(stByte, n.a, next)
		if n.kind == nodeCat:
			if reverse: return self.emit(n.b, self.emit(n.a, next))
			return self.emit(n.a, self.emit(n.b, next))
		if n.kind == nodeAlt:
			left = self.emit(n.a, next)
			return self.split(left, self.emit(n.b, next), false)
		if n.kind == nodeStar: return self.star(n.a, next, n.lazy)
		if n.kind == nodePlus:
			loop_ = self.state(stSplit, 0, 0)
			body = self.emit(n.a, loop_)
			nfa.x[loop_] = next if n.lazy else body
			nfa.y[loop_] = body if n.lazy else next
			return body
		if n.kind == nodeQuest:
			body = self.emit(n.a, next)
			return self.split(body, next, n.lazy)
		if n.kind == nodeHead: return self.state(stTail if reverse else stHead, next, 0)
		if n.kind == nodeTail: return self.state(stHead if reverse else stTail, next, 0)
		# a repetition: the optional copies nested, then the required ones before them
		tail = next
		if n.c < 0:
			tail = self.star(n.a, next, n.lazy)
		else:
			loop n.c - n.b:
				body = self.emit(n.a, tail)
				tail = self.split(body, next, n.lazy)
		loop n.b:
			tail = self.emit(n.a, tail)
		tail

# The NFA of the pattern: forward, with a lazy `.*` before it so that a scan finds a match
# anywhere (`unanchored`), or for the reversed pattern, run backwards from where a match ends.
fn buildNfa(p Parser, reverse bool, unanchored bool) Nfa ? str:
	b = Builder(nodes = p.nodes.copy(), nfa = Nfa(sets = p.sets.copy()), reverse)
	entry = b.emit(p.root, 0)
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
	if p.multiline:
		b.nfa.lines = true
		newline u8[] = zeros(256)
		newline[10] = 1
		b.nfa.sets.extend(newline)
	b.nfa.classify()
	b.nfa
