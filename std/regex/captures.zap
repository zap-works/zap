# The groups of a match, read by a Pike VM over the stretch of text the automata found: threads
# follow the pattern's NFA in step, in priority order, each with the positions it has saved, and
# the first thread to reach the match is the one a backtracking engine would take. Only a pattern
# with groups pays for it, and only over its matches. The same threads search a text for a match
# where the automata cannot: a word's edge beside a character that is not ASCII (the automata judge
# edges by bytes), which only the threads tell by the whole character.

# the threads at one position: a state each, with its saved positions in `slots`, `width` to a thread
type Threads:
	states i64[] = []
	slots i64[] = []
	seen i64[]
	generation i64 = 0
	stack i64[] = []   # what is left to follow: (0, state, 0) to visit a state, (1, slot, old) to put a slot back
	cur i64[] = []   # the slots of the path being followed
	rejectFrom i64 = -1   # a path that began here and has read no byte does not reach the match

	# the threads dropped, for the next position
	fn clear():
		states.clear()
		slots.clear()
		generation += 1

	# The state q0 and what it reaches without a byte, at position pos, added as threads in priority
	# order with the slots their paths saved; a state a thread reached before is not reached again.
	fn follow(nfa Nfa, bytes u8[], q0 i64, pos i64):
		stack.clear()
		stack.extend([0, q0, 0])
		while not stack.isEmpty:
			arg = stack.pop() ?? 0
			q = stack.pop() ?? 0
			tag = stack.pop() ?? 0
			if tag == 1:
				cur[q] = arg
				continue
			if seen[q] == generation and nfa.kind[q] != stLoopBack: continue
			seen[q] = generation
			kind = nfa.kind[q]
			if kind == stByte or kind == stMatch:
				states.push(q)
				slots.extend(cur)
			elif kind == stSplit:
				stack.extend([0, nfa.y[q], 0, 0, nfa.x[q], 0])
			elif kind == stLoopBack:
				stack.extend([0, nfa.y[q] if seen[nfa.z[q]] == generation else nfa.x[q], 0])
			elif kind == stAdvance:
				if pos > cur[0] or cur[0] != rejectFrom: stack.extend([0, nfa.x[q], 0])
			elif kind == stSave:
				slot = nfa.y[q]
				stack.extend([1, slot, cur[slot], 0, nfa.x[q], 0])
				cur[slot] = pos
			elif nfa.holdsAt(q, bytes, pos):
				stack.extend([0, nfa.x[q], 0])

# whether the `^`, `$` or word's edge of state q holds at position pos of the text
fn holdsAt(nfa Nfa, q i64, bytes u8[], pos i64):
	kind = nfa.kind[q]
	if kind == stHead: return pos == 0 or (nfa.lines and bytes[pos - 1] == 10)
	if kind == stTail:
		return pos == bytes.len or ((nfa.lines or nfa.trailing) and bytes[pos] == 10 and
			(nfa.lines or pos == bytes.len - 1))
	before = pos > 0 and wordBefore(bytes, pos, nfa.asciiBounds)
	after = pos < bytes.len and wordAt(bytes, pos, nfa.asciiBounds)
	(before != after) == (nfa.y[q] == 0)

fn newThreads(nfa Nfa, width i64, rejectFrom i64):
	Threads(seen = zeros(nfa.kind.len), cur = fill(width, -1), rejectFrom)

# The positions of the groups in the match [start, end) of the text, from the NFA that saves them:
# slot 2g is where group g begins and 2g + 1 where it ends (group 0 is the whole match), -1 for a
# group that took no part. With `rejectEmpty` a match that is empty is none.
fn captureSlots(nfa Nfa, groups i64, bytes u8[], start i64, end i64, rejectEmpty bool):
	nfa.threadSlots(groups, bytes, start, end, start if rejectEmpty else -1, false)

# The positions of the groups of the first match at or after `from`, the whole match first; empty
# when there is none. With `rejectEmpty` the match that begins at `from` may not be empty.
fn searchSlots(nfa Nfa, groups i64, bytes u8[], from i64, rejectEmpty bool):
	nfa.threadSlots(groups, bytes, from, bytes.len, from if rejectEmpty else -1, true)

# The threads from `from` to `end`: those of a match that begins at `from`, or, when `search`, of one
# that begins anywhere after it (a new thread each position, after those of the matches begun
# before, until one matches).
fn threadSlots(nfa Nfa, groups i64, bytes u8[], from i64, end i64, rejectFrom i64, search bool):
	width = 2 * (groups + 1)
	lists = [nfa.newThreads(width, rejectFrom), nfa.newThreads(width, rejectFrom)]
	now = 0
	lists[0].clear()
	found = []
	pos = from
	loop:
		if pos == from or (search and found.isEmpty and (pos >= bytes.len or (bytes[pos] & 0xC0) != 0x80)):
			lists[now].cur = fill(width, -1)
			lists[now].cur[0] = pos
			lists[now].follow(nfa, bytes, nfa.start, pos)
		later = 1 - now
		lists[later].clear()
		for t in 0..lists[now].states.len:
			q = lists[now].states[t]
			mine = lists[now].slots[t * width..(t + 1) * width]
			if nfa.kind[q] == stMatch:
				found = mine.copy()
				found[1] = pos
				break
			if pos < end and nfa.sets[nfa.x[q] * 256 + bytes[pos]] == 1:
				lists[later].cur = mine.copy()
				lists[later].follow(nfa, bytes, nfa.y[q], pos + 1)
		if pos >= end or (lists[later].states.isEmpty and not (search and found.isEmpty)): break
		now = later
		pos += 1
	found
