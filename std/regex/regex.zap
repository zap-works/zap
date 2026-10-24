# Regular expressions over bytes, matched without backtracking: a lazy DFA reads the text once,
# whatever the pattern, so a match costs time proportional to the text. `import regex`, then
# `re = regex.compile("[ab]+c") ?? fail(error)`, `re.find(text)`, `re.count(text)`,
# `re.replace(text, "-")`. The syntax is in parse.zap; a match is the leftmost one, and of those
# the one a backtracking engine would take (the first branch of each `|`, greedy unless `?`
# follows). The flags `(?i)`, `(?m)` and `(?s)` lead a pattern (parse.zap). No captures, no `\b`.
# A Regex builds its tables as it matches, so it is `mut`: a
# thread uses its own (compile one per thread).

# a match: the bytes [start, end) of the text
pub type Span:
	start i64
	end i64

# a compiled pattern: its forward automaton finds where a match ends, its reverse one where it
# starts, its anchored one the match at a given start; `prefilter` knows where a match can
# begin, so a search skips the other positions
pub type Regex:
	pattern str
	forward Dfa
	backward Dfa
	anchored Dfa
	prefilter Prefilter
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

	# The first match at or after byte `from` of the text, none when there is no more.
	pub mut fn find(text str, from i64 = 0) Span?:
		if from > text.len: return none
		end = self.locate(text.bytes(), from)
		if end < 0: return none
		Span(matchStart, end)

	# Whether the text has a match.
	pub mut fn isMatch(text str) bool:
		self.locate(text.bytes(), 0) >= 0

	# The matches that do not overlap, in order.
	pub mut fn findAll(text str) Span[]:
		bytes = text.bytes()
		found = []
		from = 0
		while from <= bytes.len:
			end = self.locate(bytes, from)
			if end < 0: break
			found.push(Span(matchStart, end))
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

	# The text with every match replaced by `by`, which is taken as it is.
	pub mut fn replace(text str, by str) str:
		bytes = text.bytes()
		out u8[] = []
		out.reserve(text.len)
		copied = 0
		from = 0
		while from <= bytes.len:
			end = self.locate(bytes, from)
			if end < 0: break
			rt.strBuildAdd(out, text[copied..matchStart])
			rt.strBuildAdd(out, by)
			copied = end
			from = after(matchStart, end)
		rt.strBuildAdd(out, text[copied..bytes.len])
		rt.strBuildEnd(move out)

# The pattern compiled, or why it is not one.
pub fn compile(pattern str) Regex ? str:
	parsed = parsePattern(pattern) ?? return error
	forward = parsed.buildNfa(false, true) ?? return error
	backward = parsed.buildNfa(true, false) ?? return error
	straight = parsed.buildNfa(false, false) ?? return error
	a = newDfa(straight, true)
	prefilter = a.prefilterOf()
	Regex(
		pattern = pattern.copy(),
		forward = newDfa(forward, true),
		backward = newDfa(backward, false),
		anchored = a,
		prefilter
	)

# where the search after a match goes on: past an empty match, else at its end
fn after(start i64, end i64):
	end if end > start else end + 1
