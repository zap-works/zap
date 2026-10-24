import os, re, sys, json
pat = re.compile(r"^(pub )?fn \w+")
counts = {}
for d, _, files in os.walk(sys.argv[1]):
    for f in files:
        if f.endswith(".zap"):
            p = os.path.join(d, f).replace("\\", "/")
            counts[p] = sum(1 for l in open(p, encoding="utf-8") if pat.match(l))
for name in sorted(counts, key=lambda k: (-counts[k], k))[:10]:
    print(f"{counts[name]:5} {name}")
print(json.dumps({"files": len(counts), "functions": sum(counts.values())}))
