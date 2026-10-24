# The formatter, `zap fmt`: one layout for every Zap file, written over the text line by line
# so comments stay where they are. Indentation is meaning, so a statement's line keeps its tabs;
# what fmt lays out is the rest: a line that continues an expression the line before ends with
# an operator is one tab past its statement, a line inside brackets opened on an earlier line
# one tab past the line that opened them (the brackets one line opens count once), and a line
# starting with closing brackets stands with the line that opened them, and a line starting with
# `.` (a chain's step) one past the line its chain goes on from. A line past 100 columns is
# broken, outermost place first (wrap.zap). A comment indented past
# that, aligned with the one before it, keeps its column (a tab counted as four). Trailing spaces
# go, blank lines are at most one in a row and never right after a line that opens a block or a
# bracket, and the file ends with one newline. Kept as written: the lines of a """ string (their
# indentation is part of it). The source a refuses or stops test hands the compiler is laid out
# the same way and otherwise kept as written (it is wrong on purpose).
# Code takes its preferred forms: a lambda that reads a field of its parameter (`m: m.hp` as
# an argument) is that field's function `.hp`, a pipeline step's lambda that only hands its
# parameter to a function of the file (`.map(x: churn(x))`) is that function (`.map(churn)`);
# the shorter forms of rewrite.zap, and those only types tell (the findings zap test's checks
# kept, lint.zap: fmt itself never checks), come first.

import fs

# The text in the layout, its lines ending as its first line does (\r\n or \n): a checkout that
# turned every \n into \r\n stays as it is
pub fn formatSource(text str) str:
	formatFile(text, false, [])

# formatSource for a file: the replacements the checker noted in it first (canon.zap), then the
# rewrites of its lines (rewrite.zap), a GPU file's left out; a .zapx file's lines holding markup
# kept as written but for the markup's indentation (scanmarkup.zap)
pub fn formatFile(text str, gpu bool, mine Note[], markup bool = false) str:
	lines = text.replace("\r", "").lines()
	taken = []   # the lines a replacement over several took
	if not gpu:
		taken = applyNotes(lines, mine)
	coalesce = []
	for n in mine:
		if n.kind == noteCoalesce:
			# the lines replacements took above it out, those they wrote (import lines) in
			added = mine
				.filter(.kind == noteReplace and .line < n.line)
				.map(.text.count('\n'))
				.sum()
			coalesce.push(n.line - taken.filter(it < n.line).len + added)
	if lines.any("\n" in it):
		lines = lines.join("\n").lines()
	formatted = layoutLines(rewriteLines(lines, gpu, coalesce, markup), markup)
	# the long lines broken once each and laid out again, until none changes
	loop:
		broken = layoutLines(breakLongLines(formatted.lines(), markup), markup)
		if broken == formatted: break
		formatted = broken
	first = text.indexOf("\n") ?? -1
	formatted.replace("\n", "\r\n") if first > 0 and text[first - 1] == '\r' else formatted

fn layoutLines(lines str[], markup bool):
	out = []
	sc = LineScanner(markup)   # the brackets, strings and blocks left open (scan.zap)
	blank = false
	fns = unaryFunctions(lines)
	for raw in lines:
		kind = sc.enterLine(raw)
		if kind == lineText:
			out.push(raw.copy())   # the string's own text, spaces included
			continue
		# a refuses or stops test's source is laid out but not rewritten
		kept = kind == lineRaw or sc.keepsText() or raw.trimmed().startsWith("#")
		t = raw .trimmed() .copy() if kept
			else functionArguments(fieldFunctions(raw.trimmed()), fns)
		if t == "":
			blank = not out.isEmpty
			continue
		# the indentation: a chain's step one past its chain; a free line's own; inside brackets,
		# the opener a leading closer matches, else one inside the innermost; a continuation one
		# more than its statement
		indent = indentOf(raw)
		closers = 0 if kind == lineMarkup else leadingClosers(t)
		if kind == lineMarkup:
			indent = sc.markBase + sc.line.depth
		elif isChainStep(t):
			indent = sc.chainBase + 1
		else:
			if not sc.freeLine():
				indent = sc.open[len - 1].base + 1
				if sc.closedOpener(closers) is k: indent = sc.open[k].base
			elif sc.continues:
				indent = sc.stmtIndent
			if sc.continues and closers == 0:
				indent += 1
		if blank and not endsOpener(out.last ?? "") and closers == 0:
			out.push("")
		blank = false
		line = "\t".repeat(indent) + t
		if t.startsWith("#") and kind != lineMarkup and leadingSpaces(raw) > 4 * indent:
			line = raw.trimmedEnd().copy()   # a comment aligned with the one before it
		out.push(line)
		sc.leaveLine(t, indent)
	while not out.isEmpty and out[len - 1] == "":
		out.pop()
	"{out.join("\n")}\n"

# the width of the line's indentation, a tab counted as four columns
fn leadingSpaces(s str):
	width = 0
	n = 0
	while n < s.len and (s[n] == ' ' or s[n] == 9):
		width += 4 if s[n] == 9 else 1
		n += 1
	width

# whether a line opens a block or a bracket: no blank line right after it
fn endsOpener(line str):
	t = codeOf(line.trimmed())
	not t.isEmpty and
		(opensBlock(t) or t[len - 1] == '{' or t[len - 1] == '(' or t[len - 1] == '[')

# ---------- files ----------

# zap fmt path: every file rewritten in the layout, with the findings a check kept for its text
# (lint.zap), the changed ones named; with check, only named. How many changed, or would. A file
# found laid out is known by the hash of its text, its findings and this zap's key (laidOutKeys),
# and not laid out again while they are the same; the others are laid out on every processor at
# once.
pub fn formatPath(path str, check bool) i64:
	all = fs.walk(path, sources = true)
	laidOut = laidOutKeys()
	known = laidOut.len
	compiler = compilerKey()
	files = []
	texts = []
	mines = []
	keys = []
	for f in all:
		text = fs.readFile(f) ?? ""
		mine = keptFindings(f, text)
		key = "{"{compiler}\n{f}\n{text}\n{noteLines(mine)}".hash()}"
		if laidOut.get(key) != none: continue
		files.push(f.copy())
		texts.push(text)
		mines.push(mine)
		keys.push(key)
	outs = (0..files.len)
		.parallel()
		.map(formatFile(texts[it], isGpuFile(files[it]), mines[it], isMarkupFile(files[it])))
	changed = 0
	for i, f in files:
		if outs[i] != texts[i]:
			changed += 1
			print(f)
			if not check:
				_ = fs.writeFile(f, outs[i])
		else:
			laidOut[keys[i].copy()] = true
	if laidOut.len > known:
		_ = fs.createDir(fs.dirOf(laidOutFile()))
		_ = fs.writeFile(laidOutFile(), laidOut.keys().join("\n"))
	changed

# the keys of the files found laid out, kept beside this zap (only the latest ones, past a size)
fn laidOutFile():
	"{fs.dirOf(exePath())}/fmt/laidout.txt"

fn laidOutKeys():
	keys {str: bool} = {}
	lines = (fs.readFile(laidOutFile()) ?? "").lines()
	if lines.len > 50_000: return keys
	for line in lines:
		keys[line.copy()] = true
	keys

# ---------- lambdas as functions ----------

# The line with each argument `m: m.hp`, a lambda that only reads a field of its parameter,
# written as that field's function `.hp`
fn fieldFunctions(line str):
	out = line.copy()
	k = 0
	while k < out.len:
		name, body = lambdaHead(out, k)
		# the lambda starts an argument: right after `(` or `, `
		if name == "" or k >= codeOf(out).len or textPlace(out, k) == 1 or
			not (out[..k].endsWith("(") or out[..k].endsWith(", ")) or
			not out[body..].startsWith("{name}."):
			k += 1
			continue
		end = body + name.len
		while end < out.len and out[end] == '.' and end + 1 < out.len and
			out[end + 1].isWordStart():
			end += 1
			while end < out.len and out[end].isWordByte():
				end += 1
		if end < out.len and (out[end] == ')' or out[end] == ','):
			field = out[body + name.len..end].copy()
			out = out[..k] + field + out[end..]
		k += 1
	out

# the one plain parameter of the lambda that starts at k (`m: `), and where its body starts;
# ("", -1) when no such lambda starts there
fn lambdaHead(s str, k i64):
	if k > 0 and s[k - 1].isWordByte(): return ("", -1)
	end = k
	while end < s.len and s[end].isWordByte():
		end += 1
	if end == k or not s[k].isWordStart() or not s[end..].startsWith(": "): return ("", -1)
	(s[k..end].copy(), end + 2)

# the functions declared at the top of the file that take one plain parameter (read, no default)
# and no type parameters: the ones a lambda `x: f(x)` can be written as `f`
fn unaryFunctions(lines str[]):
	out = []
	for line in lines:
		start = 7 if line.startsWith("pub fn ") else 3 if line.startsWith("fn ") else -1
		if start < 0: continue
		rest = line[start..]
		k = rest.indexOf("(") ?? -1
		if k <= 0: continue
		name = rest[..k]
		close = closingOf(rest, k)
		if close < 0 or not isPlainName(name): continue
		params = rest[k + 1..close - 1]
		if "," in params or "=" in params or "(" in params or params.startsWith("mut ") or
			params.startsWith("move ") or " " not in params:
			continue
		out.push(name.copy())
	out

fn isPlainName(s str):
	not s.isEmpty and s[0].isWordStart() and s.bytes().all(.isWordByte())

# The line with the lambda of a pipeline step that only hands its parameter to one of fns
# written as that function: `.map(x: churn(x))` is `.map(churn)`. A step takes a function of
# the same type its lambda has, so the two mean the same.
fn functionArguments(line str, fns str[]):
	if fns.isEmpty: return line.copy()
	out = line.copy()
	for step in [
		"map",
		"filter",
		"flatMap",
		"any",
		"all",
		"count",
		"sum",
		"sortedBy",
		"minBy",
		"maxBy"
	]:
		pat = ".{step}("
		at = 0
		loop:
			k = out.indexOf(pat, at) ?? -1
			if k < 0: break
			at = k + 1
			if k >= codeOf(out).len or textPlace(out, k) == 1: continue
			open = k + pat.len
			close = closingOf(out, open - 1)
			if close < 0: continue
			name = handedOn(out[open..close - 1], fns)
			if name != "":
				out = out[..open] + name + out[close - 1..]
	out

# f when lam is `x: f(x)` with f one of fns, else ""
fn handedOn(lam str, fns str[]):
	p, body = lambdaHead(lam, 0)
	if p == "": return ""
	rest = lam[body..]
	if fns.find(rest == "{it}({p})") is f: return f.copy()
	""
