# 7.5 Strings: `str`
#
# A `str` is immutable UTF-8 bytes. Positions count bytes: `s.len` is the byte count and
# `s[i]` the byte at `i` (a `u8`, bounds-checked); code points appear only where asked for.

test "positions count bytes, code points only where asked for":
	s = "héllo wörld ✓"
	print("{s.len} {s.chars().len} {s[0]}")
	print("{s[..3]}|{s[7..13]}|{s[5..5]}|{s.indexOf("wörld")}")
	print("{"é".charCode()} {s.chars()[12]}")
	b = s[1]
	print(b)
	prints """
		17 13 104
		hé|wörld||some(7)
		233 ✓
		195
		"""

test "an index past the end stops the program" stops IndexOutOfBounds:
	print("abc"[args.len + 3])

test "a str is not changed in place" refuses StrNotInPlace:
	mut s = "abc"
	s[0] = 65
	print(s)

# Strings order by bytes with `< <= > >=`; `a + b` joins two values (a literal in it makes it an
# interpolation, see 2.3).

test "strings order by bytes and join with +":
	a = "apple"
	b = "banana"
	expect a < b
	expect "Z" < "a"
	expect a >= a
	expect "é" > "z"
	expect a + b == "applebanana"

# `str(x)` is the text of any value, the same as `"{x}"`, for where an interpolation does not read
# better; `x.toStr()` is an error.

test "str of a value is its text":
	print("{str(42) == "42"} {str(true)} {str([1, 2])} {str(2.5) == "{2.5}"}")
	prints "true true [1, 2] true"

# A `u8[]` is the one value `str` takes otherwise: a str of its bytes. `str(move bytes)` (or
# `str(list made here)`) takes them without a copy, leaving the list empty: the way to build a
# string byte by byte. A list's place, or a lent list (`b[1..]`, `s.bytes()`), is copied.

test "str(move bytes) takes a list's bytes, str(bytes) copies them":
	buf = []
	for b in [104, 105, 33]:
		buf.push(u8(b))
	s = str(move buf)
	print("{s} {buf.len} {str("ab".bytes())}")
	bytes u8[] = [122, 97, 112]
	print("{str(bytes)} {str(bytes[1..])} {bytes.len}")
	prints """
		hi! 0 ab
		zap ap 3
		"""

# `bytes.text()` reads the bytes as a text without copying them: a window `ref str` that lives as
# long as they do.

test "bytes.text() is a window over the bytes":
	bytes u8[] = [104, 105, 33, 122, 97, 112]
	word = bytes[3..].text()
	print("{bytes[..3].text()} {word} {word.len} {word == "zap"}")
	prints "hi! zap 3 true"

# `bytes.extend("{x}".bytes())` appends the text's bytes with no str made between.

test "an interpolation's bytes appended to a list":
	out = []
	for i in 0..3:
		out.extend("{i * 7},{i == 1}{u64(i) + 18_446_744_073_709_551_613} ".bytes())
	out.extend("{out.len}".bytes())
	expect str(move out) ==
		"0,false18446744073709551613 7,true18446744073709551614 14,false18446744073709551615 84"

# The functions of the type make one: `str.fromCode(cp)` a one-character string (`str(65)` is
# `"65"`); `str(bytes)` a string of a list of bytes.

test "the type's functions make a str":
	codes u8[] = [104, 105]
	print("{str.fromCode(233)} {str(codes)} {str(65)}")
	prints "é hi 65"

# `s[a..b]` is a window `ref str` over bytes `[a, b)` (4.3); `trimmed`, `trimmedStart` and
# `trimmedEnd` are windows without ASCII spaces.

test "a slice and the trims are windows over the string":
	s = "  Hello, Zap  "
	print("{s.trimmed()}|{s.trimmedStart()}|{s.trimmedEnd()}|{s[2..7]}")
	prints "Hello, Zap|Hello, Zap  |  Hello, Zap|Hello"

# `trimmed(chars)`, `trimmedStart(chars)` and `trimmedEnd(chars)` trim the bytes of `chars` instead
# of the spaces (Python's `strip(chars)`, `lstrip(chars)` and `rstrip(chars)`).

test "the trims of a set of bytes":
	print("//a/b//".trimmedStart("/"))
	print("::ab:: ".trimmedEnd(": "))
	print("/a/b/".trimmed("/"))
	prints """
		a/b//
		::ab
		a/b
		"""

# `split(sep)` is a list of parts and `lines()` of the lines, a carriage return before a newline
# dropped and nothing after a final one (in a `for`, both windows with no copy); `words()` the runs
# between spaces, tabs and line breaks, none empty.

test "split, words and lines":
	print("a,b,,c,".split(","))
	print("{"abc".split("").len} {"".split(",").len}")
	for part in "x;y".split(";"):
		print(part)
	print("  one two\tthree\r\nfour  ".words())
	print("".words().len)
	for line in "ab\r\ncd\n".lines():
		print("{line}|")
	print("{"ab\r\n\ncd".lines()} {"".lines().len}")
	prints """
		["a", "b", "", "c", ""]
		3 1
		x
		y
		["one", "two", "three", "four"]
		0
		ab|
		cd|
		["ab", "", "cd"] 0
		"""

# Searching: `indexOf(part, from = 0)` gives the byte index of a `str` or of a byte (a `u8`, as
# `count(b)` takes: how many bytes equal `b`) and `lastIndexOf(part)` of a `str`, each a `n64?`;
# `startsWith` and `endsWith` a `bool`; membership is `x in s`.

test "indexOf, lastIndexOf, count, startsWith, endsWith and in search a string":
	t = "Hello, Zap World, Zap"
	expect t.indexOf == {"Zap": 7, ("Zap", 8): 18, "zzz": none}
	expect t.lastIndexOf("Zap") == 18
	expect t.indexOf == {111: 4, (111, 5): 12}
	expect t.count(108) == 3
	expect t[..5].count(108) == 2
	expect t.startsWith("Hello")
	expect t.endsWith("Zap")
	expect "Zap" in t
	expect "" in t

# New strings: `upper()` and `lower()` map ASCII case, `replace(a, b)` (`replace("", x)` returns
# the string unchanged) and `repeat(n)`.

test "upper, lower, replace and repeat make new strings":
	print("{"héllo wörld".upper()} {"ÀBC".lower()}")
	expect "aaa".replace("a", "aa") == "aaaaaa"
	expect "aaa".replace("", "x") == "aaa"
	expect "ab".repeat(3) == "ababab"
	prints """
		HéLLO WöRLD Àbc
		"""

# `T.parse(s)` reads a number from text (3.1).

# `loadWord(i)` is the `u64` of bytes `[i, i + 8)` (also on `u8[]`), bounds-checked; `isEmpty`,
# `len` and `hash()` complete the type.

test "loadWord, isEmpty and hash":
	text = "abcdefghij"
	print("{text.loadWord(0)} {text.loadWord(2) & 255}")
	bytes = []
	for i in 0..9:
		bytes.push(u8(i + 1))
	print(bytes.loadWord(1))
	print("{"".isEmpty} {"a".isEmpty} {"ab".hash() == "ab".hash()} {"ab".hash() != "ba".hash()}")
	prints """
		7523094288207667809 99
		650777868590383874
		true false true true
		"""

test "a word past the end stops the program" stops IndexOutOfBounds:
	print("abcdefgh".loadWord(args.len + 1))
