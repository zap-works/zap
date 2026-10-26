# The rewrite to arg(i, default) (checkArg.zap): `T.parse(args.first ?? "d") ?? d` and
# `T.parse(args[i] if args.len > i else "d") ?? d`, d a number literal written as the text is, are
# `arg(i, d)`. A different command line is not made: only a malformed argument stops the program
# now where the default ran before. The type stays: arg(i, 100) is an i64 and arg(i, 1.0) an f64,
# so `size = i32.parse(...) ?? 100`, a new binding the checker finds (noteArgBinding), is
# `size i32 = arg(0, 100)`, and any other place of another type keeps its form. A file that
# names `arg` itself keeps them all.

numberTypes = ["i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64", "f32", "f64"]

# a `T.parse(...) ?? d` of a line's code, read from the command line
pub type ArgForm:
	start i64   # where `T.parse(` starts
	end i64   # after the default
	numberType str
	index i64
	literal str   # the default as written

# the line's forms, left to right, none overlapping
fn argForms(code str):
	if ".parse(" not in code: return []
	kinds = byteKinds(code)
	found = []
	for t in numberTypes:
		at = 0
		while at < code.len:
			k = findWord(code, "{t}.parse(", at)
			if k < 0: break
			at = k + 1
			if kinds[k] != byteCode or k > 0 and code[k - 1] == '.': continue
			open = k + t.len + 6
			close = closingOf(code, open)
			if close < 0 or not code[close..].startsWith(" ?? "): continue
			index, text = argRead(code[open + 1..close - 1])
			size = numberLiteralLength(code[close + 4..])
			if index < 0 or size == 0: continue
			literal = code[close + 4..close + 4 + size]
			if literal.replace("_", "") != text.replace("_", ""): continue
			found.push(ArgForm(k, close + 4 + size, t.copy(), index, literal.copy()))
	found.sortedBy(.start)

# the argument position and the default's text of `args.first ?? "d"` or
# `args[i] if args.len > i else "d"` (-1 for anything else)
fn argRead(inner str):
	first = "args.first ?? \""
	if inner.startsWith(first) and inner.endsWith("\""):
		text = inner[first.len..len - 1]
		if not plainText(text): return (-1, "")
		return (0, text.copy())
	if not inner.startsWith("args["): return (-1, "")
	close = inner.indexOf("]") ?? -1
	digits = inner[5..close] if close > 5 else ""
	if digits.isEmpty or not onlyBytes(digits, "0123456789"): return (-1, "")
	lead = "args[{digits}] if args.len > {digits} else \""
	if not inner.startsWith(lead) or not inner.endsWith("\"") or inner.len < lead.len + 1:
		return (-1, "")
	text = inner[lead.len..len - 1]
	if not plainText(text): return (-1, "")
	(i64.parse(digits) ?? -1, text.copy())

# whether the text of a string holds no escape and no interpolation
fn plainText(text str):
	"\"" not in text and "\\" not in text and r"{" not in text

# whether every byte of s is one of allowed
fn onlyBytes(s str, allowed str):
	k = 0
	while k < s.len:
		if s[k..k + 1] not in allowed: return false
		k += 1
	true

# the length of the number literal that starts s and ends the operand (before `)`, `,`, `]`, `}`
# or the end), 0 when s does not start so
fn numberLiteralLength(s str):
	j = 1 if s.startsWith("-") else 0
	if j >= s.len or not s[j].isDigit(): return 0
	while j < s.len:
		if s[j].isWordByte() or s[j] == '.' and j + 1 < s.len and s[j + 1].isDigit():
			j += 1
		else:
			break
	j if j == s.len or s[j] in [')', ',', ']', '}'] or s[j..].trimmed().isEmpty else 0

# whether `arg(i, d)` has the type T gives the parse: an i64 for an integer literal, an f64 for
# one with a point
fn keepsType(f ArgForm):
	whole = onlyBytes(f.literal, "0123456789_-") or f.literal.startsWith("0x") or
		f.literal.startsWith("0b")
	f.numberType == "i64" and whole or f.numberType == "f64" and "." in f.literal

# the line's forms that keep their type written as arg(i, d)
fn argCalls(line str):
	code = codeOf(line)
	forms = argForms(code)
	out = line.copy()
	for k in 0..forms.len:
		f = forms[len - 1 - k]
		if f.keepsType():
			out = "{out[..f.start]}arg({f.index}, {f.literal}){out[f.end..]}"
	out

# whether a code line names `arg` other than as a call (a local, a parameter, a field) or defines
# a function of that name: then `arg(` there may mean something else. A file already written
# with arg(i, d) does not.
fn namesArg(lines str[]):
	lines.any(namesArgIn(codeOf(it)))

fn namesArgIn(code str):
	at = findWord(code, "arg", 0)
	while at >= 0:
		after = at + 3
		if after >= code.len or code[after] != '(' or code[..at].trimmedEnd().endsWith("fn"):
			return true
		at = findWord(code, "arg", after)
	false

# `size = i32.parse(args.first ?? "100") ?? 100`, a new binding without a type written: noted
# as `size i32 = arg(0, 100)`, which keeps its type (checkLetNew)
fn noteArgBinding(mut c Checker, s NodeId, vt TypeId):
	if not noting: return
	line = c.nodes[s].line
	src = c.file if c.curFile == "" else c.curFile
	text = sourceLineOf(src, line)
	code = codeOf(text)
	name = c.nodes[s].text
	p = code.len - code.trimmedStart().len
	if code[p..].startsWith("mut "):
		p += 4
	start = p + name.len
	if not code[p..].startsWith("{name} = "): return
	if c.lookupVarQuiet("arg") or c.lookupDecl(nFnDecl, "", "arg", line, 1) != none: return
	forms = argForms(code)
	if forms.len != 1 or forms[0].start != start + 3 or forms[0].end != code.len: return
	f = forms[0]
	if f.keepsType() or f.numberType != c.showTy(vt): return
	c.canonNote(
		noteReplace,
		line,
		start + 1,
		code.len - start,
		" {f.numberType} = arg({f.index}, {f.literal})"
	)
