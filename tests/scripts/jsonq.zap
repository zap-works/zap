import fs

type Commit:
	subject str
	files i64
	added i64
	removed i64

type Group:
	word str
	commits i64
	added i64
	removed i64

commits = (Commit[].fromJson(fs.readFile(args[0]) ?? fail) ?? fail("json")).filter(.files >= 3)
by = commits.groupBy(.subject.split(" ")[0])
groups = by
	.keys()
	.map(w:
		Group(
			word = w.copy(),
			commits = by[w].len,
			added = by[w].sum(.added),
			removed = by[w].sum(.removed)
		)
	)
out = groups.sortedBy((-.commits, .word))
print(out[..8.min(len)].toJson(2))
