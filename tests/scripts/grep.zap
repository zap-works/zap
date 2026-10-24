import fs
import regex

re = regex.compile(args[1]) ?? fail
for p in fs.walk(args[0], "*.zap"):
	for n, line in (fs.readFile(p) ?? fail).lines():
		if re.isMatch(line): print("{p}:{n + 1}:{line}")
