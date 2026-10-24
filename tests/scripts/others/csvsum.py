import csv, sys
from collections import defaultdict

totals = defaultdict(lambda: [0, 0, 0])
with open(sys.argv[1], newline="", encoding="utf-8") as f:
    for row in csv.DictReader(f):
        t = totals[row["area"]]
        t[0] += 1
        t[1] += int(row["added"])
        t[2] += int(row["removed"])
print(f"{'area':<12}{'commits':>8}{'added':>8}{'removed':>9}")
for area, (n, added, removed) in sorted(totals.items(), key=lambda kv: (-kv[1][1], kv[0])):
    print(f"{area:<12}{n:>8}{added:>8}{removed:>9}")
