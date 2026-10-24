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
	prefilter Prefilter
	captures Nfa   # the pattern's NFA that saves the groups' positions, left empty without groups
	groups i64
	names str[]
	matchStart i64 = 0   # where the match locate found starts

	# Where the first match of the bytes at or after `from` ends, -1 when there is none; where it
	# starts is left in `matchStart`. The bytes that cannot begin a match are skipped; then the match
	# at each candidate start is tried (the first that has one is the leftmost), as long as the
	# failed tries have read no more than the bytes passed over; after that the forward automaton
	# finds where the leftmost match ends and the reverse one where it starts, the whole text in one
	# pass whatever the pattern.
	fn locate(bytes u8[], from i64):
		n = bytes.len
		p = from
		wasted = 0
		while wasted <= p - from + 32 and p <= n:
			p = prefilter.skip(bytes, p)
			if p >= n and prefilter.canStart[256] == 0: return -1
			end = anchored.lastEnd(bytes, p)
			if end >= 0:
				matchStart = p
				return end
			wasted += anchored.stopped - p + 9
			p += 1
		if p > n: return -1
		end = forward.lastEnd(bytes, p)
		if end < 0: return -1
		matchStart = backward.firstStart(bytes, p, end)
		end

	# the positions of the groups of the match [start, end), the whole match first
	fn slotsOf(bytes u8[], start i64, end i64) i64[]:
		if groups == 0: return [start, end]
		captureSlots(captures, groups, bytes, start, end)

	fn matchOf(text str, bytes u8[], start i64, end i64) Match:
		cuts = self.slotsOf(bytes, start, end).map(-1 if it < 0 else it - start)
		Match(start, end, text = text[start..end].copy(), cuts, names = names.copy())

	# The first match at or after byte `from` of the text, none when there is no more.
	pub mut fn find(text str, from i64 = 0) Match?:
		if from > text.len: return none
		bytes = text.bytes()
		end = self.locate(bytes, from)
		if end < 0: return none
		self.matchOf(text, bytes, matchStart, end)

	# Whether the text has a match.
	pub mut fn isMatch(text str) bool:
		self.locate(text.bytes(), 0) >= 0

	# The matches that do not overlap, in order.
	pub mut fn findAll(text str) Match[]:
		bytes = text.bytes()
		found = []
		from = 0
		while from <= bytes.len:
			end = self.locate(bytes, from)
			if end < 0: break
			found.push(self.matchOf(text, bytes, matchStart, end))
			from = after(matchStart, end)
		found

	# How many matches there are.
	pub mut fn count(text str) i64:
		bytes = text.bytes()
		n = 0
		from = 0
		while from <= bytes.len:
			end = self.locate(bytes, from)
			if end < 0: break
			n += 1
			from = after(matchStart, end)
		n

	# The text with every match replaced by `by`, which writes the match's groups with `\1`,
	# `\g<1>` and `\g<name>` (template.zap); a group the pattern lacks stops the program.
	pub mut fn replace(text str, by str) str:
		template = readTemplate(by, groups, names) ?? fail(error)
		self.rewrite(text, template, writtenByTemplate, false)

	# The text with every match replaced by what `make` gives for it.
	pub mut fn replaceWith(text str, make fn(Match) str) str:
		self.rewrite(text, Template(literals = [], refs = []), make, true)

	# the text with each match replaced: by `make` of it when `useMake`, else by the template
	mut fn rewrite(text str, template Template, make fn(Match) str, useMake bool) str:
		bytes = text.bytes()
		out u8[] = []
		out.reserve(text.len)
		copied = 0
		from = 0
		while from <= bytes.len:
			end = self.locate(bytes, from)
			if end < 0: break
			rt.strBuildAdd(out, text[copied..matchStart])
			if useMake:
				rt.strBuildAdd(out, make(self.matchOf(text, bytes, matchStart, end)))
			else:
				self.expand(out, template, text, bytes, matchStart, end)
			copied = end
			from = after(matchStart, end)
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
fn writtenByTemplate(m Match) str:
	""

# The pattern compiled, or why it is not one.
pub fn compile(pattern str) Regex ? str:
	parsed = parsePattern(pattern) ?? return error
	forward = parsed.buildNfa(false, true) ?? return error
	backward = parsed.buildNfa(true, false) ?? return error
	straight = parsed.buildNfa(false, false) ?? return error
	a = newDfa(straight, true)
	prefilter = a.prefilterOf()
	captures = Nfa()
	if parsed.groups > 0: captures = parsed.buildNfa(false, false, true) ?? return error
	Regex(
		pattern = pattern.copy(),
		forward = newDfa(forward, true),
		backward = newDfa(backward, false),
		anchored = a,
		prefilter,
		captures,
		groups = parsed.groups,
		names = parsed.names.copy()
	)

# where the search after a match goes on: past an empty match, else at its end
fn after(start i64, end i64):
	end if end > start else end + 1
