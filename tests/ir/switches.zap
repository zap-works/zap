# A match of four or more integer literals (or a plain enum's variants) is a switch: a jump table
# over a dense run of cases, a binary search over sparse ones, a compare each for a few. Every
# value around each case is tried, so a wrong bound, stride or order shows. A match of four or more
# string literals, and `x in [...]` of them, switches on the length, then on the bytes.

fn dense(x i64):
	match x:
		0: 10
		1: 11
		2: 12
		3: 13
		4: 14
		6: 16
		_: -1

# cases 8 apart from 4096: a table on (x - 4096) / 8, the values between going to the default
fn strided(x u32):
	match x:
		4096: 1
		4104: 2
		4112: 3
		4120: 4
		4136: 5
		_: 0

fn sparse(x i64):
	match x:
		-1_000_000_000_000: 1
		-7: 2
		0: 3
		5: 4
		1000: 5
		77_777_777: 6
		1_000_000_000_000: 7
		_: 0

# unsigned order: the largest u64 values sort last, past every other
fn wide(x u64):
	match x:
		0: 1
		3: 2
		9_223_372_036_854_775_808: 3
		18_446_744_073_709_551_615: 4
		_: 0

fn bytes(c u8):
	match c:
		'a', 'e', 'i', 'o', 'u': "vowel"
		' ': "space"
		'0', '1', '2': "digit"
		other: "other {other}"

type Op:
	Add
	Sub
	Mul
	Div
	Neg

fn apply(op Op, a i64, b i64):
	match op:
		Add: a + b
		Sub: a - b
		Mul: a * b
		Div: a / b
		Neg: -a

type Shade:
	Red
	Orange
	Yellow
	Green
	Cyan
	Blue
	Violet
	Pink

# every variant taken, some arms of several: no default is searched
fn warmth(shade Shade):
	match shade:
		Red, Orange, Pink: 1
		Yellow: 2
		Green, Cyan: 3
		Blue: 4
		Violet: 5

# a statement: each arm changes a variable the match reads no more
fn steps(start i64):
	pc = start
	n = 0
	while pc != 0:
		n += 1
		match pc:
			1: pc = 0
			2: pc = 5
			3: pc = 2
			5: pc = 1
			_: pc = 0
	n

test "a dense switch":
	expect (-2..9).map(dense(it)) == [-1, -1, 10, 11, 12, 13, 14, -1, 16, -1, -1]

test "a table of cases a stride apart":
	found = []
	for x in 4090..4140:
		if strided(x) != 0: found.push("{x}:{strided(x)}")
	expect found.join(" ") == "4096:1 4104:2 4112:3 4120:4 4136:5"

test "a sparse switch":
	cases = [-1_000_000_000_000, -7, 0, 5, 1000, 77_777_777, 1_000_000_000_000]
	out = []
	for c in cases:
		out.push("{sparse(c - 1)}{sparse(c)}{sparse(c + 1)}")
	expect out.join(" ") == "010 020 030 040 050 060 070"

test "unsigned cases in unsigned order":
	expect wide == {
		0: 1,
		3: 2,
		9_223_372_036_854_775_808: 3,
		18_446_744_073_709_551_615: 4,
		9_223_372_036_854_775_807: 0,
		4: 0
	}

test "an arm of several patterns, and a name for the rest":
	expect bytes == {'e': "vowel", 'u': "vowel", ' ': "space", '1': "digit", 'x': "other 120"}

test "a plain enum's variants":
	expect apply ==
		{(.Add, 6, 3): 9, (.Sub, 6, 3): 3, (.Mul, 6, 3): 18, (.Div, 6, 3): 2, (.Neg, 6, 3): -6}

test "a switch in a loop that changes its own value":
	expect steps == {3: 4, 9: 1}

test "a match of every variant of an enum searches no default":
	expect warmth ==
		{.Red: 1, .Orange: 1, .Yellow: 2, .Green: 3, .Cyan: 3, .Blue: 4, .Violet: 5, .Pink: 1}

fn mnemonic(s str):
	match s:
		"lda": 1
		"sta", "stz": 2
		"": 3
		"a": 4
		"jsr": 5
		"lda": 6
		"abcdefg": 7
		"abcdefgh": 8
		"abcdefghi": 9
		"abcdefghj": 10
		"longer than sixteen bytes": 11
		_: 0

test "a switch on texts: their lengths, then their bytes":
	texts = ["lda", "sta", "stz", "", "a", "jsr", "abcdefg", "abcdefgh", "abcdefghi", "abcdefghj"]
	texts.extend(["longer than sixteen bytes", "ld", "ldb", "b", "abcdefgi", "abcdefghk"])
	texts.extend(["longer than sixteen bytez", "lda "])
	expect texts.map(mnemonic(it)) == [1, 2, 2, 3, 4, 5, 7, 8, 9, 10, 11, 0, 0, 0, 0, 0, 0, 0]
	line = "xx stz yy"
	expect mnemonic(line[3..6]) == 2
	expect mnemonic("{"j"}{"sr"}") == 5

fn branches(name str):
	name in ["bcc", "bcs", "beq", "bne", "bmi", "bpl", "bvc", "bvs"]

fn odd(n i64):
	n in [1, 3, 5, 7, 300]

test "x in a list of literals is a switch":
	expect ["bcc", "bvs", "bra", "bc", "bccc", ""].map(branches(it)) ==
		[true, true, false, false, false, false]
	expect [1, 2, 3, 300, -1, 7].map(odd(it)) == [true, false, true, true, false, true]
