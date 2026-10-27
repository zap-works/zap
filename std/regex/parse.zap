# A pattern read into a flat list of nodes (a node's children are indexes into the list, so the
# tree needs no recursive type) and the classes of characters it names. The syntax is Python's re
# on a str: literals, `.` (any character but a newline), `[a-z]`, `[^...]`, `\d \w \s` and their
# upper-case negations (Unicode's: codes.zap and unicode.zap), `\n \t \r \f \v \a \xHH \uHHHH
# \UHHHHHHHH` and escaped punctuation, `\b` and `\B` for a word's edge, `(...)`, `(?P<name>...)`
# and `(?<name>...)` for a captured group, `(?:...)` for grouping alone, `|`, `* + ? {n} {n,}
# {n,m} {,m}` each with a lazy `?` form, and `^` and `$` for the ends of the text (`$` also before
# the text's last newline). A `{` that does not begin a repetition is a literal brace. A
# repetition of a repetition or of `^`, `$`, `\b`, `\B` is refused as Python refuses it.
# What only a backtracking engine has is refused by name: a backreference, a lookahead, a
# lookbehind, an atomic group, a possessive quantifier. Flags lead the pattern, as `(?i)`,
# `(?ms)`: `i` makes a letter match in either case (Unicode's simple case folding), `m` makes `^`
# and `$` match at the ends of each line (a line ends at a newline) too, `s` makes `.` match a
# newline, `a` keeps `\w \d \s \b` and `i` to ASCII (`u`, the default, undoes it).

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
nodeClass = 12   # a: the class of characters (an index into the pattern's classes)
nodeBound = 11   # a word's edge, `\b`; the lack of one, `\B`, when a is 1

type Node:
	kind i64
	a i64 = 0
	b i64 = 0
	c i64 = 0
	lazy bool = false

type Quantifier:
	kind i64   # nodeStar, nodePlus, nodeQuest, nodeRepeat; -1 for none
	low i64
	high i64   # -1 for no limit

type Parser:
	src u8[]
	at i64 = 0
	nodes Node[] = []
	sets u8[] = []   # 256 bytes a set: 1 for a member
	classCodes i64[] = []   # the classes' code point ranges, one class after another
	classEnds i64[] = []   # where each class ends in classCodes
	error str = ""
	depth i64 = 0
	root i64 = 0
	groups i64 = 0   # the captured groups so far; names[k] is the name of group k + 1, "" when it has none
	names str[] = []
	hasBounds bool = false
	hasTail bool = false   # the pattern has a `$`
	multiline bool = false   # the flags: `m`, `i`, `s`
	ignoreCase bool = false
	dotAll bool = false
	asciiOnly bool = false   # the flag `a`: `\w`, `\d`, `\s` and `(?i)` take ASCII only

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

	# the node of a literal byte
	fn byteNode(b i64) i64:
		sets.extend(zeros(256))
		sets[sets.len - 256 + b] = 1
		self.add(nodeSet, sets.len / 256 - 1)

	# the node for a class of characters, given as ranges of code points
	fn classNode(ranges i64[]) i64:
		classCodes.extend(ranges)
		classEnds.push(classCodes.len)
		self.add(nodeClass, classEnds.len - 1)

	# The code points a class escape (\d \w \s, or the upper case for its complement) names; the
	# flag `a` keeps them to ASCII.
	fn classEscape(c u8) i64[]:
		lower = c | 32
		ranges = (digitRanges if lower == 'd' else wordRanges if lower == 'w' else spaceRanges).copy()
		if asciiOnly: ranges = clippedRanges(ranges, 0x7F)
		invertRanges(ranges) if c < 'a' else ranges

	# the code points of the text at `at`, which moves past the character
	fn readCode() i64:
		packed = utf8At(src, at)
		at += packed >> 24
		packed & 0xFFFFFF

	# the code point of an escape (after the backslash, not a class), -1 for none
	fn escapedCode(inClass bool) i64:
		c = src[at]
		at += 1
		if c == 'n': return 10
		if c == 't': return 9
		if c == 'r': return 13
		if c == 'f': return 12
		if c == 'v': return 11
		if c == 'a': return 7
		if c == 'b' and inClass: return 8
		if c == '0': return 0
		if c == 'x': return self.hexCode(2)
		if c == 'u': return self.hexCode(4)
		if c == 'U': return self.hexCode(8)
		if c.isAlpha() or c.isDigit():
			self.fail("the escape \\{[c].text()} is unsupported")
			return -1
		at -= 1
		self.readCode()

	# the code point written with that many hex digits at `at`
	fn hexCode(digits i64) i64:
		code = 0
		loop digits:
			if at >= src.len or hexValue(src[at]) < 0:
				self.fail("a bad \\x, \\u or \\U escape")
				return -1
			code = code * 16 + hexValue(src[at])
			at += 1
		if code > maxCode or (code >= 0xD800 and code <= 0xDFFF):
			self.fail("a bad \\x, \\u or \\U escape")
			return -1
		code

	# one character of a class: a code point, or -1 after a class escape (added to `escapes`) or an error
	fn classChar(mut escapes i64[]) i64:
		if src[at] != '\\': return self.readCode()
		at += 1
		if at >= src.len:
			self.fail("a trailing backslash")
			return -1
		if isClassEscape(src[at]):
			escapes = unionRanges(escapes, self.classEscape(src[at]))
			at += 1
			return -1
		self.escapedCode(true)

	# a class: `[`, an optional `^`, members (a character, a range, an escape), `]`
	fn parseClass() i64:
		at += 1
		negated = self.peeks('^')
		if negated: at += 1
		members i64[] = []   # the characters and ranges written, the other cases of them added under `i`
		escapes i64[] = []   # the sets the class escapes name
		first = true
		loop:
			if at >= src.len: return self.fail("an unclosed [")
			if src[at] == ']' and not first: break
			first = false
			lo = self.classChar(escapes)
			if not error.isEmpty: return 0
			if lo < 0: continue
			hi = lo
			if self.peeks('-') and at + 1 < src.len and src[at + 1] != ']':
				at += 1
				hi = self.classChar(escapes)
				if not error.isEmpty: return 0
				if hi < 0: return self.fail("a bad range")
				if hi < lo: return self.fail("a reversed range")
			members = unionRanges(members, [lo, hi])
		at += 1
		if ignoreCase: members = foldedRanges(members, asciiOnly)
		all = unionRanges(members, escapes)
		self.classNode(invertRanges(all) if negated else all)

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

	# the node of a literal character: the bytes of its UTF-8 together, or under `i` the class of the characters that match it
	fn literalNode(code i64) i64:
		if ignoreCase:
			same = foldedRanges([code, code], asciiOnly)
			if same.len != 2 or same[0] != code or same[1] != code: return self.classNode(same)
		bytes = utf8Of(code)
		node = self.byteNode(bytes[0])
		for k in 1..bytes.len:
			node = self.add(nodeCat, node, self.byteNode(bytes[k]))
		node

	# the name of a group, up to its `>`
	fn parseName():
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
		self.fail("an unsupported group")

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
		if c == '.': return self.classNode(invertRanges([] if dotAll else [10, 10]))
		if c == '^': return self.add(nodeHead)
		if c == '$':
			hasTail = true
			return self.add(nodeTail)
		if c in ['*', '+', '?']: return self.fail("nothing to repeat")
		if c == '{':
			at -= 1
			if self.readQuantifier().kind >= 0: return self.fail("nothing to repeat")
			at += 1
		if c == '\\':
			if at >= src.len: return self.fail("a trailing backslash")
			if isClassEscape(src[at]):
				at += 1
				return self.classNode(self.classEscape(src[at - 1]))
			if src[at] == 'b' or src[at] == 'B':
				at += 1
				hasBounds = true
				return self.add(nodeBound, 1 if src[at - 1] == 'B' else 0)
			code = self.escapedCode(false)
			if code < 0: return 0
			return self.literalNode(code)
		at -= 1
		self.literalNode(self.readCode())

	# the repetition at `at` as a Quantifier; kind -1 (and `at` unmoved) when there is none. A `{`
	# that does not begin `{m,n}` is a literal brace, and `{,n}` is `{0,n}`.
	fn readQuantifier() Quantifier:
		absent = Quantifier(-1, 0, -1)
		if not self.more(): return absent
		c = src[at]
		if c == '*':
			at += 1
			return Quantifier(nodeStar, 0, -1)
		if c == '+':
			at += 1
			return Quantifier(nodePlus, 0, -1)
		if c == '?':
			at += 1
			return Quantifier(nodeQuest, 0, -1)
		if c != '{': return absent
		from = at
		at += 1
		low = self.parseNumber()
		high = low
		if self.peeks(','):
			at += 1
			high = self.parseNumber()
			if low < 0: low = 0
		if low < 0 or not self.peeks('}'):
			at = from
			return absent
		at += 1
		if high >= 0 and high < low:
			self.fail("a reversed repetition")
			return absent
		Quantifier(nodeRepeat, low, high)

	# an atom and the repetition that follows it. What a repetition cannot follow is refused as
	# Python does: a repetition of a repetition, a repetition of `^`, `$`, `\b` or `\B`.
	fn parseRepeat():
		from = at
		node = self.parseAtom()
		q = self.readQuantifier()
		if q.kind < 0: return node
		if self.assertionAt(from): return self.fail("nothing to repeat")
		lazy = self.peeks('?')
		if lazy: at += 1
		if self.peeks('+') and not lazy: return self.fail("a possessive quantifier is unsupported")
		if self.readQuantifier().kind >= 0: return self.fail("multiple repeat")
		return self.add(q.kind, node, q.low, q.high, lazy)

	# whether the atom that begins at `from` is an assertion: `^`, `$`, `\b`, `\B`
	fn assertionAt(from i64):
		c = src[from]
		c == '^' or c == '$' or (c == '\\' and (src[from + 1] == 'b' or src[from + 1] == 'B'))

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
				elif src[at] == 'a':
					asciiOnly = true
				elif src[at] == 'u':
					asciiOnly = false
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
