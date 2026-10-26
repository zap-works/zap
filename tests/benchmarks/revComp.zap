# reverse-complement: every FASTA record read from stdin is written reversed and complemented in
# lines of 60, one record held at a time. When a record's lines are all 60 wide (the usual
# shape; anything else takes the general path) the position of a sequence character is computed,
# so the output lines are produced straight from its text. Every processor builds a block of
# output lines (.parallel()) into a buffer sized exactly, written in order as it is made.
import problems

fn complementTable():
	"ACGTUMRWSYKVHDBNacgtumrwsykvhdbn".translationTable("TGCAAKYWSRMBDHVNTGCAAKYWSRMBDHVN")

# the vector tables: the complement of the letter whose low five bits are i, for i in 0..32
# (an unknown letter stays itself, in upper case), then the indices that reverse sixteen bytes
fn vectorTables(table u8[]):
	tabs = (0..32).map(table[64 + it])
	tabs.extend((0..16).map(u8(15 - it)))
	tabs

# the output lines [first, last) of a record of m characters whose text is raw (lines of 60). A line's characters run backwards through the text over one newline at
# most, so it is one or two contiguous segments; a segment is reversed and complemented
# sixteen bytes at a time (a shuffle reverses, two shuffles through 16-entry tables indexed by
# the low five bits complement, a blend picks the table by bit four). The chunks of a line
# are produced from its end, so a chunk that starts before its segment writes bytes a later
# chunk overwrites; the lines run from the last to the first for the same reason, and the
# block's first line (nothing before it to absorb the spill) goes byte by byte.
fn linesFromText(raw u8[], table u8[], tabs u8[], m i64, first i64, last i64):
	chars = (m - first * 60).min((last - first) * 60)
	out u8[] = zeros(chars + (last - first))
	tab0 = tabs.load16(0)
	tab1 = tabs.load16(16)
	rev = tabs.load16(32)
	low4 = Simd<16>(15)
	bit4 = Simd<16>(16)
	n = raw.len
	q = last - 1
	while q >= first:
		c0 = m - 1 - 60 * q   # the first character of this output line
		length = (c0 + 1).min(60)
		o = (q - first) * 61
		a = (c0 % 60 + 1).min(length)   # characters before the newline, from c0 down
		cLow = c0 - length + 1
		s2 = cLow + cLow / 60   # the text position of the lowest character
		if q == first or s2 + (length - a) + 14 >= n:
			byteLine(raw, table, out, o, c0, length)
		else:
			if length > a:
				# the lower segment, out[o+a, o+length), from its end
				seg = length - a
				op = length - 16
				while op + 16 > a:
					v = raw.load16(s2 + seg - 16 - (op - a))
					lo = v & low4
					comp = tab0.shuffle(lo).blend(tab1.shuffle(lo), (v & bit4).eqBytes(bit4))
					out.store16(o + op, comp.shuffle(rev))
					op -= 16
			# the upper segment, out[o, o+a)
			cHigh = c0 - a + 1
			s1 = cHigh + cHigh / 60
			op = a - 16
			while op + 16 > 0:
				v = raw.load16(s1 + a - 16 - op)
				lo = v & low4
				comp = tab0.shuffle(lo).blend(tab1.shuffle(lo), (v & bit4).eqBytes(bit4))
				out.store16(o + op, comp.shuffle(rev))
				op -= 16
			out[o + length] = '\n'
		q -= 1
	out

# one output line byte by byte: out[o..o+length) from character c0 down, then its newline
fn byteLine(raw u8[], table u8[], mut out u8[], o i64, c0 i64, length i64):
	p = c0 + c0 / 60
	k = o
	loop length:
		b = raw[p]
		if b == '\n':
			p -= 1
			b = raw[p]
		out[k] = table[b]
		k += 1
		p -= 1
	out[k] = '\n'

# the output lines [first, last) of a record already reversed and complemented (lines of any
# shape were joined into it): 60 characters and a newline each
fn linesFromSeq(seq u8[], first i64, last i64):
	out = []
	for j in first..last:
		out.extend(seq[60 * j..(60 * j + 60).min(len)])
		out.push('\n')
	out

# the lines [0, lineCount) in blocks of `per` lines, f(first, last) building a block, written
# in order as each is made while the processors go on with the next ones; a few blocks ahead at
# most, so the buffers freed come back for the next ones and the working set stays in the cache
fn writeBlocks(lineCount i64, per i64, out Stream, f fn(i64, i64) u8[]):
	blocks = (lineCount + per - 1) / per
	for b in (0..blocks).parallel().map(t: f(t * per, (t * per + per).min(lineCount))):
		out.writeBytes(b)

# whether the record's lineCount lines are all 60 wide but the last, each closed by a newline:
# in parts of 32768 lines on every processor, a part's newlines counted, then looked for at
# every 61st byte with its 2 MB still in the cache
fn linesRegular(text str, raw u8[], lineCount i64):
	per = 32_768
	oks = (0..(lineCount + per - 1) / per)
		.parallel()
		.map(k:
			first = k * per
			last = (first + per).min(lineCount)
			text[61 * first..(61 * last).min(len)].count('\n') == last - first and
				(first..last.min(lineCount - 1)).all(raw[61 * it + 60] == '\n')
		)
	oks.all(it) and (raw.last ?? 0) == '\n'

# the record whose sequence text is text, written straight from the text when its lines are
# all 60 wide (m characters in lineCount lines, one every 61 bytes)
fn flushRecord(text str, raw u8[], table u8[], tabs u8[], out Stream):
	lineCount = (raw.len + 60) / 61
	m = raw.len - lineCount
	if linesRegular(text, raw, lineCount):
		writeBlocks(lineCount, 4096, out, (first, last):
			linesFromText(raw, table, tabs, m, first, last)
		)
		return
	# lines of any width: joined, then reversed and complemented
	seq = []
	for line in text.lines():
		seq.extend(line.trimmedEnd().bytes())
	seq.reverse()
	seq.translate(table)
	writeBlocks((seq.len + 59) / 60, 4096, out, (first, last): linesFromSeq(seq, first, last))

table = complementTable()
tabs = vectorTables(table)
out = stdout
stdin.until('>')   # text before the first header: skipped
while stdin.line() is header:
	out.print(header.trimmed())
	body = stdin.until('>') ?? ""
	flushRecord(body, body.bytes(), table, tabs, out)

test "every record comes out reversed and complemented in lines of 60":
	problems.feedFasta()
	main()
	prints problems.expectedOf("revComp")

test "revComp of lines of any width":
	stdin.feed(">X\nACGTACGTA\nCCGG\nT\n")
	main()
	prints """
		>X
		ACCGGTACGTACGT
		"""

test "the C, Rust and Python programs print the same bytes":
	expect problems.agree("revComp")
