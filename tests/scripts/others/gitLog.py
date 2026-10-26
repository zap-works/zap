import subprocess, sys
out = subprocess.run(["git", "-C", sys.argv[1], "log", "-200", "--format=%s"], capture_output=True, text=True).stdout
words = {}
for line in out.splitlines():
    w = line.split(" ")[0].rstrip(":")
    words[w] = words.get(w, 0) + 1
for w in sorted(words, key=lambda k: (-words[k], k))[:15]:
    print(f"{words[w]:4} {w}")
