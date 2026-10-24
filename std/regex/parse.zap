# A pattern read into a flat list of nodes (a node's children are indexes into the list, so the
# tree needs no recursive type) and the byte sets its classes name. The syntax is the usual one,
# over bytes: literals, `.` (any byte but a newline), `[a-z]`, `[^...]`, `\d \w \s` and their
# upper-case negations, `\n \t \r \xHH` and escaped punctuation, `\b` and `\B` for a word's edge,
# `(...)`, `(?P<name>...)` and `(?<name>...)` for a captured group, `(?:...)` for grouping alone,
# `|`, `* + ? {n} {n,} {n,m}` each with a lazy `?` form, and `^` and `$` for the ends of the text.
# What only a backtracking engine has is refused by name: a backreference, a lookahead, a lookbehind. Flags lead the pattern, as `(?i)`, `(?ms)`: `i` makes ASCII letters match in either
# case, `m` makes `^` and `$` match at the ends of each line (a line ends at a newline byte) too,
# `s` makes `.` match a newline.

# the kinds of a Node
nodeEmpty = 0
nodeSet = 1   # a: the set
nodeCat = 2   # a then b
nodeAlt = 3   # a or b, a preferred
nodeStar = 4   # a
nodePlus = 5   # a
nodeQuest = 6   # a
nodeHead = 7   # ^
nodeTail = 8   # $
nodeRepeat = 9   # a, between b and c times (c is -1 for no limit)
nodeGroup = 10   # a, captured as group b
nodeBound = 11   # a word's edge, `\b`; the lack of one, `\B`, when a is 1

type Node:
	kind i64
	a i64 = 0
	b i64 = 0
	c i64 = 0
	lazy bool = false

type Parser:
	src u8[]
	at i64 = 0
	nodes Node[] = []
	sets u8[] = []   # 256 bytes a set: 1 for a member
	error str = ""
	depth i64 = 0
	root i64 = 0
	groups i64 = 0   # the captured groups so far; names[k] is the name of group k + 1, "" when it has none
	names str[] = []
	hasBounds bool = false
	multiline bool = false   # the flags: `m`, `i`, `s`
	ignoreCase bool = false
	dotAll bool = false

	fn add(kind i64, a i64 = 0, b i64 = 0, c i64 = 0, lazy bool = false) i64:
		nodes.push(Node(kind, a, b, c, lazy))

	fn fail(why str):
		if error.isEmpty:
			error = "regex: {why} at byte {at}"
		0

	fn more():
		at < src.len and error.isEmpty

	fn peeks(c u8):
		at < src.len and src[at] == c

	fn newSet():
		sets.extend(zeros(256))
		sets.len / 256 - 1

	fn addRange(set i64, lo i64, hi i64):
		for b in lo..=hi:
			sets[set * 256 + b] = 1

	fn invert(set i64):
		for b in 0..256:
			sets[set * 256 + b] = 1 - sets[set * 256 + b]

	fn addSet(set i64, other i64):
		for b in 0..256:
			if sets[other * 256 + b] == 1: sets[set * 256 + b] = 1

	# the set a class escape (\d \w \s, or the upper case for its complement) names
	mut fn classEscape(c u8):
		set = self.newSet()
		lower = c | 32
		if lower == 'd':
			self.addRange(set, '0', '9')
		elif lower == 'w':
			for b in 0..256:
				if isWordByte(b): sets[set * 256 + b] = 1
		else:
			self.addRange(set, '\t', '\r')
			self.addRange(set, ' ', ' ')
		if c < 'a': self.invert(set)
		set

	# the byte an escape (after the backslash, not a class) stands for, -1 for none
	fn escapedByte() i64:
		c = src[at]
		at += 1
		if c == 'n': return 10
		if c == 't': return 9
		if c == 'r': return 13
		if c == 'f': return 12
		if c == 'v': return 11
		if c == '0': return 0
		if c == 'x':
			if at + 1 < src.len and hexValue(src[at]) >= 0 and hexValue(src[at + 1]) >= 0:
				v = hexValue(src[at]) * 16 + hexValue(src[at + 1])
				at += 2
				return v
			self.fail("a bad \\x escape")
			return -1
		if c.isAlpha() or c.isDigit():
			self.fail("the escape \\{[c].text()} is unsupported")
			return -1
		c

	# the other case of each ASCII letter in the set added to it, under the `i` flag
	fn foldCase(set i64):
		if not ignoreCase: return
		for b in 'a'..='z':
			upper = b - 32
			if sets[set * 256 + b] == 1 or sets[set * 256 + upper] == 1:
				sets[set * 256 + b] = 1
				sets[set * 256 + upper] = 1

	fn byteSet(b i64):
		set = self.newSet()
		sets[set * 256 + b] = 1
		self.foldCase(set)
		set

	# a class: `[`, an optional `^`, members (a byte, a range, an escape), `]`
	fn parseClass() i64:
		at += 1
		set = self.newSet()
		negated = self.peeks('^')
		if negated: at += 1
		first = true
		loop:
			if at >= src.len: return self.fail("an unclosed [")
			if src[at] == ']' and not first: break
			first = false
			lo = i64(src[at])
			at += 1
			if lo == '\\':
				if at >= src.len: return self.fail("a trailing backslash")
				if isClassEscape(src[at]):
					other = self.classEscape(src[at])
					at += 1
					self.addSet(set, other)
					continue
				lo = self.escapedByte()
				if lo < 0: return 0
			if self.peeks('-') and at + 1 < src.len and src[at + 1] != ']':
				at += 1
				hi = i64(src[at])
				at += 1
				if hi == '\\':
					if at >= src.len: return self.fail("a trailing backslash")
					hi = self.escapedByte()
					if hi < 0: return 0
				if hi < lo: return self.fail("a reversed range")
				self.addRange(set, lo, hi)
			else:
				self.addRange(set, lo, lo)
		at += 1
		self.foldCase(set)
		if negated: self.invert(set)
		self.add(nodeSet, set)

	# the number at `at`, -1 when there is none
	fn parseNumber():
		n = 0
		digits = 0
		while at < src.len and src[at].isDigit():
			n = n * 10 + i64(src[at]) - '0'
			at += 1
			digits += 1
			if n > maxRepeat: return self.fail("a repetition above {maxRepeat}")
		n if digits > 0 else -1

	# a literal character: one byte, or all the bytes of a UTF-8 sequence together
	fn parseLiteral(b i64):
		node = self.add(nodeSet, self.byteSet(b))
		if b >= 0xC0:
			extra = 1 if b < 0xE0 else 2 if b < 0xF0 else 3
			loop extra:
				if at >= src.len: break
				node = self.add(nodeCat, node, self.add(nodeSet, self.byteSet(src[at])))
				at += 1
		node

	# the name of a group, up to its `>`
	fn parseName() str:
		from = at
		while at < src.len and isWordByte(src[at]):
			at += 1
		if at == from or src[from].isDigit() or not self.peeks('>'):
			self.fail("a bad group name")
			return ""
		name = src[from..at].text().copy()
		at += 1
		if names.any(it == name): self.fail("the group name {name} is used twice")
		name

	# what follows `(?` when it is not `:`, `P<` or `<`: the construct a backtracking engine has
	fn unsupportedGroup() i64:
		if at >= src.len: return self.fail("an unclosed (")
		c = src[at]
		if c == '=' or c == '!': return self.fail("a lookahead is unsupported")
		if c == '<': return self.fail("a lookbehind is unsupported")
		if c == 'P': return self.fail("a named backreference is unsupported")
		if c == '>': return self.fail("an atomic group is unsupported")
		return self.fail("an unsupported group")

	# a group, after its `(`: capturing, with a name or without, or `(?:` alone
	fn parseGroup() i64:
		capture = true
		name = ""
		if self.peeks('?'):
			at += 1
			if self.peeks(':'):
				capture = false
				at += 1
			elif self.peeks('P') and at + 1 < src.len and src[at + 1] == '<':
				at += 2
				name = self.parseName()
			elif self.peeks('<') and at + 1 < src.len and src[at + 1] != '=' and src[at + 1] != '!':
				at += 1
				name = self.parseName()
			else:
				return self.unsupportedGroup()
		index = 0
		if capture:
			if groups >= maxGroups: return self.fail("more than {maxGroups} groups")
			groups += 1
			index = groups
			names.push(name)
		depth += 1
		if depth > maxDepth: return self.fail("groups nested too deep")
		node = self.parseAlt()
		if not self.peeks(')'): return self.fail("an unclosed (")
		at += 1
		depth -= 1
		self.add(nodeGroup, node, index) if capture else node

	fn parseAtom() i64:
		c = src[at]
		at += 1
		if c == '(': return self.parseGroup()
		if c == '[':
			at -= 1
			return self.parseClass()
		if c == '.':
			set = self.newSet()
			self.addRange(set, 0, 255)
			if not dotAll: sets[set * 256 + 10] = 0
			return self.add(nodeSet, set)
		if c == '^': return self.add(nodeHead)
		if c == '$': return self.add(nodeTail)
		if c in ['*', '+', '?']: return self.fail("nothing to repeat")
		if c == '\\':
			if at >= src.len: return self.fail("a trailing backslash")
			if isClassEscape(src[at]):
				set = self.classEscape(src[at])
				at += 1
				return self.add(nodeSet, set)
			if src[at] == 'b' or src[at] == 'B':
				at += 1
				hasBounds = true
				return self.add(nodeBound, 1 if src[at - 1] == 'B' else 0)
			b = self.escapedByte()
			if b < 0: return 0
			return self.add(nodeSet, self.byteSet(b))
		self.parseLiteral(c)

	# an atom and the repetitions that follow it
	fn parseRepeat():
		node = self.parseAtom()
		loop:
			if not self.more(): break
			c = src[at]
			kind = -1
			low = 0
			high = -1
			if c == '*':
				kind = nodeStar
				at += 1
			elif c == '+':
				kind = nodePlus
				at += 1
			elif c == '?':
				kind = nodeQuest
				at += 1
			elif c == '{':
				at += 1
				low = self.parseNumber()
				if low < 0: return self.fail("a bad repetition")
				high = low
				if self.peeks(','):
					at += 1
					high = self.parseNumber()
				if not self.peeks('}'): return self.fail("a bad repetition")
				at += 1
				if high >= 0 and high < low: return self.fail("a reversed repetition")
				kind = nodeRepeat
			else:
				break
			lazy = self.peeks('?')
			if lazy: at += 1
			node = self.add(kind, node, low, high, lazy)
		node

	# the flag groups that lead the pattern, `(?ims)`: each flag applies to the whole of it
	fn readFlags():
		while at + 2 < src.len and src[at] == '(' and src[at + 1] == '?' and
			src[at + 2].isAlpha() and src[at + 2] != 'P':
			at += 2
			while at < src.len and src[at] != ')':
				if src[at] == 'i':
					ignoreCase = true
				elif src[at] == 'm':
					multiline = true
				elif src[at] == 's':
					dotAll = true
				else:
					self.fail("an unsupported flag")
					return
				at += 1
			if at >= src.len:
				self.fail("an unclosed (")
				return
			at += 1

	mut fn parseCat():
		if not self.more() or src[at] == '|' or src[at] == ')': return self.add(nodeEmpty)
		node = self.parseRepeat()
		while self.more() and src[at] != '|' and src[at] != ')':
			node = self.add(nodeCat, node, self.parseRepeat())
		node

	fn parseAlt():
		node = self.parseCat()
		while self.peeks('|'):
			at += 1
			node = self.add(nodeAlt, node, self.parseCat())
		node

maxDepth = 200
maxRepeat = 1_000
maxGroups = 99

fn isClassEscape(c u8):
	(c | 32) == 'd' or (c | 32) == 'w' or (c | 32) == 's'

# a byte of a word, which `\w` and `\b` tell from the others
fn isWordByte(c i64):
	(c >= 65 and c <= 90) or (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95

fn hexValue(c u8):
	if c >= '0' and c <= '9': return i64(c) - '0'
	lower = c | 32
	if lower >= 'a' and lower <= 'f': return i64(lower) - 'a' + 10
	-1

# the pattern's nodes and sets and the root node; or why it is not a pattern
fn parsePattern(pattern str) Parser ? str:
	p = Parser(src = pattern.bytes().copy())
	p.readFlags()
	p.root = p.parseAlt() if p.error.isEmpty else 0
	if p.error.isEmpty and p.at < p.src.len:
		p.fail("an unmatched )")
	if not p.error.isEmpty: return p.error
	p
