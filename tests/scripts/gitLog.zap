# the last 200 commits' subjects by their first word, most common first
out = Process.output("git -C {args[0]} log -200 --format=%s")
words {str: i64} = {}
for line in out.out.lines():
	words.add(line.split(" ")[0].trimmedEnd(":"), 1)
top = words.keys().sortedBy((-words[it], it))
for w in top[..15.min(len)]:
	print("{words[w]:>4} {w}")
