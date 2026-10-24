import fs

fn fields(line str):
	out = []
	cur = []
	quoted = false
	i = 0
	while i < line.len:
		if line[i] == '"' and quoted and i + 1 < line.len and line[i + 1] == '"':
			cur.push('"')
			i += 1
		elif line[i] == '"': quoted = not quoted
		elif line[i] == ',' and not quoted: out.push(str(move cur))
		else: cur.push(line[i])
		i += 1
	out.push(str(move cur))
	out

fn total(rows str[,], col i64):
	rows.sum(i64.parse(it[col]) ?? 0)

rows = (fs.readFile(args[0]) ?? fail).lines().map(fields(it))
area = rows[0].indexOf("area") ?? fail("no area column")
added = rows[0].indexOf("added") ?? fail("no added column")
removed = rows[0].indexOf("removed") ?? fail("no removed column")
by = rows[1..].groupBy(it[area])
print("{"area":<12}{"commits":>8}{"added":>8}{"removed":>9}")
for k in by.keys().sortedBy((-total(by[it], added), it)):
	print("{k:<12}{by[k].len:>8}{total(by[k], added):>8}{total(by[k], removed):>9}")
