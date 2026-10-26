# The line rewrites of loops, tuples, parentheses, assignments and patterns (rewrite.zap).

# `(a, b) = v` is `a, b = v`, and a right side `(x, y)` whole is `x, y` when the left names no type
# (after a declared type the bare tuple would not parse)
fn bareTuples(line str):
	out = line.copy()
	t = out.trimmed()
	lead = leadOf(out)
	if t.startsWith("("):
		close = closingOf(t, 0)
		if close > 0 and t[close..].startsWith(" = "):
			inner = t[1..close - 1]
			parts = topLevelParts(inner)
			if parts.len >= 2 and parts.all(isPlainName(.trimmed()) or .trimmed() == "_"):
				out = lead + inner + t[close..]
	code = codeOf(out)
	eq = code.indexOf(" = (") ?? -1
	if eq >= 0 and code.trimmedEnd().endsWith(")") and "(" not in code[..eq] and
		not namesType(code[..eq]):
		open = eq + 3
		close = closingOf(code, open)
		if close == code.trimmedEnd().len:
			inner = code[open + 1..close - 1]
			if topLevelParts(inner).len >= 2 and not inner.trimmed().startsWith("fn "):
				out = out[..open] + inner + out[close..]
	out

# whether an assignment's left side declares a type: a part past `mut` holding a space
fn namesType(left str):
	target = left.trimmed()
	start = 4 if target.startsWith("mut ") else 0
	topLevelParts(target[start..]).any(" " in .trimmed())

# `for _ in 0..n:` is `loop n:`
fn repeatLoop(line str):
	t = line.trimmed()
	if t.startsWith("for _ in 0..") and codeOf(t).trimmedEnd().endsWith(":") and
		not t.startsWith("for _ in 0..="):
		return "{leadOf(line)}loop {t[12..]}"
	line.copy()

# Parentheses around a whole argument (`f((a + b))`), a whole right side (`x = (a + b)`) or a
# returned value gone, as long as they hold one value (a tuple keeps its own) and are not a
# lambda's parameters (`(x i64):`); those ending a line a chain's step goes on from (`(0..n)` / `.map(f)`)
# stay: they are the step's receiver
fn redundantParens(line str, chained bool):
	out = line.copy()
	again = true
	while again:
		again = false
		kinds = byteKinds(out)
		for k, kind in kinds:
			if kind != byteCode or out[k] != '(': continue
			before = out[..k].trimmedEnd()
			opens = before.endsWith("(") or before.endsWith(",") or before.endsWith("return") or
				(
					before.endsWith("=") and not before.endsWith("==") and
						not before.endsWith("!=") and not before.endsWith("<=") and
						not before.endsWith(">=") and not before.endsWith("=>")
				)
			if not opens or before.endsWith("fn") or before == "": continue
			close = closingOf(out, k)
			if close < 0: continue
			after = codeOf(out)[close.min(codeOf(out).len)..codeOf(out).len].trimmedStart()
			closes = after.startsWith(")") or after.startsWith(",") or after.startsWith("]")
			if not (after == "" and not chained or closes) or after.startsWith(":"): continue
			inner = out[k + 1..close - 1]
			if inner.trimmed() == "" or topLevelParts(inner).len != 1 or
				inner.trimmed().startsWith("fn "):
				continue
			out = out[..k] + inner + out[close..]
			again = true
			break
	out

# the line's indentation (a window into it)
fn leadOf(line str) ref str:
	line[..len - line.trimmedStart().len]

# `this.total += x` (a statement assigning a field of this, or a part of one) is `total += x`
fn thisAssigned(line str):
	t = line.trimmed()
	if not t.startsWith("self.") or t.len < 6 or not t[5].isWordStart(): return line.copy()
	# the place: this.name, then .field or [index] parts, then = or op=
	k = 5
	while k < t.len and t[k].isWordByte():
		k += 1
	going = true
	while going and k < t.len:
		if t[k] == '.' and k + 1 < t.len and t[k + 1].isWordStart():
			k += 1
			while k < t.len and t[k].isWordByte():
				k += 1
		elif t[k] == '[':
			close = closingOf(t, k)
			if close < 0: return line.copy()
			k = close
		else:
			going = false
	rest = t[k..]
	assigns = rest.startsWith(" = ") or compoundTexts().any(rest.startsWith(" {it}= "))
	if not assigns: return line.copy()
	leadOf(line) + t[5..]

# `x = x + e` (a statement whose value is its target, an operator of x op= and a value that
# operator takes whole) is `x += e`: the parser reads x op= e as x = x op e, one tree. The target
# is a name with fields and indexes that call nothing (a compound target's call is computed once
# first).
fn compoundAssigned(line str):
	t = line.trimmed()
	code = codeOf(t)
	eq = code.indexOf(" = ") ?? -1
	if eq <= 0 or code.startsWith("mut "): return line.copy()
	target = code[..eq]
	value = code[eq + 3..]
	# the target read again, or through this (a method's field, which its bare name is)
	read = "self.{target}" if value.startsWith("self.{target} ") else target.copy()
	if not isPlainPlace(target) or not value.startsWith("{read} ") or value.len < read.len + 3:
		return line.copy()
	rest = value[read.len + 1..]
	for op in compoundTexts():
		if rest.startsWith("{op} "):
			operand = rest[op.len + 1..].trimmed().copy()
			if not wholeOperand(operand, operatorLevel(op)): return line.copy()
			if operand.startsWith("(") and closingOf(operand, 0) == operand.len and
				topLevelParts(operand[1..len - 1]).len == 1:
				operand = operand[1..len - 1].copy()   # x op= takes its value whole
			return "{leadOf(line)}{target} {op}= {operand}{t[code.len..]}"
	line.copy()

# whether s is a place written plainly: a name, then fields and indexes holding no call
fn isPlainPlace(s str):
	if s.isEmpty or not s[0].isWordStart(): return false
	k = 0
	while k < s.len and s[k].isWordByte():
		k += 1
	while k < s.len:
		if s[k] == '.' and k + 1 < s.len and s[k + 1].isWordStart():
			k += 1
			while k < s.len and s[k].isWordByte():
				k += 1
		elif s[k] == '[':
			close = closingOf(s, k)
			if close < 0: return false
			inner = s[k + 1..close - 1]
			if "(" in inner or "?" in inner or "\"" in inner or "'" in inner or r"{" in inner:
				return false
			k = close
		else:
			return false
	true

# the parser's level of a binary operator (lower binds tighter); a text that is none ranks looser
# than all
fn operatorLevel(op str):
	code = binaryCode(op)
	binaryOperators[code].level if code >= 0 else binaryOperators.len

# whether the value r, written after `x op `, is one operand of op whole: each operator at its top
# level (outside brackets and strings) binds tighter than `level`, and it holds no block, range,
# condition or other construct; when unsure, no
fn wholeOperand(r str, level i64):
	if r == "" or bracketDelta(r) != 0 or endsWithOperator(r): return false
	k = 0
	operand = false   # whether a value ends right before k
	while k < r.len:
		b = r[k]
		if b == ' ':
			k += 1
			continue
		if b == '"' or b == '\'':
			k = literalEnd(r, k)
			if k < 0: return false
			operand = true
			continue
		if b.isWordByte():
			start = k
			while k < r.len and r[k].isWordByte():
				k += 1
			kw = keywordKind(r[start..k])
			if kw in [tkAnd, tkOr, tkNot]:
				operand = false   # an operator written as a word
				continue
			if kw >= 0 and kw != tkTrue and kw != tkFalse and kw != tkNone and kw != tkThis:
				return false   # a keyword other than a value's starts a construct
			operand = true
			continue
		if b == '(' or b == '[':
			close = closingOf(r, k)
			if close < 0: return false
			k = close
			operand = true
			continue
		if b == '.':
			if k + 1 < r.len and r[k + 1] == '.':
				return false   # a range
			k += 1   # a field, a method, a number's decimals
			continue
		if b == '?':
			# x?.f is postfix; a condition's ` ? ` and ?? bind loosely
			if operand and k + 1 < r.len and (r[k + 1] == ' ' or r[k + 1] == '?'): return false
			if not operand: return false
			k += 1
			continue
		e = k
		while e < r.len and r[e..e + 1] in "+-*/%@&|^<>=!~":
			e += 1
		if e == k:
			return false   # a byte no value or operator starts
		op = r[k..e]
		if operand:
			if operatorLevel(op) >= level: return false
			operand = false
		elif op != "-" and op != "!" and op != "~":
			return false
		k = e
	operand

# The pattern parts of a line: before an arm's top-level `:` (up to its condition), and each
# pattern after ` is `. Their variants whose values are all `_`, or that have none written, take
# no parentheses: `Rect(_, _)` is `Rect`, as a variant alone matches whatever it holds.
fn wildVariants(line str):
	out = line.copy()
	changed = true
	while changed:
		changed = false
		for (from, to) in patternSpans(out):
			at = bareVariantIn(out, from, to)
			if at >= 0:
				close = closingOf(out, at)
				out = out[..at] + out[close..]
				changed = true
				break
	out

# where the line's patterns lie, [from, to) each: an arm's (before its `:` at the line's top
# level, its condition left out) and an `is` test's
fn patternSpans(line str):
	spans = []
	code = codeOf(line).copy()
	t = code.trimmedStart().copy()
	lead = code.len - t.len
	colon = armColon(t)
	if colon > 0:
		guard = conditionAt(t[..colon])
		spans.push((lead, lead + (guard if guard >= 0 else colon)))
	at = findWord(code, "is ", 0)
	while at >= 0:
		if at > 0 and code[at - 1] == ' ' and textPlace(code, at) == 0:
			e = at + 3
			while e < code.len and code[e].isWordByte():
				e += 1
			if e < code.len and code[e] == '(':
				e = closingOf(code, e)
			if e > at + 3:
				spans.push((at + 3, e))
		at = findWord(code, "is ", at + 1)
	spans

# the words that start a statement or a declaration, never a pattern
heads = [
	"if ",
	"else",
	"elif ",
	"while ",
	"for ",
	"match ",
	"fn ",
	"mut ",
	"pub ",
	"type ",
	"shared ",
	"extern ",
	"bound ",
	"test ",
	"loop",
	"return",
	"import ",
	"parts ",
	"break",
	"continue",
	"alias ",
	"use "
]

# where the `:` of an arm `pattern: body` is in the trimmed code of a line, or -1: a tight colon at
# the top level of a line that starts with no statement's word and assigns nothing before it
fn armColon(t str):
	if heads.any(t == .trimmedEnd() or t.startsWith(it)): return -1
	k = topColon(t)
	k if k > 0 and " = " not in t[..k] else -1

# where the top-level tight `:` of a line's code is (outside brackets and strings, no space
# before it, a space or the end after it), or -1
fn topColon(code str):
	depth = 0
	k = 0
	while k < code.len:
		b = code[k]
		if b == '"' or b == '\'':
			k = literalEnd(code, k)
			if k < 0: return -1
			continue
		if b in ['(', '[', '{']:
			depth += 1
		elif b in [')', ']', '}']:
			depth -= 1
		elif depth == 0 and b == ':' and k > 0 and code[k - 1] != ' ' and
			(k + 1 == code.len or code[k + 1] == ' '):
			return k
		k += 1
	-1

# where the `(` of a variant written with parentheses that hold only `_`s, or nothing, opens in
# [from, to) of the line (its name capitalized, not a field's), or -1
fn bareVariantIn(s str, from i64, to i64):
	k = from
	while k < to:
		if s[k] == '(' and k > from and s[k - 1].isWordByte():
			n = k
			while n > from and s[n - 1].isWordByte():
				n -= 1
			close = closingOf(s, k)
			if s[n] >= 'A' and s[n] <= 'Z' and (n == 0 or s[n - 1] != '.') and close > 0 and
				close <= to:
				inner = s[k + 1..close - 1].replace(" ", "")
				if inner == "" or inner.split(",").all(it == "_"): return k
		if s[k] == '"' or s[k] == '\'':
			e = literalEnd(s, k)
			if e < 0: return -1
			k = e
			continue
		k += 1
	-1

# A lambda argument whose one parameter is in parentheses, `(x): ...` right after `(` or `, `,
# is `x: ...` (the parser reads both alike)
fn parenLambdas(line str):
	out = line.copy()
	at = 0
	loop:
		k = out.indexOf("(", at) ?? -1
		if k < 0: return out
		at = k + 1
		if k >= codeOf(out).len or textPlace(out, k) == 1: continue
		before = out[..k]
		if not before.endsWith("(") and not before.endsWith(", "): continue
		e = k + 1
		while e < out.len and out[e].isWordByte():
			e += 1
		if e == k + 1 or not out[k + 1].isWordStart() or not out[e..].startsWith("): "): continue
		out = out[..k] + out[k + 1..e] + out[e + 1..]
	out

# ---------- matches ----------
