import fs
# sums a column of a TSV and prints a table sorted by name
rows = (fs.readFile(args[0]) ?? fail("{error}")).lines().map(.split("\t"))
sums {str: f64} = {}
for r in rows[1..]:
	if r.len < 2: continue
	sums[r[0].copy()] = (sums.get(r[0]) ?? 0.0) + (f64.parse(r[1]) ?? 0.0)
for k in sums.keys().sorted():
	print("{k:<20} {sums[k]:>10.2}")
