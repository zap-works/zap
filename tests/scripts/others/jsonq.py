import json, sys

commits = json.load(open(sys.argv[1], encoding="utf-8"))
groups = {}
for c in commits:
    if c["files"] < 3:
        continue
    word = c["subject"].split(" ")[0]
    g = groups.setdefault(word, {"word": word, "commits": 0, "added": 0, "removed": 0})
    g["commits"] += 1
    g["added"] += c["added"]
    g["removed"] += c["removed"]
out = sorted(groups.values(), key=lambda g: (-g["commits"], g["word"]))
print(json.dumps(out[:8], indent=2))
