# 2.3 Literals
#
# An integer is written in decimal, hexadecimal (`0x`) or binary (`0b`), with `_` between digits as
# wanted (zap fmt groups five digits or more: by three in decimal, by four otherwise). It is an
# `i64` unless its place asks for another width, and it must fit that width.

type Vec3:
	x f32
	y f32
	z f32

fn half(x f64):
	x / 2.0

fn quarterTurn(a f32):
	a + pi / 2.0

test "integers in three bases, with their place's width":
	print("{42} {1_000_000} {0x1F} {0b1010_0001}")
	small u8 = 0xFF
	wide i32 = -2_000
	print("{small} {wide}")
	prints """
		42 1000000 31 161
		255 -2000
		"""

# A float (`3.14`, `1e21`) is `f32` or `f64` as its place asks, `f64` when nothing decides. An
# integer literal where a float is asked is that float, when the float holds it exactly.
test "floats take their place's type, and an integer literal may be one":
	a = 3.14
	b f32 = 1e21
	print("{a} {b} {half(3)}")
	v = Vec3(1, 0, 0)
	print(v.x + v.y)
	prints """
		3.14 1e+21 1.5
		1
		"""

# A byte, `'a'`, is the number of one ASCII character (escapes `\n \t \r \0 \\ \' \"`, `\xHH`): a
# `u8` alone, any integer type where its place asks.
fn byteKind(b u8):
	match b:
		'a': "a"
		'\n': "newline"
		_: "other"

test "a byte literal is the u8 of its character or its escape":
	print('\n')
	print('A' + 1)
	out = []
	out.push('h')
	out.push('i')
	out.push('\x21')
	out.push('\n')
	print(out)
	expect byteKind == {'a': "a", '\n': "newline", '\'': "other"}
	wide i64 = 'z'
	expect wide == 122
	prints """
		10
		66
		[104, 105, 33, 10]
		"""

test "a byte is ASCII" refuses ByteNotAscii:
	print('é')

# A `str` is UTF-8: `{expr}` interpolates any value and `\{` is a literal brace. `r"..."` and
# `r"""..."""` are raw: no escape and no interpolation, `{` and `\` themselves (generated code,
# JSON); zap fmt writes a string whose only escapes are `\{`, `\}` and `\\` this way.
test "interpolation, and raw strings that keep braces and backslashes":
	name = "Ana"
	print("Hi {name}, {1 + 2} \{x}")
	print(r"{x} and \n stay")
	print(r"""
		{a: 1}
		C:\dir\file
		""")
	prints r"""
		Hi Ana, 3 {x}
		{x} and \n stay
		{a: 1}
		C:\dir\file
		"""

# A multi-line string opens with `"""` at the end of a line and closes with `"""` on a line of its
# own; the closing quotes' indentation comes off every line (deeper indentation stays), and the
# newlines after the opening and before the closing quotes are not part of it. Escapes and `{...}`
# work as in one line, and a single `"` needs no escape.
test "a multi-line string drops the closing quotes' indentation and the newlines at its ends":
	name = "Zap"
	banner = """
		Hello, {name}!
		  indented two more
		a "quote" and a tab:\t.
		"""
	print(banner)
	print(banner.len)
	empty = """
		"""
	print(empty.len)
	json = """
		\{"n": {1 + 2}}
		"""
	print(json)
	prints r"""
		Hello, Zap!
		  indented two more
		a "quote" and a tab:	.
		54
		0
		{"n": 3}
		"""

test "a multi-line string starts on the next line" refuses MultilineStringStart:
	s = """hello
		world
		"""
	print(s)

# `[1, 2, 3]` is a list, `{"a": 1}` a map, `(1, "x")` a tuple; `true`, `false` and `none` the
# booleans and the absent optional. An empty `{}` needs a type from its place, and so does `[]`,
# except as the whole value of a local (`mut xs = []`): its element type is then the first use's (a
# push, an extend, a place of a list type: an argument, a return, a field, an assignment).
type Node:
	id i64

fn total(xs i64[]):
	xs.sum()

fn names():
	out = []
	out.push("a")
	out.push("b")
	out

test "lists, maps, tuples and the words":
	m = {"a": 1}
	t = 1, "x"
	maybe i64? = none
	print("{[1, 2, 3]} {m} {t} {true} {false} {maybe}")
	prints r"""
		[1, 2, 3] {"a": 1} (1, "x") true false none
		"""

test "a local made from [] takes its element type from its first use":
	pool = []
	pool.push(Node(id = 1))
	print(pool[0].id)
	nums = []
	print(total(nums))
	nums.push(5)
	print(total(nums))
	words = []
	words = ["x", "y"]
	print(words.len)
	more = []
	more.extend(nums)
	print(more.len)
	print(names())
	floats = []
	floats.push(1.5)
	print(floats[0] * 2)
	bytes = []
	bytes.push('a')
	print(bytes[0])
	prints """
		1
		0
		5
		2
		1
		["a", "b"]
		3
		97
		"""

# A local whose type no use decides (`xs = []`, `m = {}`, `x = none`) is an error that names the local
# and the line to write: `xs T[] = []`.

test "a [] alone tells nothing" refuses UntypedEmptyList("no use decides the type of 'xs': write it, `xs T[] = []`"):
	mut xs = []
	print(xs.len)

test "an element is read only once the type is told" refuses UntoldList("'xs' is read before its element type is told: write it, `xs T[] = []`"):
	mut xs = []
	for x in xs:
		print(x)
	xs.push(1)

test "an index reads the type told too" refuses UntoldList("'ys' is read before its element type is told: write it, `ys T[] = []`"):
	mut ys = []
	print(ys[0])
	ys.push(1)

test "a method reads the type told too" refuses UntoldList("'zs' is read before its element type is told: write it, `zs T[] = []`"):
	mut zs = []
	print(zs.first)
	zs.push(1)

test "an empty list elsewhere needs its type" refuses UntypedEmptyListLiteral:
	print([].len)

test "an empty map needs its type" refuses UntypedEmptyMap(r"no use decides the type of 'm': write it, `m {K: V} = {}`"):
	m = {}
	print(m.len)

test "an empty map elsewhere needs its type" refuses UntypedEmptyMapLiteral:
	print({}.len)

# `pi` and `tau` are the circle's constants, floats of the type their place asks for (rounded to
# it); declared nowhere, so a binding named `pi` or `tau` is an error (zap fmt writes a literal
# `3.141592...` or `6.283185...` as them).
test "pi and tau take the type of their place":
	print("{pi} {tau}")
	half f32 = tau
	print("{quarterTurn(0.0):.4} {half:.4}")
	print("{(pi / 2.0).sin():.0} {tau.cos():.0}")
	prints """
		3.141592653589793 6.283185307179586
		1.5708 6.2832
		1 1
		"""

test "a local may not be named pi" refuses LanguageConstant:
	pi = 3.0
	print(pi)

# Joining: `+` joins strings that are all names or calls, and `+=` appends to a text being built;
# where a literal takes part, the text is an interpolation (`"({a}, {b})"`), and the join is an
# error that shows it (zap fmt writes it). The runtime's and the derived code keep their joins.
test "a join of names and an append keep +":
	a = "x"
	b = "y"
	out = a + b
	out += "<td>"
	expect out == "xy<td>"

test "a text with a literal in it is an interpolation" refuses InterpolationNotConcat:
	a = "x"
	b = "y"
	print("(" + a + ", " + b + ")")

# Formats: a colon right after an interpolated value gives its format, the one way to round, pad or
# show a number in hexadecimal. `{x:.2}` a float with that many decimals (rounded half to even);
# `{n:04}` a number widened with zeros after its sign; `{n:x}`, `{n:X}` an integer in hexadecimal
# (a negative one after a minus); `{s:>8}`, `{s:<8}` the text padded before or after it, a fill
# before the arrow (`{s:->8}`), the width a name after it (`{s:<width}`). They combine as `{x:>8.2}`
# or `{n:08x}`. A `#` first writes an integer as zap fmt writes its literal, for code a program
# writes: `{n:#06X}` is `0x00_1F2E`, `{n:#}` `1_000_000` (five digits or more grouped by `_`, four
# a group in hexadecimal, three in decimal). A ternary-like `if` in braces has no format: its
# colons stand between spaces.
test "formats of numbers and texts":
	x = 3.14159
	n = 3
	print("{x:.2}|{x:.3}|{n:04}|{-7:04}|{255:x}|{255:X}|{255:08x}|{-31:x}")
	width = 6
	print("[{"ab":>5}]|[{"ab":<5}]|[{"ab":->5}]|[{x:>5.2}]|[{7:>3}]|[{"ok":<width}]")
	y f32 = 2.5
	print("[{x:.4}]|[{y:>8.2}]|[{y:07.2}]|[{"ébc":<5}]|[{0.125:.2}]")
	big = true
	print("{"yes" if big else "no"}")
	prints """
		3.14|3.142|0003|-007|ff|FF|000000ff|-1f
		[   ab]|[ab   ]|[---ab]|[ 3.14]|[  7]|[ok    ]
		[3.1416]|[    2.50]|[0002.50]|[ébc  ]|[0.12]
		yes
		"""

test "an integer written as its literal":
	print("{0x1F2E:#06X}|{255:#x}|{0xC0_8000:#08X}|{1000000:#}|{1234:#}|{-0x12345:#X}|{7:#04x}")
	prints "0x00_1F2E|0xff|0x00C0_8000|1_000_000|1234|-0x1_2345|0x0007"

test "a literal's format has no decimals" refuses UnknownFormat:
	print("{3.0:#.2}")

test "a width alone names the alignments" refuses WidthAligned:
	print("{3:5}")

test "decimals are a float's" refuses DecimalsNeedFloat:
	print("{3:.2}")

# `embed("world.txt")` is a string literal holding a file's bytes as they are (no escapes, no
# interpolation), read when compiling. The path is looked up beside the source, then in the dirs
# above it.
text = embed("literals.zap")

test "a file's text is a string, kept as it is":
	print(text.lines()[0])
	expect r"{not interpolated}" in text
	prints "# 2.3 Literals"

test "the path is a literal" refuses EmbedPath:
	name = "literals.zap"
	print(embed(name))
