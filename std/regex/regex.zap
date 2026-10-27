# Regular expressions over bytes, matched without backtracking: a lazy DFA reads the text once,
# whatever the pattern, so a match costs time proportional to the text. `import regex`, then
# `re = regex.compile("[ab]+c") ?? fail(error)`, `re.find(text)`, `re.count(text)`,
# `re.replace(text, "-")`. The syntax is in parse.zap; a match is the leftmost one, and of those
# the one a backtracking engine would take (the first branch of each `|`, greedy unless `?`
# follows). The flags `(?i)`, `(?m)` and `(?s)` lead a pattern (parse.zap).
# A match has the groups of `(...)` and `(?P<name>...)`: `m.group(1)`, `m.named("name")`, and a
# replacement may write them (template.zap): `re.replace(text, r"io.\1(")`. A pattern without
# groups is matched by the automata alone; one with groups has a second pass read them, over the
# match the automata found.
# A Regex builds its tables as it matches, so it is `mut`: a
# thread uses its own (compile one per thread).

# a match: the bytes [start, end) of the text, and its groups
pub type Match:
	start i64
	end i64
	text str   # the matched bytes
	cuts i64[]   # where group g lies in `text`: from cuts[2g] to cuts[2g + 1], -1 when it took no part
	names str[]   # the names of the groups from the first, "" for one without

	# Group g of the match (0 is the whole of it); none when it took no part or there is no such group.
	pub fn group(g i64) ref str?:
		if g < 0 or 2 * g + 1 >= cuts.len or cuts[2 * g] < 0: return none
		text[cuts[2 * g]..cuts[2 * g + 1]]

	# The group of that name; none when it took no part or the pattern has none of the name.
	pub fn named(name str) ref str?:
		if names.indexOf(name) is k: return self.group(k + 1)
		none

# a compiled pattern: its forward automaton finds where a match ends, its reverse one where it
# starts, its anchored one the match at a given start; `prefilter` knows where a match can
# begin, so a search skips the other positions
pub type Regex:
	pattern str
	forward Dfa
	backward Dfa
	anchored Dfa
	nonEmpty Dfa   # the anchored one for a match that is not empty
	prefilter Prefilter
	captures Nfa   # the pattern's NFA that saves the groups' positions, left empty without groups
	groups i64
	names str[]
	matchStart i64 = 0   # where the match locate found starts
	emptyRejected bool = false   # whether that match is one found with an empty match refused
	cursor i64 = 0   # where the scan for the next match of a text begins
	cursorEmpty bool = false   # whether the match before it was empty, so no empty one is taken at the cursor

	# Where the first match of the bytes at or after `from` ends, -1 when there is none; where it
	# starts is left in `matchStart`. The bytes that cannot begin a match are skipped; then the match
	# at each candidate start is tried (the first that has one is the leftmost), as long as the
	# failed tries have read no more than the bytes passed over; after that the forward automaton
	# finds where the leftmost match ends and the reverse one where it starts, the whole text in one
	# pass whatever the pattern. With `skipEmpty` the match that begins at `from` may not be empty,
	# as Python's after an empty match: `|a` finds "" at 0 and then "a" at 0.
	fn locate(bytes u8[], from0 i64, skipEmpty bool):
		emptyRejected = false
		from = from0
		if skipEmpty:
			end = nonEmpty.lastEnd(bytes, from)
			if end == quit: return self.locateByThreads(bytes, from0, skipEmpty)
			if end >= 0:
				matchStart = from
				emptyRejected = true
				return end
			if from >= bytes.len: return -1
			from = nextBoundary(bytes, from)
		n = bytes.len
		p = from
		wasted = 0
		while wasted <= p - from + 32 and p <= n:
			p = prefilter.skip(bytes, p)
			if p >= n and prefilter.canStart[256] == 0: return -1
			end = anchored.lastEnd(bytes, p)
			if end == quit: return self.locateByThreads(bytes, from0, skipEmpty)
			if end >= 0:
				matchStart = p
				return end
			wasted += anchored.stopped - p + 9
			p = nextBoundary(bytes, p)
		if p > n: return -1
		end = forward.lastEnd(bytes, p)
		if end == quit: return self.locateByThreads(bytes, from0, skipEmpty)
		if end < 0: return -1
		matchStart = backward.firstStart(bytes, p, end)
		if matchStart == quit: return self.locateByThreads(bytes, from0, skipEmpty)
		end

	# The same search by the threads alone, which judge a word's edge by the whole character; for the
	# stretch of text a scan gave up at.
	fn locateByThreads(bytes u8[], from i64, skipEmpty bool):
		slots = (captures if groups > 0 else anchored.nfa).searchSlots(groups, bytes, from, skipEmpty)
		if slots.isEmpty: return -1
		matchStart = slots[0]
		emptyRejected = skipEmpty and matchStart == from
		slots[1]

	# the scan for a text's matches begins at its start
	fn restart():
		cursor = 0
		cursorEmpty = false

	# Where the next match of the text ends, -1 when there is none; where it starts is left in
	# `matchStart`. The scan goes on at the match's end, where no empty match is taken after an empty one.
	fn locateNext(bytes u8[]):
		end = self.locate(bytes, cursor, cursorEmpty)
		if end >= 0:
			cursor = end
			cursorEmpty = end == matchStart
		end

	# the positions of the groups of the match [start, end), the whole match first
	fn slotsOf(bytes u8[], start i64, end i64):
		if groups == 0: return [start, end]
		captures.captureSlots(groups, bytes, start, end, emptyRejected)

	fn matchOf(text str, bytes u8[], start i64, end i64):
		cuts = self.slotsOf(bytes, start, end).map(-1 if it < 0 else it - start)
		Match(start, end, text = text[start..end].copy(), cuts, names = names.copy())

	# The first match at or after byte `from` of the text, none when there is no more.
	pub mut fn find(text str, from i64 = 0) Match?:
		if from > text.len: return none
		bytes = text.bytes()
		end = self.locate(bytes, from, false)
		if end < 0: return none
		self.matchOf(text, bytes, matchStart, end)

	# Whether the text has a match.
	pub mut fn isMatch(text str) bool:
		self.locate(text.bytes(), 0, false) >= 0

	# The matches that do not overlap, in order.
	pub mut fn findAll(text str) Match[]:
		bytes = text.bytes()
		found = []
		self.restart()
		loop:
			end = self.locateNext(bytes)
			if end < 0: break
			found.push(self.matchOf(text, bytes, matchStart, end))
		found

	# How many matches there are.
	pub mut fn count(text str) i64:
		bytes = text.bytes()
		n = 0
		self.restart()
		while self.locateNext(bytes) >= 0:
			n += 1
		n

	# The text with every match replaced by `by`, which writes the match's groups with `\1`,
	# `\g<1>` and `\g<name>` (template.zap); a group the pattern lacks stops the program.
	pub mut fn replace(text str, by str) str:
		template = readTemplate(by, groups, names) ?? fail
		self.rewrite(text, template, writtenByTemplate, false)

	# The text with every match replaced by what `make` gives for it.
	pub mut fn replaceWith(text str, make fn(Match) str) str:
		self.rewrite(text, Template(literals = [], refs = []), make, true)

	# the text with each match replaced: by `make` of it when `useMake`, else by the template
	mut fn rewrite(text str, template Template, make fn(Match) str, useMake bool):
		bytes = text.bytes()
		out u8[] = []
		out.reserve(text.len)
		copied = 0
		self.restart()
		loop:
			end = self.locateNext(bytes)
			if end < 0: break
			rt.strBuildAdd(out, text[copied..matchStart])
			if useMake:
				rt.strBuildAdd(out, make(self.matchOf(text, bytes, matchStart, end)))
			else:
				self.expand(out, template, text, bytes, matchStart, end)
			copied = end
		rt.strBuildAdd(out, text[copied..bytes.len])
		rt.strBuildEnd(move out)

	# the template written into out for the match [start, end)
	fn expand(mut out u8[], template Template, text str, bytes u8[], start i64, end i64):
		rt.strBuildAdd(out, template.literals[0])
		if template.refs.isEmpty: return
		slots = self.slotsOf(bytes, start, end)
		for k, g in template.refs:
			if slots[2 * g] >= 0: rt.strBuildAdd(out, text[slots[2 * g]..slots[2 * g + 1]])
			rt.strBuildAdd(out, template.literals[k + 1])

# the stand-in for a replacement function when the template is the one in use
fn writtenByTemplate(m Match):
	""

# The pattern compiled, or why it is not one.
pub fn compile(pattern str) Regex ? str:
	parsed = parsePattern(pattern) ?? return error
	forward = parsed.buildNfa(false, true) ?? return error
	backward = parsed.buildNfa(true, false) ?? return error
	straight = parsed.buildNfa(false, false) ?? return error
	a = newDfa(straight.copy(), true)
	nonEmpty = newDfa(straight, true, true)
	prefilter = a.prefilterOf()
	captures = Nfa()
	if parsed.groups > 0: captures = parsed.buildNfa(false, false, true) ?? return error
	Regex(
		pattern = pattern.copy(),
		forward = newDfa(forward, true),
		backward = newDfa(backward, false),
		anchored = a,
		nonEmpty,
		prefilter,
		captures,
		groups = parsed.groups,
		names = parsed.names.copy()
	)

# the position after the character that begins at p (a UTF-8 character is at most four bytes)
fn nextBoundary(bytes u8[], p i64):
	q = p + 1
	while q < bytes.len and q < p + 4 and (bytes[q] & 0xC0) == 0x80:
		q += 1
	q
