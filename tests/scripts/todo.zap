import fs
import regex

type Hit:
	dir str
	item str

re = regex.compile("TODO|FIXME") ?? fail
exts = [".zap", ".zapx", ".py", ".rs", ".c", ".cpp", ".h", ".lua", ".toml"]
hits = []
for name in Process.output("git -C {args[0]} ls-files").out
	.lines()
	.filter(fs.extension(it) in exts):
	for n, line in (fs.readFile("{args[0]}/{name}") ?? fail).lines():
		if re.isMatch(line):
			text = line.trimmed()
			hits.push(
				Hit(
					dir = fs.dirOf(name).copy(),
					item = "{fs.fileName(name)}:{n + 1}: {text[..70.min(text.len)]}"
				)
			)
by = hits.groupBy(.dir)
for d in by.keys().sortedBy((-by[it].len, it)):
	print("{d} ({by[d].len})")
	for hit in by[d]:
		print("  {hit.item}")
