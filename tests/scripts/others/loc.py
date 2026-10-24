import subprocess, sys
from collections import defaultdict
from pathlib import Path

COMMENT = {".zap": "#", ".py": "#", ".toml": "#", ".c": "//", ".cpp": "//", ".rs": "//", ".lua": "--"}
stats = defaultdict(lambda: [0, 0, 0, 0])
files = subprocess.run(["git", "-C", sys.argv[1], "ls-files"], capture_output=True, text=True).stdout.splitlines()
for name in files:
    ext = Path(name).suffix
    if ext not in COMMENT:
        continue
    lines = (Path(sys.argv[1]) / name).read_text(encoding="utf-8", errors="replace").splitlines()
    s = stats[ext]
    s[0] += 1
    s[1] += len(lines)
    s[2] += sum(1 for l in lines if not l.strip())
    s[3] += sum(1 for l in lines if l.strip().startswith(COMMENT[ext]))
print(f"{'ext':<8}{'files':>6}{'lines':>9}{'blank':>8}{'comment':>9}")
for ext, s in sorted(stats.items(), key=lambda kv: (-kv[1][1], kv[0])):
    print(f"{ext:<8}{s[0]:>6}{s[1]:>9}{s[2]:>8}{s[3]:>9}")
