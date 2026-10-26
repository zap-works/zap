# regex-redux for the Zap benchmarks game, in the manner of the Benchmarks Game's Python programs:
# the headers and newlines taken out with a regular expression, nine variants counted, four
# substitutions in turn. Standard library only (re), bytes patterns over the raw stdin.
import re
import sys

variants = [
    b"agggtaaa|tttaccct",
    b"[cgt]gggtaaa|tttaccc[acg]",
    b"a[act]ggtaaa|tttacc[agt]t",
    b"ag[act]gtaaa|tttac[agt]ct",
    b"agg[act]taaa|ttta[agt]cct",
    b"aggg[acg]aaa|ttt[cgt]ccct",
    b"agggt[cgt]aa|tt[acg]accct",
    b"agggta[cgt]a|t[acg]taccct",
    b"agggtaa[cgt]|[acg]ttaccct",
]

substitutions = [
    (b"tHa[Nt]", b"<4>"),
    (b"aND|caN|Ha[DS]|WaS", b"<3>"),
    (b"a[NSt]|BY", b"<2>"),
    (b"<[^>]*>", b"|"),
    (b"\\|[^|][^|]*\\|", b"-"),
]


def stripped(text):
    # in parts that end at a newline, so that re.sub's list of pieces stays small
    strip = re.compile(b">.*\n|\n")
    parts = []
    start = 0
    while start < len(text):
        end = text.find(b"\n", min(start + (16 << 20), len(text) - 1))
        end = len(text) if end < 0 else end + 1
        parts.append(strip.sub(b"", text[start:end]))
        start = end
    return b"".join(parts)


def replaced(pattern, by, text):
    # not re.sub: its list of pieces for millions of matches is gigabytes
    out = bytearray()
    last = 0
    for m in re.finditer(pattern, text):
        out += text[last:m.start()]
        out += by
        last = m.end()
    out += text[last:]
    return bytes(out)


def main():
    original = sys.stdin.buffer.read()
    sequence = stripped(original)
    out = []
    for pattern in variants:
        count = len(re.findall(pattern, sequence))
        out.append("%s %d\n" % (pattern.decode(), count))
    text = sequence
    for pattern, by in substitutions:
        text = replaced(pattern, by, text)
    out.append("\n%d\n%d\n%d\n" % (len(original), len(sequence), len(text)))
    sys.stdout.buffer.write("".join(out).encode())


main()
