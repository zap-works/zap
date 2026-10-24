# A lazy DFA over an NFA: a state is the ordered list of NFA states a scan can be in, made when
# the scan first reaches it and kept in a table (a byte class a column, the end of the text one
# more). In `ordered` mode the list is cut where it reaches the match, so what is found is the
# match a backtracking engine would find (leftmost, then the preferred branch of each choice);
# otherwise every thread goes on and the longest match is found. A scan costs a table read a
# byte whatever the pattern; the table is emptied if it grows past `cap` states.

type Dfa:
	nfa Nfa
	ordered bool
	shift i64 = 0   # a row of the table has 1 << shift columns: the classes, then (last) the end of the
	# text, so a state is found by a shift
	stride i64 = 0
	trans i32[] = []   # state * stride + column: -1 not made yet, else the next state, as an offset into
	# this table (state * stride) when it is plain, and as -(state + 2) when it holds the match or is
	# the dead state: a scan takes the plain case without looking at the state
	matching u8[] = []   # 1 for a state whose list holds the match
	at i64[] = []   # where a state's list starts in `members`
	size i64[] = []   # and its length
	members i64[] = []
	index {str: i64} = {}
	starts i64[] = [-1, -1]
	seen i64[] = []   # the generation that last reached an NFA state
	generation i64 = 0
	stack i64[] = []
	cap i64 = 3_000   # at most 1 << stateBits
	stopped i64 = 0   # where the last forward scan stopped reading

	# the table emptied but for the dead state (0), whose list is empty
	fn reset():
		trans.clear()
		matching.clear()
		at.clear()
		size.clear()
		members.clear()
		index.clear()
		starts = [-1, -1]
		self.intern([])
		for c in 0..stride:
			trans[c] = -2

	# the state of the list, made when new
	fn intern(list i64[]):
		key = list.map("{it}").join(",")
		if index.get(key) is known: return known
		id = at.len
		at.push(members.len)
		size.push(list.len)
		members.extend(list)
		hit = 0
		for q in list:
			if nfa.kind[q] == stMatch: hit = 1
		matching.push(hit)
		trans.extend(fill(stride, -1))
		index[key.copy()] = id
		id

	# q and what it reaches without a byte, in priority order, added to the list; true when the
	# match is reached in `ordered` mode (what has less priority is not added)
	fn close(q0 i64, atHead bool, atTail bool, mut list i64[]):
		stack.clear()
		stack.push(q0)
		while stack.pop() is q:
			if seen[q] == generation: continue
			seen[q] = generation
			kind = nfa.kind[q]
			if kind == stByte:
				list.push(q)
			elif kind == stMatch:
				list.push(q)
				if ordered: return true
			elif kind == stSplit:
				stack.push(nfa.y[q])
				stack.push(nfa.x[q])
			elif kind == stHead:
				if atHead: stack.push(nfa.x[q])
			elif atTail:
				stack.push(nfa.x[q])
			else:
				list.push(q)   # a $ waits for the end of the text
		false

	# the start state: with the text's start behind it, or not
	fn startState(atHead bool):
		k = 0 if atHead else 1
		if starts[k] >= 0: return starts[k]
		generation += 1
		list = []
		self.close(nfa.start, atHead, false, list)
		id = self.intern(list)
		starts[k] = id
		id

	# The entry of the table that goes to state t after column c. A scan reads a plain entry
	# without looking at the state; a newline, in a pattern whose `^` and `$` hold at the ends of
	# lines, is never plain: the scan stops there to see whether a `$` holds before it.
	fn encoded(t i64, c i64) i32:
		if t == 0 or matching[t] == 1 or (nfa.lines and c == nfa.classOf[10]): return i32(-(t + 2))
		i32(t << shift)

	# The members of state s with the `$` states passed (what is next is a newline or the end),
	# in priority order, cut where the match is reached when `ordered`.
	fn tailsPassed(s i64):
		list = []
		for k in at[s]..at[s] + size[s]:
			q = members[k]
			if nfa.kind[q] != stTail:
				list.push(q)
			elif self.close(nfa.x[q], false, true, list):
				break
		generation += 1
		list

	# the state after state s reads column c (the end of the text when c is the last)
	fn step(s i64, c i64):
		generation += 1
		list = []
		done = false
		atEnd = c == stride - 1
		rep = 0 if atEnd else nfa.reps[c]
		# before a newline the `$` states hold: they are passed first
		passed = self.tailsPassed(s) if nfa.lines and rep == 10 else []
		n = passed.len if nfa.lines and rep == 10 else size[s]
		for k in 0..n:
			if done: break
			q = passed[k] if nfa.lines and rep == 10 else members[at[s] + k]
			kind = nfa.kind[q]
			if atEnd:
				if kind == stTail:
					done = self.close(nfa.x[q], false, true, list)
				elif kind == stMatch:
					list.push(q)
					done = ordered
			elif kind == stByte and nfa.sets[nfa.x[q] * 256 + rep] == 1:
				done = self.close(nfa.y[q], nfa.lines and rep == 10, false, list)
		flushed = at.len >= cap
		if flushed:
			self.reset()
		t = self.intern(list)
		if not flushed: trans[(s << shift) + c] = self.encoded(t, c)
		t

	# the state after state s reads column c
	mut fn go(s i64, c i64):
		v = i64(trans[(s << shift) + c])
		if v >= 0: return v >> shift
		if v == -1: return self.step(s, c)
		-v - 2

	# The plain transitions followed from text[i] with the table in hand (nothing is looked up
	# through the automaton) from state s: the index of the first byte whose entry is not plain (or
	# n) and the state before it.
	fn scanForward(text u8[], i0 i64, s0 i64):
		i = i0
		o = s0 << shift
		n = text.len
		while i < n:
			v = i64(trans[o + nfa.classOf[text[i]]])
			if v < 0: break
			o = v
			i += 1
		(i << stateBits) | (o >> shift)

	# the same, backwards: text[i - 1] is the next byte; the index is that of the first byte whose
	# entry is not plain, plus one, or `stop`
	fn scanBackward(text u8[], i0 i64, s0 i64, stop i64):
		i = i0
		o = s0 << shift
		while i > stop:
			v = i64(trans[o + nfa.classOf[text[i - 1]]])
			if v < 0: break
			o = v
			i -= 1
		(i << stateBits) | (o >> shift)

	# the start state, from its cache where it is there
	mut fn startAt(atHead bool) i64:
		s = starts[0 if atHead else 1]
		if s >= 0: return s
		self.startState(atHead)

	# where the match found from `from` ends: the last position at which the state holds the match,
	# -1 for none
	fn lastEnd(text u8[], from i64):
		s = self.startAt(from == 0 or (nfa.lines and text[from - 1] == 10))
		last = -1
		if matching[s] == 1: last = from
		i = from
		n = text.len
		loop:
			ran = self.scanForward(text, i, s)
			i = ran >> stateBits
			s = ran & ((1 << stateBits) - 1)
			if i >= n: break
			if nfa.lines and text[i] == 10 and matching[self.go(s, stride - 1)] == 1: last = i
			c = i64(nfa.classOf[text[i]])
			i += 1
			v = i64(trans[(s << shift) + c])   # the scan stopped here: not plain, a state known or not
			s = self.step(s, c) if v == -1 else -v - 2
			if matching[s] == 1:
				last = i
				if size[s] == 1:   # nothing but the match is left: no byte can change it
					stopped = i
					return last
			if s == 0:
				stopped = i
				return last
		stopped = n
		s = self.go(s, stride - 1)
		if matching[s] == 1: last = n
		last

	# where the match that ends at `end` starts: this DFA is the reversed pattern's, scanned
	# backwards over text[from..end]; the lowest position at which the state holds the match
	mut fn firstStart(text u8[], from i64, end i64):
		s = self.startAt(end == text.len or (nfa.lines and text[end] == 10))
		best = -1
		if matching[s] == 1: best = end
		i = end
		loop:
			ran = self.scanBackward(text, i, s, from)
			i = ran >> stateBits
			s = ran & ((1 << stateBits) - 1)
			if i <= from: break
			i -= 1
			if nfa.lines and text[i] == 10 and matching[self.go(s, stride - 1)] == 1: best = i + 1
			c = i64(nfa.classOf[text[i]])
			s = self.go(s, c)
			if matching[s] == 1: best = i
			if s == 0: return best
		if from == 0 or (nfa.lines and text[from - 1] == 10):
			s = self.go(s, stride - 1)
			if matching[s] == 1: best = from
		best

	# which bytes can begin a match: a table of 256, then one more for the end of the text; all ones
	# when anything might, as when the pattern can match nothing
	mut fn startBytes() u8[]:
		table u8[] = zeros(257)
		for atHead in [true, false]:
			s = self.startState(atHead)
			if matching[s] == 1: return fill(257, 1)
			for k in at[s]..at[s] + size[s]:
				q = members[k]
				if nfa.kind[q] != stByte: return fill(257, 1)
				for b in 0..256:
					if nfa.sets[nfa.x[q] * 256 + b] == 1: table[b] = 1
		table

	# whether state s waits for a `$`, which a newline next lets hold: a match can end before any byte
	fn waitsForTail(s i64):
		(at[s]..at[s] + size[s]).any(nfa.kind[members[it]] == stTail)

	# which two bytes can begin a match: a table of 65536, first byte * 256 + second; ones for every
	# second byte after a first one that can end a match or wait for the end of the text
	mut fn startPairs() u8[]:
		table u8[] = zeros(65_536)
		for atHead in [true, false]:
			start = self.startAt(atHead)
			if matching[start] == 1: return fill(65_536, 1)
			if nfa.lines and self.waitsForTail(start): return fill(65_536, 1)
			for c in 0..nfa.classes:
				s = self.go(start, c)
				if s == 0: continue
				second u8[] = zeros(256)
				any = matching[s] == 1
				for k in at[s]..at[s] + size[s]:
					q = members[k]
					if nfa.kind[q] != stByte:
						any = true
					else:
						for b in 0..256:
							if nfa.sets[nfa.x[q] * 256 + b] == 1: second[b] = 1
				for first in 0..256:
					if nfa.classOf[first] == c:
						for b in 0..256:
							if any or second[b] == 1: table[first * 256 + b] = 1
		table

fn newDfa(move nfa Nfa, ordered bool):
	n = nfa.kind.len
	d = Dfa(nfa, ordered, seen = zeros(n))
	d.shift = 1
	while (1 << d.shift) < d.nfa.classes + 1:
		d.shift += 1
	d.stride = 1 << d.shift
	d.reset()
	d

# A scan's result is packed in a word: the byte index above, the state below.
stateBits = 20
