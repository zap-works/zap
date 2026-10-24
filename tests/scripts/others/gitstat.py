import subprocess, sys
from collections import Counter

out = subprocess.run(["git", "-C", sys.argv[1], "log", "--numstat", "--format="], capture_output=True, text=True).stdout
changes, lines = Counter(), Counter()
for line in out.splitlines():
    parts = line.split("\t")
    if len(parts) != 3 or parts[0] == "-":
        continue
    changes[parts[2]] += 1
    lines[parts[2]] += int(parts[0]) + int(parts[1])
for path in sorted(changes, key=lambda p: (-changes[p], p))[:15]:
    print(f"{changes[path]:4} {lines[path]:7} {path}")
