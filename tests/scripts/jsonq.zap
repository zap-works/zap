import fs
import json

type Group:
	word str
	commits i64
	added i64
	removed i64

doc = json.parse(fs.readFile(args[0]) ?? fail) ?? fail
commits = (0..doc.count(doc.root))
	.map(doc.at(doc.root, it))
	.filter((doc.number(it, "files") ?? 0) >= 3)
by = commits.groupBy(doc.textOf(it, "subject").split(" ")[0])
groups = by
	.keys()
	.map(w:
		Group(
			word = w.copy(),
			commits = by[w].len,
			added = by[w].sum(i64(doc.number(it, "added") ?? 0)),
			removed = by[w].sum(i64(doc.number(it, "removed") ?? 0))
		)
	)
out = groups.sortedBy((-.commits, .word))
print((json.parse(out[..8.min(len)].toJson()) ?? fail).text(indent = 2))
