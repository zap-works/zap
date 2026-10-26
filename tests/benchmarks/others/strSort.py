# strSort: n generated strings of 1 to 40 letters, each from an alphabet of 2 to 26 letters, sorted
# by bytes; prints how many are distinct, a hash of the sorted sequence and the first and last
import sys

MASK = (1 << 64) - 1
state = 1


def next_number():
    global state
    state = (state * 6364136223846793005 + 1442695040888963407) & MASK
    return state >> 33


n = int(sys.argv[1]) if len(sys.argv) > 1 else 1000
words = []
for _ in range(n):
    length = 1 + next_number() % 40
    letters_used = 2 + next_number() % 25
    words.append(bytes(97 + next_number() % letters_used for _ in range(length)))
words.sort()
distinct = 0
h = 14695981039346656037
for i, w in enumerate(words):
    if i == 0 or w != words[i - 1]:
        distinct += 1
    for c in w:
        h = ((h ^ c) * 1099511628211) & MASK
    h = ((h ^ 10) * 1099511628211) & MASK
sys.stdout.buffer.write(("%d strings, %d distinct, hash %x\n" % (n, distinct, h)).encode() + words[0] + b"\n" + words[-1] + b"\n")
