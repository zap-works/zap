# `zap doc <error>`: a compile error explained, by its name (AssignImmutable) or its code
# (assign-immutable): its message, its explanation and an example, the error's own test (a
# `test "..." refuses Name:`, or a case `refuses Name:`, under spec/, tests/ or std/) where it has
# one, else the example kept beside it in errornames.zap. `zap doc errors` lists them.

import fs

# whether word names a compile error (or is `errors`, which lists them): its explanation printed
pub fn explainError(word str) bool:
	if word == "errors":
		for e in compileErrors:
			print("{e.name:<32} error[{kebabCase(e.name)}]")
		return true
	for e in compileErrors:
		if e.name == word or kebabCase(e.name) == word:
			print(e.errorDoc())
			return true
	false

fn errorDoc(e NamedError):
	head = "error[{kebabCase(e.name)}]: {e.text}\n\n{e.explain.wrapLines(100)}"
	if errorTest(e.name) is test: return "{head}\n\n{test}"
	if e.example == "": return head
	"{head}\n\nFor example:\n\n{e.example}"

# the first test of spec/, tests/ or std/ that expects the error, led by where it is
fn errorTest(name str) str?:
	rt = runtimeDir()
	root = dirPrefix(rt[..len - 1])
	header = "{refusesWord} {name}"
	for dir in ["spec", "tests", "std"]:
		for file in fs.walk("{root}{dir}", sources = true):
			text = fs.readFile(file) ?? ""
			if header not in text: continue
			lines = text.replace("\r\n", "\n").lines()
			for i, line in lines:
				lead = line.trimmedStart()
				if (lead.startsWith("{testWord} ") or lead.startsWith(header)) and
					line.indexOf(header) is at and
					line[at + header.len] in [':', '(']:
					return "{file[root.len..]}:{i + 1}:\n{testBlock(lines, i)}"
	none

# the test whose header is lines[at], up to the next line indented no deeper, unindented
fn testBlock(lines str[], at i64):
	indent = lines[at].len - lines[at].trimmedStart().len
	out = [lines[at][indent..lines[at].len].copy()]
	for line in lines[at + 1..]:
		if line.trimmed() != "" and line.len - line.trimmedStart().len <= indent: break
		out.push(line[indent..].copy() if line.len >= indent else "")
	while out.len > 1 and out[len - 1].trimmed() == "":
		out.pop()
	out.join("\n")
