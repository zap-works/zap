# zap test's limits: no .zap file over 1,000 lines and no function body over 100 lines, across
# every .zap file of a repository. A table file, or a function that is one line per arm (a
# dispatch), is exempt by a comment line `# long: why` at the top of the file (in its leading
# comment block) or directly above the function (in the comment block over its `fn`).

import fs

maxFileLines = 1000
maxBodyLines = 100
longMark = "# long:"

# whether the comment block that ends just above line `at` holds the mark
fn markedAbove(lines str[], at i64):
	k = at - 1
	while k >= 0 and lines[k].startsWith("#"):
		if lines[k].startsWith(longMark): return true
		k -= 1
	false

# whether the comment block that opens the file holds the mark
fn markedAtTop(lines str[]):
	for line in lines:
		if line.startsWith(longMark): return true
		if line.trimmed() != "" and not line.startsWith("#"): return false
	false

# The last line of the function whose header is line `at`: the last indented or closing line
# before the next statement at the left margin.
fn lastLineOf(lines str[], at i64):
	last = at
	k = at + 1
	while k < lines.len:
		line = lines[k]
		if line.trimmed() == "" or line.startsWith("#"):
			k += 1
			continue
		first = line[0]
		if first != ' ' and first != '\t' and first != ')' and first != ']' and first != '}': break
		last = k
		k += 1
	last

fn relativeTo(file str, base str):
	from = base.len if file.startsWith(base) else 0
	while from < file.len and file[from] == '/':
		from += 1
	file[from..].copy()

# The repository at root against the limits: whether no file or function is over.
pub fn limitsCheck(root str) bool:
	base = root.copy() if root.endsWith("/") else "{root}/"
	over = 0
	for file in fs.walk(base, sources = true):
		name = relativeTo(file, base)
		lines = (fs.readFile(file) ?? "").replace("\r", "").lines()
		if lines.len > maxFileLines and not markedAtTop(lines):
			print(
				"{name}: {lines.len} lines, over {maxFileLines}: split it by what it does, or mark a table with `{longMark} why` at its top"
			)
			over += 1
		for i, line in lines:
			if not line.startsWith("fn ") and not line.startsWith("pub fn "): continue
			body = lastLineOf(lines, i) - i
			if body > maxBodyLines and not markedAbove(lines, i):
				print(
					"{name}:{i + 1}: a function body of {body} lines, over {maxBodyLines}: split it by what it does, or mark a dispatch with `{longMark} why` above it"
				)
				over += 1
	if over > 0:
		print("{over} files or functions over the limits")
		return false
	print("limits: no file or function over the limits")
	true
