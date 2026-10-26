# The rewrites of match arms and guards across lines (rewrite.zap).

# A match as fmt lays it out: its header line (`... match scrutinee:`), its arms (each from its
# first line, one tab past the header, the arm's lines then those to the next arm) and the first
# line after it (close: the file's length when nothing follows).
type MatchLines:
	header i64
	prefix str   # the header before `match`
	scrut str
	note str   # a comment after the header, kept by what it is written as
	arms i64[]   # each arm's first line
	close i64

# The matches of the code rewritten, the last first (a rewrite changes its own lines only)
fn matchRewrites(mut lines str[], mut info LineInfo[], coalesce i64[]):
	# again while a rewrite made another possible (a match an arm held, a statement once its
	# outer match is an if)
	passes = 0
	changed = true
	while changed and passes < 4:
		changed = false
		i = lines.len - 1
		while i >= 0:
			if info[i].kind == 0:
				m = matchAt(lines, info, i)
				if m.close > 0:
					before = lines.len
					mergeArms(lines, info, m)
					m2 = matchAt(lines, info, i)
					if m2.close > 0 and
						(
							oneCase(lines, info, m2) or
								info[i].origin in coalesce and coalesced(lines, info, m2)
						) or
						lines.len != before:
						changed = true
			i -= 1
		passes += 1

# A guard written over two lines, `if c:` / `return x` (or break, continue), with no else and no
# comment, is one line when that fits in guardWidth columns: `if c: return x`.
fn guardRewrites(mut lines str[], mut info LineInfo[]):
	i = lines.len - 2
	while i >= 0:
		if guardAt(lines, info, i):
			made = "{leadOf(lines[i])}{lines[i].trimmed()} {lines[i + 1].trimmed()}"
			replaceLines(lines, info, i, i + 2, [(made, i)])
		i -= 1

# the columns a line of the layout fits in, a tab counted as four (wrap.zap breaks longer ones)
lineWidth = 100

fn guardAt(lines str[], info LineInfo[], i i64):
	head = lines[i].trimmed()
	body = lines[i + 1].trimmed()
	if info[i].kind != 0 or info[i + 1].kind != 0 or not info[i].stmt or not info[i + 1].stmt:
		return false
	if not head.startsWith("if ") or not opensBlock(head) or "#" in head or "#" in body:
		return false
	tabs = indentOf(lines[i])
	if indentOf(lines[i + 1]) != tabs + 1: return false
	# the block holds that line alone: the next line of code is indented no more than the if
	j = i + 2
	while j < lines.len and lines[j].trimmed() == "":
		j += 1
	if j < lines.len and
		(
			indentOf(lines[j]) > tabs or lines[j].trimmed().startsWith("else") or
				lines[j].trimmed().startsWith("elif")
		):
		return false
	jump = body == "break" or body == "continue" or body == "return" or body.startsWith("return ")
	jump and 4 * tabs + head.len + body.len + 1 <= lineWidth

# the match whose header is line i (close 0 when the line is not one, or its lines read
# otherwise than fmt lays them out)
fn matchAt(lines str[], info LineInfo[], i i64):
	nothing = MatchLines(header = i, prefix = "", scrut = "", note = "", arms = [], close = 0)
	code = codeOf(lines[i].trimmed())
	if not opensBlock(code): return nothing
	at = lastMatchWord(code)
	if at < 0: return nothing
	whole = lines[i].trimmed()
	note = whole[code.len..].copy()
	m = MatchLines(
		header = i,
		prefix = code[..at].copy(),
		scrut = code[at + 6..len - 1].trimmedEnd().copy(),
		note,
		arms = [],
		close = 0
	)
	tabs = indentOf(lines[i])
	j = i + 1
	while j < lines.len:
		if lines[j].trimmed() == "":
			j += 1
			continue
		depth = indentOf(lines[j])
		if info[j].kind == 0 and depth <= tabs:
			m.close = j
			return m if not m.arms.isEmpty else nothing
		if depth == tabs + 1:
			if info[j].kind != 0 or codeOf(lines[j].trimmed()) == "":
				return nothing   # a string, a comment or a test's source between the arms
			m.arms.push(j)
		j += 1
	m.close = lines.len
	m if not m.arms.isEmpty else nothing

# where the word `match` of a header line starts (the last one, at its top level), or -1
fn lastMatchWord(code str):
	best = -1
	at = findWord(code, "match ", 0)
	while at >= 0:
		if textPlace(code, at) == 0:
			best = at
		at = findWord(code, "match ", at + 1)
	best

# an arm's first line taken apart: its pattern (its condition included) and what follows its `:` (""
# for a block on the lines below); ("", "") when the line is not `pattern: rest`
fn armParts(line str):
	t = line.trimmed()
	k = armColon(t)
	if k < 0: return ("", "")
	(t[..k].copy(), t[k + 1..].trimmed().copy())

# the lines of arm a (index into m.arms): from its first to the next arm's or the close
fn armEnd(m MatchLines, a i64):
	m.arms[a + 1] if a + 1 < m.arms.len else m.close

# whether a pattern binds no name: `_` and bare names do, as do a lowercase word in it (outside
# its strings and characters) and a string's capture; none, literals, variants without names and
# ranges do not
fn bindsNothing(pat str):
	if pat in ["none", "true", "false"]: return true
	k = 0
	while k < pat.len:
		b = pat[k]
		if b == '"' or b == '\'':
			e = literalEnd(pat, k)
			if e < 0 or b == '"' and capturesIn(pat[k..e]): return false   # a string's captures bind
			k = e
			continue
		if b == '_' or b >= 'a' and b <= 'z' and (k == 0 or not pat[k - 1].isWordByte()):
			# a name (hexadecimal digits follow 0x: part of a number)
			if not (k >= 2 and pat[k - 2] == '0' and pat[k - 1] == 'x') and
				not (k > 0 and (pat[k - 1] >= '0' and pat[k - 1] <= '9')):
				return false
		k += 1
	pat != ""

# where text is in a pattern's, outside its brackets and strings, or -1
fn topLevelAt(pat str, text str):
	depth = 0
	k = 0
	while k < pat.len:
		b = pat[k]
		if b == '"' or b == '\'':
			k = literalEnd(pat, k)
			if k < 0: return -1
			continue
		if b in ['(', '[', '{']:
			depth += 1
		elif b in [')', ']', '}']:
			depth -= 1
		elif depth == 0 and b == text[0] and pat[k..].startsWith(text):
			return k
		k += 1
	-1

# where an arm's condition starts in the text of its patterns (its top-level ` and `), or -1
fn conditionAt(pat str):
	topLevelAt(pat, " and ")

# whether a string's pattern takes parts of the text (`"GET {path}"`): a brace not escaped
fn capturesIn(pat str):
	for k in 0..pat.len:
		if pat[k] == '{' and (k == 0 or pat[k - 1] != '\\'): return true
	false

# whether a pattern holds several, separated by commas outside its parentheses (A, B)
fn topComma(pat str):
	topLevelAt(pat, ",") >= 0

# whether the code of a line ends where its text does (no comment after it)
fn bare(line str):
	codeOf(line.trimmed()).len == line.trimmed().len

# Arms in a row of one line each, binding nothing, without a condition and with the same body,
# made one: `0x04, 0x0A: 2`.
fn mergeArms(mut lines str[], mut info LineInfo[], m MatchLines):
	a = m.arms.len - 1
	while a > 0:
		cur = m.arms[a]
		prev = m.arms[a - 1]
		if m.armEnd(a) == cur + 1 and cur == prev + 1 and bare(lines[cur]) and bare(lines[prev]):
			p1, r1 = armParts(lines[prev])
			p2, r2 = armParts(lines[cur])
			if p1 != "" and p2 != "" and r1 == r2 and r1 != "" and bindsNothing(p1) and
				bindsNothing(p2) and conditionAt(p1) < 0 and conditionAt(p2) < 0:
				lines[prev] = "{leadOf(lines[prev])}{p1}, {p2}: {r1}"
				lines.remove(cur)
				info.remove(cur)
		a -= 1

# whether s holds, outside its strings, one of the operators (written between spaces or as `..`)
fn holdsOperator(s str, ops str[]):
	plain = ""
	k = 0
	while k < s.len:
		if s[k] == '"' or s[k] == '\'':
			e = literalEnd(s, k)
			if e < 0: break
			k = e
			continue
		plain += s[k..k + 1]
		k += 1
	ops.any(it in plain)

# the operators as loose as the binary operator op or looser, as written: the binary ones between
# spaces, a condition's ` ? ` and a range's `..`
fn looseOperators(op i64):
	ops = [" ? ", ".."]
	for o in binaryOperators:
		if o.level >= binaryOperators[op].level:
			ops.push(" {o.text} ")
	ops

# the scrutinee as an operand of `is` or `==`: in parentheses when it holds an operator that
# binds as loosely as a comparison or more
fn operand(s str):
	"({s})" if holdsOperator(s, looseOperators(binLt)) else s.copy()

# the scrutinee as an operand of `??` (and the value after it): in parentheses when it holds an
# operator as loose as ?? or looser
fn coalesceOperand(s str):
	"({s})" if holdsOperator(s, looseOperators(binCoalesce)) else s.copy()

# A statement match of two arms, one of which does nothing and binds nothing (`none: pass`):
# an if. Whether it rewrote it.
fn oneCase(mut lines str[], mut info LineInfo[], m MatchLines):
	if m.prefix != "" or m.arms.len != 2 or m.scrut.startsWith("move ") or
		m.scrut.startsWith("mut "):
		return false
	empty = -1
	for a in 0..2:
		p, r = armParts(lines[m.arms[a]])
		if r == passWord and m.armEnd(a) == m.arms[a] + 1 and
			(p == "_" or bindsNothing(p)) and conditionAt(p) < 0 and not topComma(p) and
			bare(lines[m.arms[a]]):
			empty = a
	if empty < 0: return false
	other = 1 - empty
	first = m.arms[other]
	last = m.armEnd(other) - 1
	pat, rest = armParts(lines[first])
	if pat == "" or pat == "_" or topComma(pat): return false
	# the condition: a pattern is tested with is (the arm's condition joins it with and), a literal
	# or none compared, a bool read as it is
	g = conditionAt(pat)
	core = pat[..g].copy() if g >= 0 else pat.copy()
	guard = pat[g..].copy() if g >= 0 else ""
	# after the empty arm a name takes what it left (`0: pass` then `v: ...`), which an if's
	# name would not: only an optional's none leaves the value to it
	emptyPat, _ = armParts(lines[m.arms[empty]])
	if empty == 0 and isPlainName(core) and core not in ["none", "true", "false"] and
		emptyPat != "none":
		return false
	# `is name` names what it tests, so the arm must read the name (else check refuses the if)
	body = [rest.copy()]
	body.extend(lines[first + 1..=last].map(.copy()))
	if isPlainName(core) and core[0] >= 'a' and core[0] <= 'z' and
		core not in ["none", "true", "false"] and
		body.all(wordColumns(it, core).isEmpty):
		return false
	lit = core == "none" or
		not core.isEmpty and ".." not in core and
		(core[0] == '"' and not capturesIn(core) or core[0] == '\'' or core[0] == '-' or
				core[0] >= '0' and core[0] <= '9')
	cond = "{operand(m.scrut)} == {core}{guard}" if lit
		else "{operand(m.scrut)} is {core}{guard}"
	if core == "true" or core == "false":
		grouped = "({m.scrut})" if holdsOperator(m.scrut, [" "]) else m.scrut.copy()
		cond = operand(m.scrut) + guard if core == "true" else "not {grouped}{guard}"
	lead = leadOf(lines[m.header]).copy()
	made = []
	code = codeOf(lines[first].trimmed())
	comment = lines[first].trimmed()[code.len..lines[first].trimmed().len].copy()
	if rest == "":
		# a block: its statements are the if's, one tab less deep
		made.push(("{lead}if {cond}:{m.note}{comment}", -1))
		for k in first + 1..=last:
			made.push((dedented(lines[k]), k))
	else:
		# a statement, on its line or over the lines of what it opens (a nested match)
		made.push(("{lead}if {cond}:{m.note}", -1))
		made.push(("{lead}\t{rest}", first))
		for k in first + 1..=last:
			made.push((lines[k].copy(), k))
	replaceLines(lines, info, m.header, m.close, made)
	true

# the line one tab less deep (a line of a """ string keeps its text)
fn dedented(line str):
	line[1..].copy() if line.startsWith("\t") else line.copy()

# A match giving a value whose first arm gives what it binds (`v: v`) and whose other arm is a
# value of one line (the checker found it of that type): `r ?? value`. Whether it rewrote it.
fn coalesced(mut lines str[], mut info LineInfo[], m MatchLines):
	p = m.prefix
	if m.arms.len != 2 or m.armEnd(0) != m.arms[0] + 1 or m.armEnd(1) != m.arms[1] + 1 or
		not bare(lines[m.arms[0]]) or not bare(lines[m.arms[1]]):
		return false
	p1, r1 = armParts(lines[m.arms[0]])
	p2, r2 = armParts(lines[m.arms[1]])
	if p1 == "" or p1 != r1 or not isPlainName(p1) or p1 == "_" or p2 == "" or r2 == "":
		return false
	# the match stands where a value does: after `=`, `return`, `(`, `, ` or `=>`, or alone as its
	# block's last line (the body's result)
	last = m.close >= lines.len or indentOf(lines[m.close]) < indentOf(lines[m.header])
	if not (
		p.endsWith("= ") or p == "return " or p.endsWith("(") or p.endsWith(", ") or
			p.endsWith("=> ") or p == "" and last
	):
		return false
	if p2 not in ["none", "_", errorWord]: return false
	# a match in parentheses goes on on the line after its arms, with the `)`
	tail = ""
	to = m.close
	if p.endsWith("(") and m.close < lines.len and
		codeOf(lines[m.close].trimmed()).startsWith(")") and
		indentOf(lines[m.close]) == indentOf(lines[m.header]):
		tail = lines[m.close].trimmed().copy()
		to = m.close + 1
	lead = leadOf(lines[m.header]).copy()
	replaceLines(
		lines,
		info,
		m.header,
		to,
		[("{lead}{p}{coalesceOperand(m.scrut)} ?? {coalesceOperand(r2)}{tail}{m.note}", -1)]
	)
	true

# lines [from, to) replaced by made: each line with the line it was copied from (its kind and
# origin kept), or -1 for code a rewrite wrote
fn replaceLines(
	mut lines str[],
	mut info LineInfo[],
	from i64,
	to i64,
	made (str, i64)[]
):
	infos = []
	for (_, origin) in made:
		infos.push(info[origin] if origin >= 0 else LineInfo(kind = 0, stmt = false, origin = 0))
	for _ in from..to:
		lines.remove(from)
		info.remove(from)
	for k, (text, _) in made:
		lines.insert(from + k, text.copy())
		info.insert(from + k, infos[k])

# the parts of a list of values separated by commas at its top level (outside brackets, strings
# and characters), each trimmed
# whether the `<` at k opens a type's arguments: right after a type's name (`Pool<`, `geo.Grid<`),
# where a comparison has a space
fn typeArgumentsAt(s str, k i64):
	w = k
	while w > 0 and s[w - 1].isWordByte():
		w -= 1
	w < k and s[w] >= 'A' and s[w] <= 'Z'

fn topLevelParts(s str):
	parts = []
	depth = 0
	angles = 0   # a type's arguments open: `{i64: Node}` is one part
	from = 0
	k = 0
	while k < s.len:
		b = s[k]
		if b == '"' or b == '\'':
			e = literalEnd(s, k)
			if e < 0: return []
			k = e
			continue
		if b in ['(', '[', '{']:
			depth += 1
		elif b in [')', ']', '}']:
			depth -= 1
		elif b == '<' and typeArgumentsAt(s, k):
			angles += 1
		elif b == '>' and angles > 0:
			angles -= 1
		elif b == ',' and depth == 0 and angles == 0:
			parts.push(s[from..k].trimmed().copy())
			from = k + 1
		k += 1
	parts.push(s[from..].trimmed().copy())
	parts
