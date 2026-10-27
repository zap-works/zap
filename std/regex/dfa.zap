# A lazy DFA over an NFA: a state is the ordered list of NFA states a scan can be in, made when
# the scan first reaches it and kept in a table (a byte class a column, the end of the text one
# more). In `ordered` mode the list is cut where it reaches the match, so what is found is the
# match a backtracking engine would find (leftmost, then the preferred branch of each choice);
# otherwise every thread goes on and the longest match is found. A scan costs a table read a
# byte whatever the pattern; the table is emptied if it grows past `cap` states.
#
# A state also knows, when its list waits on the next byte (a `$` before a newline, a word's edge),
# whether the byte before was a word byte and whether it stood at the start of a line. Such a wait
# is settled when the next byte is read, so a match it lets hold ended one byte before: the state
# that byte leads to is flagged `lagging`, and a scan takes the match's end from the position before.

type Dfa:
	nfa Nfa
	ordered bool
	rejectEmpty bool = false   # the match must not be empty: a scan that has read no byte has not reached it
	shift i64 = 0   # a row of the table has 1 << shift columns: the classes, then (last) the end of the
	# text, so a state is found by a shift
	stride i64 = 0
	trans i32[] = []   # state * stride + column: -1 not made yet, else the next state, as an offset into
	# this table (state * stride) when it is plain, and as -(state + 2) when it holds the match or is
	# the dead state: a scan takes the plain case without looking at the state
	matching u8[] = []   # 1 for a state whose list holds the match
	flags u8[] = []   # a state's flags: lagging, after a word byte, at the start of a line
	at i64[] = []   # where a state's list starts in `members`
	size i64[] = []   # and its length
	members i64[] = []
	index {str: i64} = {}
	starts i64[] = [-1, -1, -1, -1]   # the start states: at the start of a line, after a non-word byte, after a word byte, before a final newline
	seen i64[] = []   # the generation that last reached an NFA state
	generation i64 = 0
	stack i64[] = []
	reached bool = false   # whether the last closure came to the match
	cap i64 = 3_000   # at most 1 << stateBits
	stopped i64 = 0   # where the last forward scan stopped reading

	# the table emptied but for the dead state (0), whose list is empty
	fn reset():
		trans.clear()
		matching.clear()
		flags.clear()
		at.clear()
		size.clear()
		members.clear()
		index.clear()
		starts = [-1, -1, -1, -1]
		self.intern([], 0)
		for c in 0..stride:
			trans[c] = -2
		if nfa.quits:
			# state 1, where a scan stops that has read a byte it cannot judge
			at.push(members.len)
			size.push(0)
			flags.push(0)
			matching.push(0)
			trans.extend(fill(stride, -3))

	# The state of the list and the flags, made when new. A list that waits on no word's edge has
	# no use for the word and line flags.
	fn intern(list i64[], flags0 i64):
		hit = 0
		waits = false
		for q in list:
			if nfa.kind[q] == stMatch: hit = 1
			if nfa.kind[q] == stBound or ((nfa.bounds or rejectEmpty or nfa.trailing) and nfa.kind[q] == stTail):
				waits = true
		f = flags0 if waits else (flags0 & (flagLagging | flagTrail | flagTextEnd))
		key = "{f}:{list.map("{it}").join(",")}"
		if index.get(key) is known: return known
		id = at.len
		at.push(members.len)
		size.push(list.len)
		members.extend(list)
		flags.push(u8(f))
		matching.push(hit)
		trans.extend(fill(stride, -1))
		index[key.copy()] = id
		id

	# q and what it reaches without a byte, in priority order, added to the list; true when the
	# match is reached in `ordered` mode (what has less priority is not added). `prev` tells
	# whether the byte before is a word byte, `next` whether the byte after is (-1 when it is not known yet,
	# and a word's edge waits).
	fn close(q0 i64, atHead bool, atTail bool, atStart bool, prev i64, next i64, mut list i64[]):
		stack.clear()
		stack.push(q0)
		while stack.pop() is q:
			if seen[q] == generation and nfa.kind[q] != stLoopBack: continue
			seen[q] = generation
			kind = nfa.kind[q]
			if kind == stByte:
				list.push(q)
			elif kind == stMatch:
				list.push(q)
				reached = true
				if ordered: return true
			elif kind == stSplit:
				stack.push(nfa.y[q])
				stack.push(nfa.x[q])
			elif kind == stAdvance:
				if not atStart: stack.push(nfa.x[q])
			elif kind == stLoopBack:
				stack.push(nfa.y[q] if seen[nfa.z[q]] == generation else nfa.x[q])
			elif kind == stHead:
				if atHead: stack.push(nfa.x[q])
			elif kind == stBound:
				if next < 0:
					list.push(q)
				elif (prev != next) == (nfa.y[q] == 0):
					stack.push(nfa.x[q])
			elif atTail:
				stack.push(nfa.x[q])
			else:
				list.push(q)   # a $ waits for the end of the text
		false

	# the start state of a kind: 0 at the start of a line, 1 after a non-word byte, 2 after a word
	# byte, 3 (the reversed pattern's, from the end of a match) at the end of the text but for its newline
	fn startAt(kind i64):
		if starts[kind] >= 0: return starts[kind]
		generation += 1
		list = []
		self.close(nfa.start, kind == 0 or kind == 3, false, rejectEmpty, 1 if kind == 2 else 0, -1, list)
		id = self.intern(list, (flagHead if kind == 0 else 0) | (flagWord if kind == 2 else 0) |
			(flagStart if rejectEmpty else 0) | (flagTextEnd if kind == 0 and nfa.reverse and nfa.trailing else 0))
		starts[kind] = id
		id

	# the kind of start state for a scan beginning after `before`, the byte before it (-1 at the start
	# of the text); `last` tells that `before` is the text's last byte, which a `$` may stand before
	fn startKind(before i64, last bool = false):
		if before < 0 or (nfa.lines and before == 10): return 0
		if before == 10 and last and nfa.trailing and nfa.reverse: return 3
		if nfa.bounds and isWordByte(before): return 2
		1

	# The entry of the table that goes to state t. A scan reads a plain entry without looking at
	# the state; one that is dead, holds the match or is lagging is never plain.
	fn encoded(t i64) i32:
		if size[t] == 0 or matching[t] == 1 or (flags[t] & flagLagging) != 0: return i32(-(t + 2))
		i32(t << shift)

	# The members of state s once what waits on the next byte (rep, -1 at the end of the text) is
	# settled, in priority order, cut where the match is reached when `ordered`; `reached` tells whether
	# a wait let the match hold.
	fn settled(s i64, rep i64, endsLine bool):
		list = []
		reached = false
		prev = (flags[s] >> 1) & 1
		atStart = (flags[s] & flagStart) != 0
		next = 1 if rep >= 0 and isWordByte(rep) else 0
		for k in at[s]..at[s] + size[s]:
			q = members[k]
			kind = nfa.kind[q]
			if kind == stTail:
				if endsLine and self.close(nfa.x[q], (flags[s] & flagHead) != 0, true, atStart, prev, next, list): break
				if not endsLine and nfa.trailing and rep == 10: list.push(q)
			elif kind == stBound:
				holds = (prev != next) == (nfa.y[q] == 0)
				if holds and
					self.close(nfa.x[q], (flags[s] & flagHead) != 0, endsLine, atStart, prev, next, list):
					break
			else:
				list.push(q)
		generation += 1
		list

	# What a `$` waiting in the state s leaves when the byte just read is a newline: the marker of a
	# match that ends before the newline or after it, taken if the text ends there; -1 for none.
	fn trailMarker(q i64, s i64):
		generation += 1
		first = []
		self.close(nfa.x[q], (flags[s] & flagHead) != 0, true, rejectEmpty and (flags[s] & flagStart) != 0,
			(flags[s] >> 1) & 1, 0, first)
		for m in first:
			if nfa.kind[m] == stMatch: return nfa.trailBefore
			if nfa.kind[m] == stByte and nfa.sets[nfa.x[m] * 256 + 10] == 1:
				second = []
				generation += 1
				self.close(nfa.y[m], false, true, false, 0, 0, second)
				if second.any(nfa.kind[it] == stMatch): return nfa.trailAfter
		-1

	# the state after state s reads column c (the end of the text when c is the last)
	fn step(s i64, c i64):
		generation += 1
		list = []
		done = false
		atEnd = c == stride - 1
		rep = -1 if atEnd else nfa.reps[c]
		if nfa.quits and rep >= 0x80:
			trans[(s << shift) + c] = -3
			return 1
		endsLine = atEnd or (nfa.lines and rep == 10)
		waiting = endsLine or nfa.bounds
		passed = self.settled(s, rep, endsLine) if waiting else []
		lagging = waiting and reached and not atEnd
		word = 1 if rep >= 0 and isWordByte(rep) else 0
		trailMatch = false
		trails = []
		if nfa.trailing and rep == 10 and not nfa.reverse:
			for k in 0..(passed.len if waiting else size[s]):
				q = passed[k] if waiting else members[at[s] + k]
				trails.push(self.trailMarker(q, s) if nfa.kind[q] == stTail else -1)
			generation += 1
		newlineEndsText = nfa.reverse and rep == 10 and (flags[s] & flagTextEnd) != 0
		for k in 0..(passed.len if waiting else size[s]):
			if done: break
			q = passed[k] if waiting else members[at[s] + k]
			kind = nfa.kind[q]
			if atEnd:
				if kind in [stMatch, stTrailBefore, stTrailAfter]:
					list.push(0)
					trailMatch = kind == stTrailBefore
					done = ordered
			elif kind == stByte and nfa.sets[nfa.x[q] * 256 + rep] == 1:
				done = self.close(nfa.y[q], nfa.lines and rep == 10 or newlineEndsText, false, false, word, -1, list)
			elif kind == stTail and not trails.isEmpty and trails[k] >= 0:
				list.push(trails[k])
		f = (flagLagging if lagging else 0) | (flagTrail if trailMatch else 0)
		if not atEnd and nfa.bounds:
			f |= flagWord if word == 1 else 0
			f |= flagHead if nfa.lines and rep == 10 else 0
		flushed = at.len >= cap
		if flushed:
			self.reset()
		t = self.intern(list, f)
		if not flushed: trans[(s << shift) + c] = self.encoded(t)
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

	# where the match found from `from` ends: the last position at which the state holds the match,
	# -1 for none, `quit` when the scan could not judge a byte
	fn lastEnd(text u8[], from i64):
		if nfa.quits and from > 0 and text[from - 1] >= 0x80: return quit
		s = self.startAt(self.startKind(text[from - 1] if from > 0 else -1))
		last = -1
		if matching[s] == 1: last = from
		i = from
		n = text.len
		loop:
			ran = self.scanForward(text, i, s)
			i = ran >> stateBits
			s = ran & ((1 << stateBits) - 1)
			if i >= n: break
			c = i64(nfa.classOf[text[i]])
			i += 1
			v = i64(trans[(s << shift) + c])   # the scan stopped here: not plain, a state known or not
			s = self.step(s, c) if v == -1 else -v - 2
			if nfa.quits and s == 1: return quit
			if (flags[s] & flagLagging) != 0: last = i - 1
			if matching[s] == 1:
				last = i
				if size[s] == 1:   # nothing but the match is left: no byte can change it
					stopped = i
					return last
			if size[s] == 0:
				stopped = i
				return last
		stopped = n
		s = self.go(s, stride - 1)
		if matching[s] == 1: last = n - (flags[s] & flagTrail) / flagTrail
		last

	# where the match that ends at `end` starts: this DFA is the reversed pattern's, scanned
	# backwards over text[from..end]; the lowest position at which the state holds the match
	mut fn firstStart(text u8[], from i64, end i64):
		if nfa.quits and ((end < text.len and text[end] >= 0x80) or (from > 0 and text[from - 1] >= 0x80)): return quit
		s = self.startAt(self.startKind(text[end] if end < text.len else -1, end == text.len - 1))
		best = -1
		if matching[s] == 1: best = end
		i = end
		loop:
			ran = self.scanBackward(text, i, s, from)
			i = ran >> stateBits
			s = ran & ((1 << stateBits) - 1)
			if i <= from: break
			i -= 1
			s = self.go(s, nfa.classOf[text[i]])
			if nfa.quits and s == 1: return quit
			if (flags[s] & flagLagging) != 0: best = i + 1
			if matching[s] == 1: best = i
			if size[s] == 0: return best
		# what waits on the byte before `from` is settled by it
		if from == 0:
			if matching[self.go(s, stride - 1)] == 1: best = from
		elif nfa.lines or nfa.bounds:
			if (flags[self.go(s, nfa.classOf[text[from - 1]])] & flagLagging) != 0: best = from
		best

	# which bytes can begin a match: a table of 256, then one more for the end of the text; all ones
	# when anything might, as when the pattern can match nothing
	mut fn startBytes() u8[]:
		table u8[] = zeros(257)
		for kind in 0..3:
			s = self.startAt(kind)
			if matching[s] == 1: return fill(257, 1)
			for k in at[s]..at[s] + size[s]:
				q = members[k]
				if nfa.kind[q] != stByte: return fill(257, 1)
				for b in 0..256:
					if nfa.sets[nfa.x[q] * 256 + b] == 1: table[b] = 1
		table

	# whether state s waits on the next byte: a match can end before any byte, or before none
	fn waits(s i64):
		(at[s]..at[s] + size[s]).any(
			nfa.kind[members[it]] == stBound or (nfa.lines and nfa.kind[members[it]] == stTail)
		)

	# which two bytes can begin a match: a table of 65536, first byte * 256 + second; ones for every
	# second byte after a first one that can end a match or wait for the end of the text
	mut fn startPairs() u8[]:
		table u8[] = zeros(65_536)
		for kind in 0..3:
			start = self.startAt(kind)
			if matching[start] == 1 or self.waits(start): return fill(65_536, 1)
			for c in 0..nfa.classes:
				s = self.go(start, c)
				if s == 0: continue
				second u8[] = zeros(256)
				any = matching[s] == 1 or (flags[s] & flagLagging) != 0 or (nfa.quits and s == 1)
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

fn newDfa(move nfa Nfa, ordered bool, rejectEmpty bool = false):
	n = nfa.kind.len
	d = Dfa(nfa, ordered, rejectEmpty, seen = zeros(n))
	d.shift = 1
	while (1 << d.shift) < d.nfa.classes + 1:
		d.shift += 1
	d.stride = 1 << d.shift
	d.reset()
	d

# what a scan gives instead of a position when it has stopped at a byte it cannot judge (a word's edge
# beside a byte that is not ASCII), so that the threads search the text
quit = -2

# A scan's result is packed in a word: the byte index above, the state below.
stateBits = 20

# the bits of a state's flags
flagLagging = 1
flagWord = 2
flagHead = 4
flagTrail = 16   # the match the state holds ends before the text's last byte
flagTextEnd = 32   # the reversed pattern's scan began at the end of the text
flagStart = 8   # the state is the start of a scan that rejects an empty match
