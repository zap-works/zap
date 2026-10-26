# A str of up to 22 bytes keeps its bytes in its own header (spec 14.2): made, copied, moved,
# compared, sorted, hashed and read through windows like any other, with no block of its own.
#
# a text compared with a literal of up to eight bytes: in place, its length then its bytes.

type Named:
	name str
	tags str[]

fn shout(s str):
	s.upper()

fn firstWord(s str) ref str:   # a window into s itself
	s[..(s.indexOf(" ") ?? len)]

test "short text takes no block":
	before = allocations()
	a = "abc".copy()
	b = "n{41 + 1}"
	c = str(123_456)
	d = shout(a)
	e = "{a}-{b}-{c}"
	print("{a} {b} {c} {d} {e} {allocations() - before}")
	prints "abc n42 123456 ABC abc-n42-123456 0"

test "a long text still gets one":
	before = allocations()
	long = "a text longer than twenty-two bytes".copy()
	expect long.len == 35
	expect allocations() - before == 1

test "short text moves, sorts, hashes and compares by its bytes":
	xs = ["pear", "fig", "apple", "fig"].map(.copy())
	xs.sort()
	counts {str: i64} = {}
	for x in xs:
		counts.add(x, 1)
	moved = []
	for x in xs:
		moved.push(x)
	print("{moved} {counts["fig"]} {moved[0] == "apple"} {moved[1] < moved[2]}")
	prints "[\"apple\", \"fig\", \"fig\", \"pear\"] 2 true false"

test "windows on short text read its bytes where it is":
	s = "  hello world  ".trimmed()
	w = s[..5]
	parts = s.split(" ")
	found = parts.find(.startsWith("wor")) ?? ""
	print("{w} {w.len} {s.bytes().len} {found} {s.indexOf("o") ?? 99} {s[4]}")
	match s:
		"hello {rest}": print(rest)
		_: print("no")
	prints """
		hello 5 11 world 4 111
		world
		"""

test "short text in structs and lists survives their moves":
	people = []
	for i in 0..40:
		people.push(Named(name = "p{i}", tags = ["t{i}", "u"]))
	kept = people.filter(.name.len == 2).map(.name)
	expect kept.len == 10
	expect kept[3] == "p3"
	expect people[39].tags[0] == "t39"
	expect firstWord("zap is short") == "zap"

words = [
	"",
	"a",
	"ab",
	"abc",
	"abcd",
	"abcde",
	"abcdef",
	"abcdefg",
	"abcdefgh",
	"abcdefghi",
	"abd",
	"xbcdefgh",
	"abcdefgx"
]
for w in words:
	print("{w}: {w == "a"} {w == "ab"} {w == "abc"} {w == "abcd"} {w == "abcde"} {w == "abcdefg"} {w == "abcdefgh"} {w != "abc"} {"abcdef" == w}")

test "short literal equality":
	main()
	prints """
		: false false false false false false false true false
		a: true false false false false false false true false
		ab: false true false false false false false true false
		abc: false false true false false false false false false
		abcd: false false false true false false false true false
		abcde: false false false false true false false true false
		abcdef: false false false false false false false true true
		abcdefg: false false false false false true false true false
		abcdefgh: false false false false false false true true false
		abcdefghi: false false false false false false false true false
		abd: false false false false false false false true false
		xbcdefgh: false false false false false false false true false
		abcdefgx: false false false false false false false true false
		"""
