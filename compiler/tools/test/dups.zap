# zap test's dups: code written twice, blocks of six or more lines that are the same once
# comments, names and literals are set aside (a copy with its variables renamed counts), across
# every .zap file of a repository. A clone already known is listed in the repository's
# dups.baseline, one line each (its fingerprint, then where its copies are, for the reader); a
# clone not listed fails the check, so new copies are caught while the known ones are worked off.
# The baseline only shrinks: `zap test --update` takes out the clones that are gone.

import fs

cloneWindow = 6   # code lines in the smallest clone

type CloneSpot:
	file str
	first i64   # 1-based line numbers
	last i64

# a line as the clone search sees it: comments, literals and names gone, keywords kept
fn cloneShape(line str) str:
	out = []
	i = 0
	n = line.len
	while i < n:
		c = line[i]
		if c == '/' and i + 1 < n and line[i + 1] == '/': break
		if c == '"':
			j = i + 1
			while j < n and line[j] != '"':
				j += 2 if line[j] == '\\' else 1
			out.push('S')
			i = j + 1
			continue
		if c >= '0' and c <= '9':
			while i < n and (line[i].isWordByte() or line[i] == '.'):
				i += 1
			out.push('N')
			continue
		if c.isWordByte():
			start = i
			while i < n and line[i].isWordByte():
				i += 1
			word = line[start..i]
			if word in keywords or word == testWord:
				out.extend(word.bytes())
			else:
				out.push('i')
			continue
		if c != ' ' and c != '\t':
			out.push(c)
		i += 1
	str(move out)

# a line that says too little to make a clone of: a brace, an else
fn trivialShape(s str):
	s == "" or s == "}" or s == r"{" or s == r"}else{"

# a field given a literal (`name = "x",`, `size = 4`): a table's data, which repeats its shape by
# design
fn dataShape(s str):
	s.startsWith("i=") and s[2..] in ["S", "S,", "iS", "iS,", "N", "N,"]

type CloneLine:
	number i64
	shape str
	length i64   # of the line as written, trimmed

# the windows of every file, by their fingerprint (the shapes of their lines)
fn cloneWindows(files str[], root str):
	found {str: CloneSpot[]} = {}
	for file in files:
		text = fs.readFile(file) ?? ""
		code = []
		lines = text.replace("\r", "").lines()
		for i, raw in lines:
			t = raw.trimmed()
			s = cloneShape(t)
			if not trivialShape(s) and not dataShape(s) and not t.startsWith("#"):
				code.push(CloneLine(number = i + 1, shape = s, length = t.len))
		from = root.len if file.startsWith(root) else 0
		while from < file.len and file[from] == '/':
			from += 1
		name = file[from..]
		for k in 0..=code.len - cloneWindow:
			part = code[k..k + cloneWindow]
			# a window of mostly the same line, or of very short lines, is no clone worth naming
			if part.sum(.length) < 220 or distinctShapes(part) < cloneWindow - 1: continue
			key = part.map(.shape).join("\n")
			spot = CloneSpot(
				file = name.copy(),
				first = part[0].number,
				last = part[cloneWindow - 1].number
			)
			match found.get(key):
				mut spots: spots.push(spot)
				none: found[key] = [spot]
	found

fn distinctShapes(part CloneLine[]):
	seen str[] = []
	for c in part:
		if c.shape not in seen:
			seen.push(c.shape.copy())
	seen.len

# a short fingerprint of a window's shapes (FNV-1a, 64 bits, as hexadecimal)
fn cloneFingerprint(key str):
	h u64 = 14_695_981_039_346_656_037
	for b in key.bytes():
		h = (h ^ b) * 1_099_511_628_211
	"{h:x}"

# the clones: windows found in two places or more that do not overlap one another, one line each
type FoundClone:
	fingerprint str
	places str

fn clonesFound(found {str: CloneSpot[]}):
	out = []
	for key in found.keys().sorted():
		spots = found[key]
		if spots.len < 2 or spots.len > 8: continue
		if spots.len == 2 and spots[0].file == spots[1].file and spots[1].first <= spots[0].last:
			continue   # a window overlapping itself (a repeated line run)
		where = spots.map("{.file}:{.first}-{.last}").join(" ")
		out.push(FoundClone(cloneFingerprint(key), where))
	out

# The repository at root against its dups.baseline: whether no clone is new. With update, the
# baseline loses the clones that are gone (a new one is never written: it fails until merged).
pub fn dupsCheck(root str, update bool) bool:
	base = root.copy() if root.endsWith("/") else "{root}/"
	# the fuzzers' generated programs are no copies (walking the sources skips build and top dirs)
	files = fs.walk(base, sources = true).filter("/fuzz/" not in it[base.len..])
	found = clonesFound(cloneWindows(files, base))
	baselinePath = "{base}baselines/dups.baseline"
	# a checkout may end the lines with \r\n
	known = (fs.readFile(baselinePath) ?? "").lines().map(.trimmed().split(" ")[0].copy())
	fresh = 0
	for FoundClone(print_, where) in found:
		if print_ not in known:
			print("new clone: {where} (fingerprint {print_})")
			fresh += 1
	gone = known.filter(k: k != "" and not found.any(.fingerprint == k)).len
	if fresh > 0:
		print(
			"{fresh} new clones: merge the copies into one function, or name where the code belongs"
		)
		return false
	if gone > 0 and update:
		_ = fs.createDir(fs.dirOf(baselinePath))
		_ = fs.writeFile(baselinePath, "{found.map("{.fingerprint} {.places}").join("\n")}\n")
		print("{gone} clones gone from {baselinePath}")
	elif gone > 0:
		print("{gone} clones of the baseline are gone: `zap test --update` shrinks it")
	print("no new clones ({found.len} known)")
	true
