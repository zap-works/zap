# wordFreq: n generated words counted in a hash map keyed by the words; prints the distinct
# count and the ten most frequent.
import sys
from collections import Counter

MASK = (1 << 64) - 1
n = int(sys.argv[1]) if len(sys.argv) > 1 else 1000
letters = [bytes((97 + i,)) for i in range(26)]
words = []
state = 1
for _ in range(n):
    state = (state * 6364136223846793005 + 1442695040888963407) & MASK
    k = (state >> 44) % ((state >> 24 & 1048575) + 1)
    w = letters[k % 26]
    k //= 26
    while k > 0:
        w += letters[k % 26]
        k //= 26
    words.append(w)
counts = Counter(words)
top = sorted(counts.items(), key=lambda e: (-e[1], e[0]))[:10]
out = [b"%d words, %d distinct\n" % (n, len(counts))]
out += [b"%8d %s\n" % (c, w) for w, c in top]
sys.stdout.buffer.write(b"".join(out))
