# The formatter's rewrites: a form the language takes that says a thing a longer way, written as
# the one form it keeps, so every file says it alike. They work on the lines of a file before it
# is laid out (fmt.zap), on code only: never in a """ string or the source of a test that
# refuses or stops, which may be wrong on purpose, nor in a GPU file (the shader compiler
# reads its forms apart). A rewrite keeps what the program does; one that cannot tell from the
# text leaves it as it is. A line's rewrites:
#   - a method's field assigned through self: self.x = v is x = v (no local takes a field's name);
#   - a statement x = x op e where op takes e whole: x op= e (the parser reads both as one tree);
#   - a variant pattern whose values are all `_`, or none: Rect(_, _) is Rect;
#   - a lambda argument's one parameter in parentheses: (x): ... is x: ...;
#   - `for _ in 0..n:` is `loop n:`;
#   - an integer literal of five digits or more is grouped by `_`: 1_000_000, 0xFFFF_FFFF, 0b1010_0001;
#   - `else if c:` is `elif c:`; `.split("\n")` is `.lines()`;
#   - `(a, b) = (x, y)` is `a, b = x, y`: a tuple taken apart, or given, without parentheses;
#   - a string whose only escapes are `\{`, `\}` and `\\` is raw: r"..." with them bare;
#   - `xs[xs.len - 1]` is `xs[len - 1]`: inside an index's brackets `len` is the list's length;
#   - a slice from the start or to the end is open: `xs[a..len]` is `xs[a..]`, `xs[0..b]` `xs[..b]`;
#   - `i64.parse(args.first ?? "100") ?? 100` is `arg(0, 100)` (rewriteArg.zap);
#   - parentheses around a whole argument, a whole right side or a returned value go:
#     f((a + b)) is f(a + b).
# And a match's (it and its arms on lines of their own, as fmt lays them out):
#   - two arms, one empty and binding nothing (`none: pass`, `_: pass`): if x is v: ...
#     (== none, == literal, a bool as itself);
#   - a value whose first arm gives what it binds (`v: v`) and whose other gives a value of its
#     type, as the checker found (canon.zap): r ?? value (which reads a result's error as error);
#   - arms in a row that bind nothing and do the same: A, B: body.
# The forms only types tell (canon.zap) are applied before these, at the places the checker noted.

# what a line of the file is and where it came from
type LineInfo:
	kind i64   # 0 code, 1 the text of a """ string, 2 the source of a refuses or stops test
	stmt bool   # code that starts a statement: in a block, not going on from the line before
	origin i64   # its line in the file (1-based), 0 for a line a rewrite made

# lines: the file's; gpu: a GPU file's (left as they are); coalesce: the lines of the matches
# the checker found may be written with ??
pub fn rewriteLines(written str[], gpu bool, coalesce i64[], markup bool) str[]:
	lines = written
	if gpu: return lines.map(circleConstants(it))   # a GPU file keeps its layout
	out = []
	info = lineInfos(lines, markup)
	keepsArgs = namesArg(lines)
	src = lines.copy()
	rawBlocks(src, info)
	for i in 0..src.len:
		if info[i].kind != 0 or src[i].trimmed().startsWith("#"):
			out.push(src[i].copy())
			continue
		line = rawStrings(src[i])
		if not keepsArgs: line = argCalls(line)
		if info[i].stmt:
			line = bareTuples(
				repeatLoop(compoundAssigned(thisAssigned(lenInBrackets(line))))
			)
		chained = i + 1 < src.len and isChainStep(src[i + 1].trimmed())
		out.push(
			parenLambdas(
				wildVariants(
					redundantParens(
						angleForms(clampForm(circleConstants(groupedDigits(linesForm(openSlices(lenInBrackets(line))))))),
						chained
					)
				)
			)
		)
	matchRewrites(out, info, coalesce)
	guardRewrites(out, info)
	out

# What each line is, as layoutLines reads them (scan.zap): its kind, and for code whether it
# starts a statement
fn lineInfos(lines str[], markup bool):
	infos = []
	scans = scanLines(lines, markup)
	for i, s in scans:
		infos.push(LineInfo(kind = s.kind, stmt = s.stmt, origin = i + 1))
	infos

# Multi-line strings (\"\"\" at a code line's end, text lines after it, the closing quotes the last
# text line) whose only escapes are `\{`, `\}` and `\\`, with no interpolation: written raw,
# r\"\"\" in front and the escapes bare
fn rawBlocks(mut lines str[], info LineInfo[]):
	i = 0
	while i < lines.len:
		if info[i].kind != 0 or not codeOf(lines[i]).trimmedEnd().endsWith("\"\"\"") or
			codeOf(lines[i]).trimmedEnd().endsWith("r\"\"\""):
			i += 1
			continue
		j = i + 1
		while j < lines.len and info[j].kind == lineText:
			j += 1
		body = lines[i + 1..j]
		if body.any(r"\{" in it) and body.all(rawEscapesOnly):
			code = codeOf(lines[i]).trimmedEnd()
			lines[
				i
			] = "{lines[i][0..code.len - 3]}r{lines[i][code.len - 3..lines[i].len]}"
			for k in i + 1..j:
				lines[k] = bareEscapes(lines[k])
		i = j
		if j == i: i += 1

# whether a string's text holds no escape but `\{`, `\}` and `\\`, and no interpolation
fn rawEscapesOnly(text str):
	k = 0
	while k < text.len:
		b = text[k]
		if b == '\\':
			if k + 1 >= text.len or text[k + 1] not in ['{', '}', '\\']: return false
			k += 2
			continue
		if b == '{': return false
		k += 1
	true

# the escapes `\{`, `\}` and `\\` of a raw string's text written bare
fn bareEscapes(text str):
	out = ""
	k = 0
	while k < text.len:
		if text[k] == '\\' and k + 1 < text.len and text[k + 1] in ['{', '}', '\\']:
			out += text[k + 1..k + 2]
			k += 2
		else:
			out += text[k..k + 1]
			k += 1
	out

# the one-line strings of a code line whose only escapes are `\{`, `\}` and `\\`, with no
# interpolation, written raw
fn rawStrings(line str):
	if r"\{" not in line: return line.copy()
	out = ""
	i = 0
	while i < line.len:
		b = line[i]
		if b == '"' and (i + 2 >= line.len or line[i + 1] != '"' or line[i + 2] != '"') and
			(i == 0 or line[i - 1] != 'r' or i > 1 and line[i - 2].isWordByte()):
			k = i + 1
			interpolated = false
			while k < line.len and line[k] != '"':
				if line[k] == '\\':
					k += 1
				elif line[k] == '{':
					interpolated = true
					break
				k += 1
			if interpolated or k >= line.len: return out + line[i..]
			content = line[i + 1..k]
			if r"\{" in content and rawEscapesOnly(content):
				out += "r\"{bareEscapes(content)}\""
			else:
				out += line[i..k + 1]
			i = k + 1
			continue
		if b == '#' and (i == 0 or line[i - 1] == ' ' or line[i - 1] == 9):
			return out + line[i..]
		out += line[i..i + 1]
		i += 1
	out
