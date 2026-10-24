import fs
import regex

fs.deleteTree(args[1]) ?? fail
for f in fs.walk(args[0]):
	fs.createDir(fs.dirOf("{args[1]}{f[args[0].len..]}")) ?? fail
	fs.writeBytes("{args[1]}{f[args[0].len..]}", fs.readBytes(f) ?? fail) ?? fail
re = regex.compile(r"fs\.(readFile|readBytes)\(") ?? fail
files = 0
replacements = 0
for f in fs.walk(args[1], "*.zap"):
	text = fs.readFile(f) ?? fail
	n = re.count(text)
	if n > 0:
		fs.writeFile(f, re.replace(text, "fs.load(")) ?? fail
		files += 1
		replacements += n
print("{replacements} replacements in {files} files")
