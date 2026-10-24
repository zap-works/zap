import re, shutil, sys
from pathlib import Path

src, dst = Path(sys.argv[1]), Path(sys.argv[2])
shutil.rmtree(dst, ignore_errors=True)
shutil.copytree(src, dst)
pat = re.compile(r"fs\.(readFile|readBytes)\(")
files = replacements = 0
for p in sorted(dst.rglob("*.zap")):
    text = p.read_text(encoding="utf-8")
    new, n = pat.subn("fs.load(", text)
    if n:
        p.write_text(new, encoding="utf-8", newline="")
        files += 1
        replacements += n
print(f"{replacements} replacements in {files} files")
