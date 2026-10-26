# The markup of a .zapx file as the line scanner reads it (scan.zap): what is open across lines,
# by the lexer's rules (lexMarkup.zap), so zap fmt lays markup out by its nesting and leaves its
# text alone. A line that starts inside markup is indented one past the line its innermost open
# part (a tag, an element's children, a `{...}` of code) started on; a line that closes that part
# stands with it. Inside a `{...}` the blocks its code opens (`{for x in xs:`) count past the first.

import zapx

# a part of markup open at a line's end
type MarkOpen:
	kind i64   # markTag, markKids or markExpr (lexMarkup.zap)
	tag str = ""
	braces i64 = 0   # markExpr: the braces its code opened and has not closed
	blocks i64[] = []   # markExpr: the written indentation of each line whose `:` opened a block in it

# the line's place in markup as enterLine reads it: whether it starts inside markup, whether it
# holds any, its depth, and its code with each markup span written `0`
type MarkLine:
	inside bool = false
	touched bool = false
	opens bool = false   # it starts in code and leaves markup open
	depth i64 = 0
	code str = ""

# What a line of a .zapx file is to markup (t: its text trimmed; written: its indentation as
# written), the parts it opens and closes taken: sc.line says what it was
fn enterMarkupLine(mut sc LineScanner, t str, written i64):
	inside = not sc.marks.isEmpty
	if inside and t != "":
		sc.closeMarkBlocks(written)
	depth = sc.markDepth(t) if inside else 0
	code = sc.maskMarkup(t, written)
	sc.line = MarkLine(
		inside,
		touched = inside or code != t,
		opens = not inside and not sc.marks.isEmpty,
		depth,
		code
	)

# the blocks of the innermost `{...}` that a line written at `written` ends
fn closeMarkBlocks(mut sc LineScanner, written i64):
	last = sc.marks.len - 1
	if sc.marks[last].kind != markExpr: return
	while not sc.marks[last].blocks.isEmpty and written <= sc.marks[last].blocks[len - 1]:
		sc.marks[last].blocks.pop()

# how deep a line starting inside markup stands below the line that opened it
fn markDepth(sc LineScanner, t str):
	d = 0
	for m in sc.marks:
		d += 1 + (m.blocks.len - 1).max(0)
	top = sc.marks[len - 1]
	closes = top.kind == markKids and t.startsWith("</") or
		top.kind == markTag and (t.startsWith(">") or t.startsWith("/>")) or
		top.kind == markExpr and
		(
			t.startsWith("}") or
				top.blocks.isEmpty and (findWord(t, "else", 0) == 0 or findWord(t, "elif", 0) == 0)
		)
	d - (1 if closes else 0)

# t with each span of markup written `0` (a value: what the code around it sees), the parts it
# opens and closes taken
fn maskMarkup(mut sc LineScanner, t str, written i64):
	out = "0" if not sc.marks.isEmpty else ""
	k = 0
	while k < t.len:
		if sc.marks.isEmpty:
			at = markupOpening(t, k)
			if at < 0:
				out += t[k..]
				break
			out = "{out}{t[k..at]}0"
			k = sc.openMark(t, at)
		else:
			kind = sc.marks[len - 1].kind
			k = sc.tagStep(t, k) if kind == markTag else sc.kidsStep(t, k) if kind == markKids
				else sc.codeStep(t, k, written)
	out

# where code from k opens markup (a `<` where an expression starts, before a name or `>`), or -1
fn markupOpening(t str, k i64):
	kinds = byteKinds(t[k..])
	for j, kind in kinds:
		if kind == byteComment: return -1
		at = k + j
		if kind == byteCode and t[at] == '<' and opensMarkup(t, at): return at
	-1

# whether the `<` at `at` opens markup: a name or `>` after it, and before it no value (the
# lexer's valueEnds): the line's start, an operator, an opening bracket or a keyword
fn opensMarkup(t str, at i64):
	if at + 1 >= t.len or not (t[at + 1].isAlpha() or t[at + 1] == '>'): return false
	j = at
	while j > 0 and t[j - 1] == ' ':
		j -= 1
	if j == 0: return true
	b = t[j - 1]
	if b in [')', ']', '}', '"', '\'']: return false
	if not b.isWordByte(): return true
	start = j
	while start > 0 and t[start - 1].isWordByte():
		start -= 1
	keywordKind(t[start..j]) >= 0 and t[start..j] not in ["true", "false", "none", "this", "it"]

# the tag opening at `at` pushed: where the scan goes on
fn openMark(mut sc LineScanner, t str, at i64):
	k = at + 1
	while k < t.len and (t[k].isWordByte() or t[k] in ['-', ':', '.']):
		k += 1
	tag = t[at + 1..k].copy()
	if tag == "" and k < t.len and t[k] == '>':
		sc.marks.push(MarkOpen(markKids))   # a fragment
		return k + 1
	sc.marks.push(MarkOpen(markTag, tag))
	k

fn tagStep(mut sc LineScanner, t str, k i64):
	b = t[k]
	last = sc.marks.len - 1
	if b == '"':
		end = stringEnd(t, k)
		return t.len if end < 0 else end
	if b == '{':
		sc.marks.push(MarkOpen(markExpr))
		return k + 1
	if b == '/' and k + 1 < t.len and t[k + 1] == '>':
		sc.marks.pop()
		return k + 2
	if b == '>':
		if zapx.isVoid(sc.marks[last].tag):
			sc.marks.pop()
		else:
			sc.marks[last].kind = markKids
	k + 1

fn kidsStep(mut sc LineScanner, t str, k i64):
	b = t[k]
	if b == '<' and k + 1 < t.len and t[k + 1] == '/':
		end = t.indexOf(">", k) ?? t.len - 1
		sc.marks.pop()
		return end + 1
	if b == '<' and k + 1 < t.len and (t[k + 1].isAlpha() or t[k + 1] == '>'):
		return sc.openMark(t, k)
	if b == '{':
		sc.marks.push(MarkOpen(markExpr))
	k + 1

# code inside a `{...}` from k: up to its `}`, to markup it opens or to the line's end, where a
# `:` ending it opens a block
fn codeStep(mut sc LineScanner, t str, k i64, written i64):
	last = sc.marks.len - 1
	kinds = byteKinds(t[k..])
	for j, kind in kinds:
		at = k + j
		if kind == byteComment: break
		if kind != byteCode: continue
		b = t[at]
		if b == '<' and opensMarkup(t, at): return sc.openMark(t, at)
		if b == '{':
			sc.marks[last].braces += 1
		elif b == '}' and sc.marks[last].braces == 0:
			sc.marks.pop()
			return at + 1
		elif b == '}':
			sc.marks[last].braces -= 1
	if opensBlock(codeOf(t[k..])):
		sc.marks[last].blocks.push(written)
	t.len
