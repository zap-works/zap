# k-nucleotide: frequencies of nucleotide sequences in the third FASTA record read from stdin. A
# sequence of k nucleotides is packed two bits per nucleotide into an integer key, as the fastest
# programs do; the two bits of a letter that tell A, C, T and G apart are the same in either case.
# The record itself is kept so too, four nucleotides a byte. Every k is counted in a map, in parts
# of the sequence, all at once on every processor (the longest keys first), and the parts merged.

import problems

# The third record (">THREE"; the ones before it dropped): its nucleotides' codes, four a byte (the
# first in the low bits), and how many there are.
type Sequence:
	codes u8[]
	length i64

	# the letters' codes added, four a byte; round is 3 for the last ones (a group padded), else 0
	# and fewer than four stay in letters
	fn pack(mut letters u8[], round i64):
		n = letters.len
		groups = (n + round) / 4
		letters.extend("AAA".bytes())   # the last group's padding: code 0
		codes.extend(
			(0..groups).map(q:
				x = (letters.u32le(4 * q) >> 1) & 0x0303_0303   # the four codes, a byte each
				y = x | (x >> 6)   # the second's beside the first's, the fourth's beside the third's
				u8((y | (y >> 12)) & 255)
			)
		)
		length += (4 * groups).min(n)
		letters = letters[(4 * groups).min(n)..n].copy()

fn thirdSequence():
	loop 3:
		stdin.until('>')   # the lines before the header: ONE's, TWO's
		stdin.line()   # the header
	seq = Sequence(codes = [], length = 0)
	letters = []
	while stdin.line() is line:
		if line.startsWith(">"): break
		letters.extend(line.trimmedEnd().bytes())
		if letters.len >= 65_536:
			seq.pack(letters, 0)
	seq.pack(letters, 3)
	seq

# the code of nucleotide i
fn codeAt(seq Sequence, i i64) i64:
	((seq.codes[i >> 2] >> (2 * (i & 3))) & 3)

# a part of the sequence one task counts the words of length k in
type Part:
	k i64
	lo i64
	hi i64

# the k-mers ending in positions [lo, hi) of seq, counted
fn counts(seq Sequence, k i64, lo i64, hi i64):
	table {i64: i64} = {}
	mask = (1 << (2 * k)) - 1
	start = lo.max(k - 1)
	key = (start + 1 - k..start).reduce(0, (key, i): (key << 2) | seq.codeAt(i))   # the k - 1 before
	word = i64(seq.codes[start >> 2]) >> (2 * (start & 3)) if start < hi else 0   # the codes left in the byte of position i
	for i in start..hi:
		if i & 3 == 0:
			word = seq.codes[i >> 2]
		key = ((key << 2) | (word & 3)) & mask
		word >>= 2
		table.add(key, 1)
	table

fn encode(pattern str):
	(0..pattern.len).reduce(0, (key, i): (key << 2) | ((pattern[i] >> 1) & 3))

fn decode(key i64, k i64):
	str((0..k).map("ACTG"[(key >> (2 * (k - 1 - it))) & 3]))

seq = thirdSequence()
n = seq.length
ks = [18, 12, 6, 4, 3, 2, 1]
# the long keys in one part each: their tables, a few megabytes, stay in the shared cache
tasks = ks.flatMap(k:
	np = 1 if k > 6 else cpuCount()
	per = (n + np - 1) / np
	(0..np).map(Part(k, it * per, (it * per + per).min(n)))
)
tables = tasks.parallel().map(seq.counts(.k, .lo, .hi))
merged = ks.map(k:
	parts = (0..tasks.len).filter(tasks[it].k == k)
	total = tables[parts[0]].copy()
	for (key, count) in parts[1..].flatMap(tables[it].entries()):
		total.add(key, count)
	total
)
for j in [6, 5]:
	total = f64(n - ks[j] + 1)
	m = merged[j]
	words = m.keys().sortedBy(-m[it], decode(it, ks[j]))
	print(words.map("{decode(it, ks[j])} {(100.0 * m[it] / total):.3}\n").join(""))
patterns = ["GGT", "GGTA", "GGTATT", "GGTATTTTAATT", "GGTATTTTAATTTATAGT"]
for i, pattern in patterns:
	print("{merged[4 - i].get(encode(pattern)) ?? 0}\t{pattern}")

test "the third record's nucleotide frequencies and counts are the reference's, and the C, Rust and Python programs print the same bytes":
	problems.feedFasta()
	main()
	prints problems.expectedOf("kNucleotide")
	expect problems.agree("kNucleotide")
