# zap fmt run on a file in the test's dir: what it wrote, its tabs shown as `>`

import fs

pub fn formatted(source str) str:
	formattedAs("messy.zap", source)

# formatted, the file checked first (zap test --only check), so fmt writes the forms only types
# tell (the lint's findings, 13.1.3) too
pub fn linted(source str) str:
	formattedAs("messy.zap", source, lint = true)

# whether zap fmt leaves the file as it is: the file stays as it was
pub fn isLaidOut(file str) bool:
	before = fs.readFile(file) ?? ""
	zapFmt(file)
	laid = (fs.readFile(file) ?? "") == before
	_ = fs.writeFile(file, before)
	laid

pub fn formattedAs(name str, source str, lint bool = false) str:
	file = "{testDir()}{name}"
	_ = fs.writeFile(file, source)
	zapFmt(file, lint)
	text = fs.readFile(file) ?? ""
	_ = fs.deleteFile(file)
	text.trimmed().replace("\t", ">")
