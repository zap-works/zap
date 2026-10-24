import re, sys
from pathlib import Path
pat = re.compile(sys.argv[2])
for p in sorted(Path(sys.argv[1]).rglob("*.zap")):
    for n, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1):
        if pat.search(line):
            print(f"{p.as_posix()}:{n}:{line}")
