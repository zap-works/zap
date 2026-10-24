import fs

marks = {".zap": "#", ".py": "#", ".toml": "#", ".c": "//", ".cpp": "//", ".rs": "//", ".lua": "--"}
stats {str: i64[]} = {}
for name in Process.output("git -C {args[0]} ls-files").out.lines():
	ext = fs.extension(name)
	mark = marks.get(ext) ?? continue
	lines = (fs.readFile("{args[0]}/{name}") ?? fail).lines()
	s = stats.get(ext) ?? [0, 0, 0, 0]
	stats[ext.copy()] = [
		s[0] + 1,
		s[1] + lines.len,
		s[2] + lines.count(.trimmed().isEmpty),
		s[3] + lines.count(.trimmed().startsWith(mark))
	]
print("{"ext":<8}{"files":>6}{"lines":>9}{"blank":>8}{"comment":>9}")
for ext in stats.keys().sortedBy((-stats[it][1], it)):
	s = stats[ext]
	print("{ext:<8}{s[0]:>6}{s[1]:>9}{s[2]:>8}{s[3]:>9}")
