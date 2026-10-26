changes {str: i64} = {}
lines {str: i64} = {}
for line in Process.output("git -C {args[0]} log --numstat --format=").out.lines():
	parts = line.split("\t")
	if parts.len != 3 or parts[0] == "-": continue
	changes.add(parts[2], 1)
	lines.add(parts[2], (i64.parse(parts[0]) ?? 0) + (i64.parse(parts[1]) ?? 0))
top = changes.keys().sortedBy((-changes[it], it))
for path in top[..15.min(len)]:
	print("{changes[path]:>4} {lines[path]:>7} {path}")
