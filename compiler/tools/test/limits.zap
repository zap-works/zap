# zap test's limits: no .zap file over 1,000 lines and no function body over 100 lines, across
# every .zap file of a repository; and no .zap file, or dir holding one, named with `_`, `-` or a
# capital first letter (a module's name is camelCase, as a function's). A table file, or a
# function that is one line per arm (a dispatch), is exempt from the lines by a comment line
# `# long: why` at the top of the file (in its leading comment block) or directly above the
# function (in the comment block over its `fn`).

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

# the first part of a path under the repository that is not a camelCase name: one with `_` or `-`,
# or a capital first letter; "" when every part is one
fn misnamedPart(name str):
	for part in name.split("/"):
		if "_" in part or "-" in part or (not part.isEmpty and part[0] >= 'A' and part[0] <= 'Z'):
			return part.copy()
	""

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
		misnamed = misnamedPart(name) if name.endsWith(".zap") else ""
		if misnamed != "":
			print("{name}: `{misnamed}` is not camelCase, as a module's file or dir is: no `_` or `-`, a lowercase first letter")
			over += 1
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
		print("{over} files or functions over the limits or misnamed")
		return false
	print("limits: no file or function over the limits, every name camelCase")
	true
