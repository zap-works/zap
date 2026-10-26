import fs

type Commit:
	area str
	added i64
	removed i64

rows = Commit[].fromCsv(fs.readFile(args[0]) ?? fail) ?? fail
by = rows.groupBy(.area)
print("{"area":<12}{"commits":>8}{"added":>8}{"removed":>9}")
for k in by.keys().sortedBy((-by[it].sum(.added), it)):
	print("{k:<12}{by[k].len:>8}{by[k].sum(.added):>8}{by[k].sum(.removed):>9}")
