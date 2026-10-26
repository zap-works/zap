# The line rewrites of forms with an operand: slices, ranges, digit groups, constants, clamps and angles (rewrite.zap).

# `xs[xs.len - 1]`, `xs.items[i + xs.items.len]`: inside an index's brackets, the indexed
# place's own `.len` is `length`
fn lenInBrackets(line str):
	if ".len" not in line: return line.copy()
	out = line.copy()
	k = out.indexOf("[") ?? -1
	while k >= 0:
		kinds = byteKinds(out)
		place = kinds[k] == byteCode and k > 0 and
			(out[k - 1].isWordByte() or out[k - 1] == ']' or out[k - 1] == ')')
		start = placeStart(out, k) if place else -1
		close = closingOf(out, k) if start >= 0 else -1
		if start >= 0 and close >= 0:
			base = out[start..k]
			inner = out[k + 1..close - 1]
			if "(" not in base and "{base}.len" in inner:
				out = out[..k + 1] + ownLenAsLen(inner, base) + out[close - 1..]
		k = out.indexOf("[", k + 1) ?? -1
	out

# inner, the brackets' text after the place base, with base's own `.len` written `len`: not
# another name's that ends alike (`it.len` in `t[...]`), not one in a literal, not one in nested
# brackets (whose `len` is their list's)
fn ownLenAsLen(inner str, base str):
	own = "{base}.len"
	out = ""
	depth = 0
	from = 0
	j = 0
	while j < inner.len:
		b = inner[j]
		if b == '"' or b == '\'':
			j = literalEnd(inner, j)
			if j < 0: return out + inner[from..]
			continue
		if depth == 0 and inner[j..].startsWith(own) and
			(j == 0 or not inner[j - 1].isWordByte() and inner[j - 1] != '.') and
			(j + own.len == inner.len or not inner[j + own.len].isWordByte()):
			out = "{out}{inner[from..j]}len"
			j += own.len
			from = j
			continue
		if b == '[':
			depth += 1
		elif b == ']':
			depth -= 1
		j += 1
	out + inner[from..]

# `xs[a..len]` and `xs[a..xs.len]` are `xs[a..]`, `xs[0..b]` is `xs[..b]`: an index's one range
# (no step, not `..=`) open at the start or the end, in code and in an interpolation's
fn openSlices(line str):
	if ".." not in line: return line.copy()
	out = line.copy()
	k = out.indexOf("[") ?? -1
	while k >= 0:
		kinds = byteKinds(out)
		code = kinds[k] == byteCode or kinds[k] == byteInner
		place = code and k > 0 and
			(out[k - 1].isWordByte() or out[k - 1] == ']' or out[k - 1] == ')')
		start = placeStart(out, k) if place else -1
		close = closingOf(out, k) if start >= 0 else -1
		if close >= 0:
			opened = openRange(out[k + 1..close - 1], out[start..k])
			if opened != "":
				out = out[..k + 1] + opened + out[close - 1..]
		k = out.indexOf("[", k + 1) ?? -1
	out

# the brackets' text inner (of the place base) with its range written open, or "" when it is not
# one range open at an end
fn openRange(inner str, base str):
	depth = 0
	dots = -1
	j = 0
	while j < inner.len:
		b = inner[j]
		if b == '"' or b == '\'':
			j = literalEnd(inner, j)
			if j < 0: return ""
			continue
		if b in ['(', '[', '{']:
			depth += 1
		elif b in [')', ']', '}']:
			depth -= 1
		elif depth == 0 and b == ',':
			return ""
		elif depth == 0 and b == '.' and j + 1 < inner.len and inner[j + 1] == '.':
			if dots >= 0: return ""
			dots = j
			j += 1
		j += 1
	if dots < 0 or dots + 2 < inner.len and inner[dots + 2] == '=': return ""
	lo = inner[..dots].trimmed()
	hi = inner[dots + 2..].trimmed()
	if " step " in " {hi} " or lo == "" or hi == "": return ""
	toEnd = hi == "len" or "(" not in base and hi == "{base}.len"
	if lo == "0" and toEnd: return ".."
	if toEnd: return "{lo}.."
	if lo == "0": return "..{hi}"
	""

# the start of the place written before the `[` at k: a chain of names, fields, indexes and calls
fn placeStart(text str, k i64):
	i = k
	while i > 0:
		b = text[i - 1]
		if b.isWordByte() or b == '.':
			i -= 1
		elif b == ']' or b == ')':
			open = openingOf(text, i - 1)
			if open < 0: return -1
			i = open
		else:
			break
	if i == k or not text[i].isWordStart(): return -1
	i

# ---------- one line ----------

# `.split("\n")` of the line's code is `.lines()`, a list of the lines as a for over them goes (a
# carriage return before a newline left out, nothing after a final one)
fn linesForm(line str):
	split = ".split(\"\\n\")"
	if split not in line: return line.copy()
	kinds = byteKinds(line)
	out = ""
	i = 0
	while i < line.len:
		if kinds[i] == byteCode and line[i..].startsWith(split):
			out += ".lines()"
			i += split.len
		else:
			out += line[i..i + 1]
			i += 1
	out

# Every integer literal of the line's code of five digits or more written with `_` between its
# groups: of three for decimal, of four for hexadecimal and binary (a float keeps its digits)
fn groupedDigits(line str):
	kinds = byteKinds(line)
	out = ""
	i = 0
	while i < line.len:
		b = line[i]
		if kinds[i] != byteCode or not b.isDigit() or
			i > 0 and (line[i - 1].isWordByte() or line[i - 1] == '.'):
			out += line[i..i + 1]
			i += 1
			continue
		j = i
		base = 10
		if b == '0' and i + 1 < line.len and (line[i + 1] == 'x' or line[i + 1] == 'X'):
			base = 16
			j += 2
		elif b == '0' and i + 1 < line.len and (line[i + 1] == 'b' or line[i + 1] == 'B'):
			base = 2
			j += 2
		digitsFrom = j
		while j < line.len and
			(line[j] == '_' or (isHexDigit(line[j]) if base == 16 else line[j].isDigit())):
			j += 1
		isFloat = base == 10 and j < line.len and
			(
				line[j] == 'e' or line[j] == 'E' or
					line[j] == '.' and j + 1 < line.len and line[j + 1].isDigit()
			)
		digits = line[digitsFrom..j].replace("_", "")
		if isFloat or digits.len < 5 or j < line.len and line[j].isWordByte():
			out += line[i..j]
			i = j
			continue
		group = 3 if base == 10 else 4
		grouped = ""
		for k in 0..digits.len:
			if k > 0 and (digits.len - k) % group == 0:
				grouped += "_"
			grouped += digits[k..k + 1]
		out += line[i..digitsFrom] + grouped
		i = j
	out

# A float literal of the line's code that is pi or tau to seven decimals or more written `pi` or
# `tau`: the constants of the language
fn circleConstants(line str):
	kinds = byteKinds(line)
	out = ""
	i = 0
	while i < line.len:
		b = line[i]
		if kinds[i] != byteCode or not b.isDigit() or
			i > 0 and (line[i - 1].isWordByte() or line[i - 1] == '.'):
			out += line[i..i + 1]
			i += 1
			continue
		j = i
		while j < line.len and (line[j].isDigit() or line[j] == '.' or line[j] == '_'):
			j += 1
		text = line[i..j].replace("_", "")
		if j < line.len and line[j].isWordByte() or text.split(".").len != 2:
			out += line[i..j]
		elif text.startsWith("3.141592") and text.len >= 9: out += "pi"
		elif text.startsWith("6.283185") and text.len >= 9: out += "tau"
		else:
			out += line[i..j]
		i = j
	out

# `.max(lo).min(hi)` of the line's code is `.clamp(lo, hi)` (the other order is not: it gives lo
# when lo > hi, where clamp gives hi)
fn clampForm(line str):
	out = line.copy()
	k = 0
	while k + 5 < out.len:
		if out[k..k + 5] != ".max(" or byteKinds(out)[k] != byteCode:
			k += 1
			continue
		c1 = closingOf(out, k + 4)
		if c1 < 0 or not out[c1..].startsWith(".min("):
			k += 1
			continue
		c2 = closingOf(out, c1 + 4)
		lo = out[k + 5..c1 - 1].copy()
		hi = out[c1 + 5..c2 - 1].copy()
		if c2 < 0 or lo.trimmed() == "" or hi.trimmed() == "" or topLevelParts(lo).len != 1 or
			topLevelParts(hi).len != 1:
			k += 1
			continue
		out = "{out[..k]}.clamp({lo}, {hi}){out[c2..]}"
		k += 1
	out

# `x * pi / 180.0`, `x * (pi / 180.0)` and `pi / 180.0 * x` of the line's code are `x.radians()`;
# with 180.0 and pi the other way round, `x.degrees()`. The operand is a name, a field chain, a
# call or a parenthesised value, taken whole by the multiplication (nothing divides it before); not
# a number literal, whose method would fix it as an f64 where the product takes its place's type.
fn angleForms(line str):
	out = line.copy()
	after = [
		(" * pi / 180.0", "radians"),
		(" * (pi / 180.0)", "radians"),
		(" * 180.0 / pi", "degrees"),
		(" * (180.0 / pi)", "degrees")
	]
	for (form, method) in after:
		k = out.indexOf(form) ?? -1
		while k >= 0:
			end = k + form.len
			start = operandStart(out, k)
			if byteKinds(out)[k] == byteCode and start >= 0 and
				not (end < out.len and (out[end].isWordByte() or out[end] == '.')):
				out = "{out[..start]}{out[start..k]}.{method}(){out[end..]}"
			rest = out[k + 1..].indexOf(form) ?? -1
			k = -1 if rest < 0 else k + 1 + rest
	before = [("pi / 180.0 * ", "radians"), ("180.0 / pi * ", "degrees")]
	for (form, method) in before:
		k = out.indexOf(form) ?? -1
		while k >= 0:
			from = k + form.len
			end = operandEnd(out, from)
			if byteKinds(out)[k] == byteCode and end >= 0 and
				not (k > 0 and (out[k - 1].isWordByte() or out[k - 1] in ['.', '/', '%'])):
				out = "{out[..k]}{out[from..end]}.{method}(){out[end..]}"
			rest = out[k + 1..].indexOf(form) ?? -1
			k = -1 if rest < 0 else k + 1 + rest
	out

# where the operand ending at k (exclusive) starts, -1 when it is not one a method may take whole
fn operandStart(s str, k i64):
	j = k
	if j > 0 and s[j - 1] == ')':
		j = openingOf(s, j - 1)
		if j < 0: return -1
	elif j > 0 and s[j - 1] == ']':
		return -1
	while j > 0 and (s[j - 1].isWordByte() or s[j - 1] == '.'):
		j -= 1
	if j == k or s[j].isDigit(): return -1
	b = j - 1
	while b >= 0 and s[b] == ' ':
		b -= 1
	if b < 0 or s[b] in ['(', ',', '=', '+', '-', '*', '[', ':', '\t']: return j
	if b < j - 1 and s[b].isWordByte(): return j   # `return x`, `elif x`: a word before a space
	-1

# where the operand starting at from ends (exclusive), -1 when it is not one a method may take whole
fn operandEnd(s str, from i64):
	e = from
	if e < s.len and s[e] == '(':
		e = closingOf(s, e)
		return e if e > 0 else -1
	while e < s.len and (s[e].isWordByte() or s[e] == '.'):
		e += 1
	if e == from or s[from].isDigit(): return -1
	if e < s.len and s[e] == '(':
		e = closingOf(s, e)
		if e < 0: return -1
	if e < s.len and s[e] == '[': return -1
	e

fn isHexDigit(b u8):
	b.isDigit() or b >= 'a' and b <= 'f' or b >= 'A' and b <= 'F'

# the index of the `(` that the `)` at i closes, or -1
fn openingOf(s str, i i64):
	kinds = byteKinds(s)
	depth = 0
	k = i
	while k >= 0:
		if kinds[k] == byteCode and s[k] == ')':
			depth += 1
		elif kinds[k] == byteCode and s[k] == '(':
			depth -= 1
			if depth == 0: return k
		k -= 1
	-1
