import re, subprocess, sys
from collections import defaultdict
from pathlib import Path

pat = re.compile(r"TODO|FIXME")
exts = {".zap", ".zapx", ".py", ".rs", ".c", ".cpp", ".h", ".lua", ".toml"}
groups = defaultdict(list)
names = subprocess.run(["git", "-C", sys.argv[1], "ls-files"], capture_output=True, text=True).stdout.splitlines()
for name in names:
    p = Path(name)
    if p.suffix not in exts:
        continue
    for n, line in enumerate((Path(sys.argv[1]) / p).read_text(encoding="utf-8", errors="replace").splitlines(), 1):
        if pat.search(line):
            groups[p.parent.as_posix()].append(f"{p.name}:{n}: {line.strip()[:70]}")
for d in sorted(groups, key=lambda d: (-len(groups[d]), d)):
    print(f"{d} ({len(groups[d])})")
    for item in groups[d]:
        print(f"  {item}")
