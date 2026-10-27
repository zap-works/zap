# The groups of a match, read by a Pike VM over the stretch of text the automata found: threads
# follow the pattern's NFA in step, in priority order, each with the positions it has saved, and
# the first thread to reach the match is the one a backtracking engine would take. Only a pattern
# with groups pays for it, and only over its matches.

# the threads at one position: a state each, with its saved positions in `slots`, `width` to a thread
type Threads:
	states i64[] = []
	slots i64[] = []
	seen i64[]
	generation i64 = 0
	stack i64[] = []   # what is left to follow: (0, state, 0) to visit a state, (1, slot, old) to put a slot back
	cur i64[] = []   # the slots of the path being followed
	rejectEmpty bool = false   # a path that has read no byte since the match began does not reach the match

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
				stack.extend([0, nfa.y[q] if seen[nfa.x[q]] == generation else nfa.x[q], 0])
			elif kind == stAdvance:
				if pos > cur[0] or not rejectEmpty: stack.extend([0, nfa.x[q], 0])
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
	before = pos > 0 and isWordByte(bytes[pos - 1])
	after = pos < bytes.len and isWordByte(bytes[pos])
	(before != after) == (nfa.y[q] == 0)

fn newThreads(nfa Nfa, width i64, rejectEmpty bool):
	Threads(seen = zeros(nfa.kind.len), cur = fill(width, -1), rejectEmpty)

# The positions of the groups in the match [start, end) of the text, from the NFA that saves them:
# slot 2g is where group g begins and 2g + 1 where it ends (group 0 is the whole match), -1 for a
# group that took no part.
fn captureSlots(nfa Nfa, groups i64, bytes u8[], start i64, end i64, rejectEmpty bool):
	width = 2 * (groups + 1)
	lists = [nfa.newThreads(width, rejectEmpty), nfa.newThreads(width, rejectEmpty)]
	now = 0
	lists[0].cur[0] = start
	lists[0].clear()
	lists[0].follow(nfa, bytes, nfa.start, start)
	found = []
	pos = start
	loop:
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
		if pos >= end or lists[later].states.isEmpty: break
		now = later
		pos += 1
	found
