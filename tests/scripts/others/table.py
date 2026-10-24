import sys
rows = [l.split("	") for l in open(sys.argv[1]).read().splitlines()]
sums = {}
for r in rows[1:]:
    if len(r) < 2: continue
    sums[r[0]] = sums.get(r[0], 0.0) + float(r[1])
for k in sorted(sums):
    print(f"{k:<20} {sums[k]:10.2f}")
