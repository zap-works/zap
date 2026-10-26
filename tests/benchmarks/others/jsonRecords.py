# jsonRecords: n generated records written as {"records": [...]} and parsed back; prints the
# JSON's size and byte sum, sums over the parsed records and whether they equal the originals.
import json
import sys

MASK = (1 << 64) - 1
TAGS = ["red", "green", "blue", "admin", "guest", "beta"]
state = 7


def next_number():
    global state
    state = (state * 6364136223846793005 + 1442695040888963407) & MASK
    return state >> 33


def generate(n):
    records = []
    for i in range(n):
        word = "".join([chr(97 + next_number() % 26) for _ in range(5 + next_number() % 8)])
        score = next_number() % 100000 - 50000
        active = next_number() % 3 != 0
        tags = [TAGS[next_number() % 6] for _ in range(next_number() % 4)]
        name = word + ' "jr"' if i % 10 == 0 else word
        records.append({"id": i, "name": name, "email": "%s%d@mail.test" % (word, i), "score": score, "active": active, "tags": tags})
    return records


n = int(sys.argv[1]) if len(sys.argv) > 1 else 100
records = generate(n)
text = json.dumps({"records": records}, separators=(",", ":")).encode()
sys.stdout.buffer.write(b"json %d bytes, checksum %d\n" % (len(text), sum(text)))
back = json.loads(text)["records"]
scores = sum(r["score"] for r in back)
active = sum(r["active"] for r in back)
tags = sum(len(r["tags"]) for r in back)
sys.stdout.buffer.write(b"read %d records: scores %d, active %d, tags %d, %s\n" % (len(back), scores, active, tags, b"same" if back == records else b"DIFFERENT"))
