# The standard library's regular expressions: a pattern compiled to automata, matches found by
# scanning the text once.
#
# Patterns checked against Python's re over short texts: each row is a pattern, a text, the spans
# of its matches in order, and the text with every match replaced by <>.

import regex

fn found(pattern str, text str):
	re = regex.compile(pattern) ?? fail
	match re.find(text):
		m: "{m.start}-{m.end}"
		none: "none"

test "literals and the leftmost match":
	expect found("abc", "xxabcxabc") == "2-5"
	expect found("abc", "ab") == "none"
	expect found("", "abc") == "0-0"

test "classes, escapes and any byte":
	expect found("[a-c]+", "xxbcaz") == "2-5"
	expect found("[^a-c]+", "abxyc") == "2-4"
	expect found("\\d+", "ab1234c") == "2-6"
	expect found("\\w+\\s", "  hi_9 x") == "2-7"
	expect found("a.c", "a\nc abc") == "4-7"
	expect found("[]a]+", "x]a]") == "1-4"
	expect found("[\\d-]+", "a1-2b") == "1-4"
	expect found("\\x41\\.", "zA.") == "1-3"

test "alternation takes the first branch that matches, as a backtracking engine does":
	expect found("a|ab", "ab") == "0-1"
	expect found("ab|a", "ab") == "0-2"
	expect found("(a|ab)(c|bcd)", "abcd") == "0-4"
	expect found("x*", "aaa") == "0-0"
	expect found("b|abcd", "abcd") == "0-4"
	expect found("abcd|b", "abcx") == "1-2"

test "greedy and lazy repetition":
	expect found("a+", "baaac") == "1-4"
	expect found("a+?", "baaac") == "1-2"
	expect found("<.*>", "<a><b>") == "0-6"
	expect found("<.*?>", "<a><b>") == "0-3"
	expect found(r"a{2}", "aaaa") == "0-2"
	expect found(r"a{2,3}", "aaaa") == "0-3"
	expect found(r"a{2,}", "baaaa") == "1-5"
	expect found(r"(ab){2}", "ababab") == "0-4"
	expect found("a?b", "aab") == "1-3"

test "^ and $ match only at the text's ends":
	expect found("^a", "ba") == "none"
	expect found("^a", "ab") == "0-1"
	expect found("a$", "aba") == "2-3"
	expect found("a$", "ab") == "none"
	expect found("^$", "") == "0-0"
	expect found("^$", "a") == "none"
	re = regex.compile("^a") ?? fail
	expect re.find("aa", 1) == none

test "UTF-8 text is matched byte by byte, a character as a unit":
	expect found("é+", "caféé!") == "3-7"
	expect found("caf.", "café") == "0-4"   # `.` is one byte

test "find from a position, all matches, the count, the replacement":
	re = regex.compile("a+") ?? fail
	expect re.isMatch("bab")
	expect not re.isMatch("bbb")
	first = re.find("aabaaa", 2) ?? fail("none")
	expect first.start == 3 and first.end == 6
	expect re.findAll("aabaaa").len == 2
	expect re.count("a-aa-aaa") == 3
	expect re.replace("a-aa-aaa", "X") == "X-X-X"
	expect re.replace("none", "X") == "none"
	empty = regex.compile("x*") ?? fail
	expect empty.replace("abc", "-") == "-a-b-c-"
	expect empty.count("") == 1

test "a pattern that is not one gives why" for bad in [
	"(a",
	"a)",
	"[a",
	"*a",
	r"a{3,1}",
	"\\",
	"[z-a]",
	"(?=a)",
	"\\q"
]:
	match regex.compile(bad):
		error: expect error.startsWith("regex: ")
		_: expect false

test "a pattern whose automaton is larger than the cache is still matched":
	# a, then twelve of a or b: 2^13 states, more than the cache keeps
	re = regex.compile(r"a[ab]{12}") ?? fail
	seed u32 = 7
	text = ""
	loop 3000:
		seed = (seed * 1_103_515_245 + 12_345) % 2_147_483_648
		text += "a" if (seed >> 16) % 2 == 0 else "b"
	expected = 0
	at = 0
	while at + 13 <= text.len:
		if text[at] == 'a':
			expected += 1
			at += 13
		else:
			at += 1
	expect re.count(text) == expected
	expect expected > 10

test "a long text is scanned and replaced":
	re = regex.compile("ab|cd") ?? fail
	text = "xabxcdx".repeat(10_000)
	expect re.count(text) == 20_000
	expect re.replace(text, "").len == 3 * 10_000

test "a match is found at every offset of a long text, in the vector scan and in the tail":
	words = regex.compile("needle|nxx") ?? fail
	digit = regex.compile("q[0-9]") ?? fail
	lone = regex.compile("z") ?? fail
	for offset in 0..100:
		for tail in [0, 1, 7, 40]:
			text = "{"x".repeat(offset)}needle{"y".repeat(tail)}"
			m = words.find(text) ?? fail("no match at {offset}")
			expect m.start == offset and m.end == offset + 6
			text2 = "{"w".repeat(offset)}q7{"w".repeat(tail)}"
			m2 = digit.find(text2) ?? fail("no digit match at {offset}")
			expect m2.start == offset and m2.end == offset + 2
			text3 = "{"w".repeat(offset)}z{"w".repeat(tail)}"
			expect lone.count(text3) == 1
			expect lone.find(text3, offset + 1) == none

type Case:
	pattern str
	text str
	spans str
	replaced str

cases = [
	Case("(ab|a)(\\db[a-c]a*?)??|(?:b|bc)", "x\na", "2-3 ", "x\n<>"),
	Case("$\\d*?", "ax1\n", "3-3 4-4 ", "ax1<>\n<>"),
	Case("c|^(a|b)*?[ab]", "x1axb\nxx", "", "x1axb\nxx"),
	Case(r"[^a](?:b|bc){0,2}|(a|b)*((?:b|bc){0,2}.$.){0,2}", "cxc\n11\nax", "0-1 1-2 2-3 3-4 4-5 5-6 6-7 7-8 8-9 9-9 ", "<><><><><><><><><><>"),
	Case(r"(a|b)*\d|\d*(a|b)[^a]*?(x{0,2}$)|b", "cbca1bccabbc", "1-2 3-5 5-6 8-12 ", "c<>c<><>cc<>"),
	Case(r"(?:b|bc)\d+|[^a]+[ab].*(ac{0,2})|.a{2,}$[^a]", "cbbacaacc\nb", "0-9 ", "<>\nb"),
	Case("(ab|a)*(ab|a)(ab|a)x", "bcab1\n", "", "bcab1\n"),
	Case(r"((?:b|bc)|[ab]*?x{2,}$c*?){2}(a|b)(?:b|bc)(a|b)|c??(ab|a)??", "b1\nx", "0-0 1-1 2-2 3-3 4-4 ", "<>b<>1<>\n<>x<>"),
	Case(r"(ab|a)*(((ab|a)){0,2}.){0,2}", "caaca1\n", "0-4 4-6 6-6 7-7 ", "<><><>\n<>"),
	Case("b", "b1x", "0-1 ", "<>1x"),
	Case(r"bc{2}", "c1c\nxcab", "", "c1c\nxcab"),
	Case(r"(^\d+[^a]|$(ab|a))\d{0,2}.+", "x", "", "x"),
	Case("(?:b|bc)*?", "acbc", "0-0 1-1 2-2 2-3 3-3 4-4 ", "<>a<>c<><><>c<>"),
	Case(".(ab|a)*?a+?", "\n", "", "\n"),
	Case("a??", "a1", "0-0 0-1 1-1 2-2 ", "<><><>1<>"),
	Case(r"bcx{0,2}", "cbbb1\nac1", "", "cbbb1\nac1"),
	Case("ca|(?:b|bc)", "x1xaxcbc", "6-7 ", "x1xaxc<>c"),
	Case(r"a((c+?[a-c]){1,2}((a|b)\d(?:b|bc)){1,2}.{2,})[ab]+$", "1b", "", "1b"),
	Case("[ab](((ab|a))+?[a-c]$\\d)c", "c", "", "c"),
	Case("[ab]?", "\n\n\naxbxxx", "0-0 1-1 2-2 3-4 4-4 5-6 6-6 7-7 8-8 9-9 ", "<>\n<>\n<>\n<><>x<><>x<>x<>x<>"),
	Case(r"[^a]\d{2,}", "\n", "", "\n"),
	Case("[ab]a(x?(a|b)+?)?", "xab1xbc", "", "xab1xbc"),
	Case(r"((a|b))|(ab|a)??$([^a]{2}[^a](?:b|bc)b)*", "1\n\n\n1bx11x", "5-6 10-10 ", "1\n\n\n1<>x11x<>"),
	Case(r"([^a](ab|a){2,})((?:b|bc)*[a-c]{2})([^a])", "cxbx1ac", "", "cxbx1ac"),
	Case("^|(?:b|bc)?", "\n\nc1cb", "0-0 1-1 2-2 3-3 4-4 5-6 6-6 ", "<>\n<>\n<>c<>1<>c<><>"),
	Case(".+^", "x11\na", "", "x11\na"),
	Case("[ab]x*?", "bxc1c\n", "0-1 ", "<>xc1c\n"),
	Case("[ab]x", "cxbcba", "", "cxbcba"),
	Case("x?(ab|a)?|^[ab]*?", "aabx", "0-1 1-3 3-4 4-4 ", "<><><><>"),
	Case(r"\d($|[^a][ab]?b*?\d?)+?\d{1,2}", "x1aba", "", "x1aba"),
	Case("a", "1cbxb\n", "", "1cbxb\n"),
	Case("$a", "xcbax\ncaa", "", "xcbax\ncaa"),
	Case("(a|b)+?", "abax\nb", "0-1 1-2 2-3 5-6 ", "<><><>x\n<>"),
	Case(r"(?:b|bc){1,2}[a-c]+?(?:b|bc){2,}", "bcx1\n1\n1a", "", "bcx1\n1\n1a"),
	Case(r"(a|b){0,2}[a-c]+?^", "c", "", "c"),
	Case(r"(x+x|a*\d[a-c]){0,2}(ba?[ab]){2}", "1bcc1x1x", "", "1bcc1x1x"),
	Case(r"c{0,2}", "\n11ac\nbbc", "0-0 1-1 2-2 3-3 4-5 5-5 6-6 7-7 8-9 9-9 ", "<>\n<>1<>1<>a<><>\n<>b<>b<><>"),
	Case(r"(a|b)?(x[a-c]??^)c$|\d{2}x{2,}((a|b)+?)", "\ncxcx", "", "\ncxcx"),
	Case("(a|b)+?(?:b|bc)+c", "a1\nc\nabca\n11", "5-8 ", "a1\nc\n<>a\n11"),
	Case("((?:b|bc)(x+?.(ab|a)*?))", "acxba\n1x1xa", "", "acxba\n1x1xa"),
	Case(r"(ab|a)(ab|a){1,2}(^a(a|b))(ab|a){2}", "x1\n1cxcb", "", "x1\n1cxcb"),
	Case(r"([ab]^|[a-c]*bx+?\d??)$\d?(x(ab|a))|^[^a]{1,2}[a-c]?.*|\db?", "x", "0-1 ", "<>"),
	Case("(a|b)*", "\n", "0-0 1-1 ", "<>\n<>"),
	Case(r"x+?(?:b|bc)*$(b{0,2}\d{1,2}(c[a-c])x){2,}", "aa\n\nc\nc", "", "aa\n\nc\nc"),
	Case(r"(a|b)+|[ab]?((a|b))[ab]|\d{1,2}.{2,}", "1\nx1ba1c1\nb", "3-9 10-11 ", "1\nx<>\n<>"),
	Case("[^a]+c|(.)", "aac1b", "0-1 1-2 2-3 3-4 4-5 ", "<><><><><>"),
	Case("^", "c1\n1x", "0-0 ", "<>c1\n1x"),
	Case("b+?", "\n1", "", "\n1"),
	Case(r"([ab]*){2}", "\n\nba\ncca1ca", "0-0 1-1 2-4 4-4 5-5 6-6 7-8 8-8 9-9 10-11 11-11 ", "<>\n<>\n<><>\n<>c<>c<><>1<>c<><>"),
	Case("$^(ab|a)+", "\n1x1x1xcb", "", "\n1x1x1xcb"),
	Case("(c|[ab])?[a-c]b", "\n1\n1a1cx\nbba", "9-11 ", "\n1\n1a1cx\n<>a"),
	Case(r"(?:b|bc)??[^a]{2}", "a1bcc\n", "1-3 3-5 ", "a<><>\n"),
	Case("(a|b)", "\n1axax", "2-3 4-5 ", "\n1<>x<>x"),
	Case(r"[ab]{2,}(($)?(a|b)+?$(?:b|bc)*?)b?b", "cc\n\na1xxxcc", "", "cc\n\na1xxxcc"),
	Case(r"\d{1,2}[ab]{2}((\d(?:b|bc))|[ab]{2})$", "a1bxb\n", "", "a1bxb\n"),
	Case(r"[^a]{0,2}(a|b){2,}|[a-c]{0,2}(.{1,2})", "a\nxa1baa", "0-1 2-4 4-8 ", "<>\n<><>"),
	Case(r"\d{2,}c[^a]", "x1b\nx\nxbxccb", "", "x1b\nx\nxbxccb"),
	Case(r"(ab|a){2,}b?[ab]+?", "", "", ""),
	Case("c+$", "x\nb1b1xx", "", "x\nb1b1xx"),
	Case("b*a?", "\n1", "0-0 1-1 2-2 ", "<>\n<>1<>"),
	Case(".*?", "c\nbbc\n", "0-0 0-1 1-1 2-2 2-3 3-3 3-4 4-4 4-5 5-5 6-6 ", "<><><>\n<><><><><><><>\n<>"),
	Case(r"[^a]{0,2}x|(ab|a){2,}|c(?:b|bc)b", "\nb1", "", "\nb1"),
	Case(r"b.{0,2}c($){1,2}", "ca\n", "", "ca\n"),
	Case("(?:b|bc).", "xcxa\nb", "", "xcxa\nb"),
	Case(r"(\d)(x?){0,2}", "bbc\n1", "4-5 ", "bbc\n<>"),
	Case(r"[^a]{2,}|x*(ab|a)", "ax11\nc", "0-1 1-6 ", "<><>"),
	Case("[ab]*(a|b)a[^a]", "a1cx", "", "a1cx"),
	Case(r"(a|b)(b??)??(x{0,2}|[^a]?(ab|a)+)[a-c]", "ca\na\nbcx1", "5-7 ", "ca\na\n<>x1"),
	Case(r"(ab|a)?[ab]{0,2}^|[ab]{0,2}", "b1a1ccc1baxc", "0-0 0-1 1-1 2-3 3-3 4-4 5-5 6-6 7-7 8-10 10-10 11-11 12-12 ", "<><><>1<><>1<>c<>c<>c<>1<><>x<>c<>"),
	Case("a?", "", "0-0 ", "<>"),
	Case(r"c+(^|[^a])^((a+){0,2}.{1,2}(a|b)+.{2,}|(ab|a)*\d+(?:b|bc)(?:b|bc))", "a\nxb\n", "", "a\nxb\n"),
	Case(r"x(a|b)(ab|a)x|(?:b|bc){2}(ab|a)*(ab|a)", "b1xb\n", "", "b1xb\n"),
	Case("[^a][a-c]+[^a][ab]", "", "", ""),
	Case(r"[^a]x+(c{2})?", "1\n1\ncccxx1xa", "6-9 9-11 ", "1\n1\ncc<><>a"),
	Case(r"[a-c](ab|a){2}", "b\nc\n\nca\n\n", "", "b\nc\n\nca\n\n"),
	Case(r"\da??x{2,}|$[ab](bx(?:b|bc)[ab]*?)", "bc", "", "bc"),
	Case("b", "aaaaa1cca1a", "", "aaaaa1cca1a"),
	Case(r"\d{0,2}(a|b)*?", "", "0-0 ", "<>"),
	Case(r"(a|b)??((a|b).+|^c{1,2}c+?)+", "b\nbaaba\n\naa\n", "2-7 9-11 ", "b\n<>\n\n<>\n"),
	Case("[ab]x+?", "ccx\n1", "", "ccx\n1"),
	Case("x*?xc+$", "cccxxccc", "3-8 ", "ccc<>"),
	Case(r"\d+?c{0,2}^c|x??|[ab]?(a|b){1,2}b(?:b|bc)?", "", "0-0 ", "<>"),
	Case("^", "c1c1\n\ncc\nab", "0-0 ", "<>c1c1\n\ncc\nab"),
	Case(r"a^([^a]*.(.+?c+))x{1,2}", "b1cbxac", "", "b1cbxac"),
	Case("a.[ab]", "", "", ""),
	Case(r"c{2}[a-c]??$", "c1c\nbcbca", "", "c1c\nbcbca"),
	Case(r"[^a](c(ba)??(a|b)\d{0,2}){2,}(ab|a)[^a]{0,2}", "x", "", "x"),
	Case(r"(((ab|a)?(ab|a)*(ab|a){2,})(a|b){1,2}b?(.[a-c]{0,2}(a|b){0,2}))[ab]x{2}", "\nb1xx1xc", "", "\nb1xx1xc"),
	Case(r"(b{2}|(a|b)a(ab|a){2}[ab]){2,}(((a|b)??)|^)", "abx1x1\nx", "", "abx1x1\nx"),
	Case(r"((\dc+)??(a|b)*)[ab]{2,}", "cbaxbxbxa1a1", "1-3 ", "c<>xbxbxa1a1"),
	Case(r"[^a]{0,2}(?:b|bc)(a|b){1,2}", "bbb1b1ba", "0-3 4-8 ", "<>1<>"),
	Case("(ab|a)*[^a](?:b|bc)+?", "x\nx\nb", "3-5 ", "x\nx<>"),
	Case("[a-c]", "1bba1cxb\ncax", "1-2 2-3 3-4 5-6 7-8 9-10 10-11 ", "1<><><>1<>x<>\n<><>x"),
	Case("$", "a1", "2-2 ", "a1<>"),
	Case("$[a-c]", "1cbbbb1bbax", "", "1cbbbb1bbax"),
	Case(r"((ab|a)[^a]?.{1,2}|c)??(b{1,2}.*^|bx)", "\n11\n\nx\n", "", "\n11\n\nx\n"),
	Case(r"c$[a-c]|c{2}", "x1aab1aax", "", "x1aab1aax"),
	Case(r"(^[^a]){1,2}c(x|$a?)*", "1xax111ab1\n\n", "", "1xax111ab1\n\n"),
	Case("(?:b|bc).\\d+b", "a", "", "a"),
	Case(r"b{2,}(((ab|a){2}(a|b)*(?:b|bc)[ab])??$\d{0,2}c+?){0,2}(?:b|bc)", "11xx\nbcaab", "", "11xx\nbcaab"),
	Case(r"x[ab]{0,2}(\d{2,}[^a]*)(ab|a)|^(b??(ab|a)^^)b", "abba1aaa11", "", "abba1aaa11"),
	Case("$c*?b", "c1bc1b", "", "c1bc1b"),
	Case("x*", "xxxa", "0-3 3-3 4-4 ", "<><>a<>"),
	Case(r".{2}x", "bb", "", "bb"),
	Case("$([^a]?^^b)", "\ncbb", "", "\ncbb"),
	Case(r"(\d*?x+?^.*?){1,2}[^a](?:b|bc){0,2}[a-c]{2}", "xb", "", "xb"),
	Case(r"[ab]+|\d+[^a]{0,2}$", "a1\n\nacxcac", "0-1 4-5 8-9 ", "<>1\n\n<>cxc<>c"),
	Case("(a$[a-c].*)*([^a]*)+", "ccb\nc1bc1", "0-9 9-9 ", "<><>"),
	Case(r".[ab]{0,2}", "1a\nx", "0-2 3-4 ", "<>\n<>"),
	Case(r"x*?([a-c]{0,2}$(^.{1,2}.+^)){1,2}(x)|\d*.|[ab][ab]*x{1,2}", "c", "0-1 ", "<>"),
	Case("(?:b|bc)+((ab|a)a)ca?", "a11cbxa1c", "", "a11cbxa1c"),
	Case(r"[ab]{2}(a|b)+c|(x*?){2}^", "a\nab1x1x", "0-0 ", "<>a\nab1x1x"),
	Case(r"([ab](.^(a|b))?|[ab]+x^(ab|a)?){1,2}$b", "b", "", "b"),
	Case(r"(a|b)[^a].{2}", "1bx1ab\n1\ncaa", "1-5 ", "1<>b\n1\ncaa"),
	Case("(ab|a)\\d$.", "ac111cb1bx", "", "ac111cb1bx"),
	Case(r"^.{0,2}(a{0,2}(^b??[a-c]){1,2}(?:b|bc))", "", "", ""),
	Case("a?", "\n\ncaxcbbc", "0-0 1-1 2-2 3-4 4-4 5-5 6-6 7-7 8-8 9-9 ", "<>\n<>\n<>c<><>x<>c<>b<>b<>c<>"),
	Case("a?", "axa", "0-1 1-1 2-3 3-3 ", "<><>x<><>"),
	Case(r"(a+?(?:b|bc)|(ab|a)){2}[ab]|x{2}c(a|b)[ab]|^\d(a|b)*?", "\n\n1bca\na", "", "\n\n1bca\na"),
	Case(r"^c(ab|a){1,2}|b+\d", "", "", ""),
	Case(r"a(?:b|bc)b{2}", "cab\nx1", "", "cab\nx1"),
	Case("[a-c]^([^a]|(ab|a)c+(a|b)*?)", "bc", "", "bc"),
	Case(r"x[a-c]|a{2}", "cx1cxca11", "4-6 ", "cx1c<>a11"),
	Case(r"((a*?){0,2}(a|b)(?:b|bc)+^|ca[a-c])", "", "", ""),
	Case("[^a][^a][a-c]a", "\naxx\na1aa11", "", "\naxx\na1aa11"),
	Case("$c+?(a|b)?$", "1c\n\nax11x", "", "1c\n\nax11x"),
	Case(r"((ab|a)((ab|a)){1,2}(c[ab]+[ab])$)*?$|x", "a", "1-1 ", "a<>"),
	Case(r"(($(ab|a).{2,}\d){2,}[a-c](ab|a)+)a(a+?)", "cxxa\nbc\n\nb11", "", "cxxa\nbc\n\nb11"),
	Case(r"[^a]{2}", "ca", "", "ca"),
	Case(r"[ab]{2,}ca", "x\n", "", "x\n"),
	Case(r"[a-c]+?a(.??[ab]){1,2}|b?b(?:b|bc)*?|[^a](ab|a)a{1,2}", "1acab\nbc\n", "1-5 6-7 ", "1<>\n<>c\n"),
	Case(r"b??$|[a-c]{2}", "\ncx1cc1ax", "4-6 9-9 ", "\ncx1<>1ax<>"),
	Case(r"(ab|a)+?(c{0,2}){2}", "x", "", "x"),
	Case("^x", "x", "0-1 ", "<>"),
	Case("^.", "cbc\n", "0-1 ", "<>bc\n"),
	Case("((a|b)+?(a|b)\\d+?)?[ab](?:b|bc)?", "aa1bca", "0-4 5-6 ", "<>c<>"),
	Case(r"a{2,}(?:b|bc)*[^a]{2}", "1aa", "", "1aa"),
	Case(r"a+?$x|(x(?:b|bc)b{2}a)\d", "\nx\nbb", "", "\nx\nbb"),
	Case(r"((?:b|bc)*(c)(\d+?){2}(a[^a]?(ab|a)))(a|b){2}((a|b))a", "bba", "", "bba"),
	Case("(a|b)(?:b|bc)[ab]+?(ab|a)|[^a]*?$(a|b)+?|.*(ab|a)+?[ab]+?", "ab\nxxccxc1bc", "0-2 ", "<>\nxxccxc1bc"),
	Case(r"$\d(b|a*x(ab|a){2})", "1\nxb\n", "", "1\nxb\n"),
	Case(r"xb??[^a]b{2}", "b", "", "b"),
	Case(r"(.[^a]){1,2}(ab|a)*?(?:b|bc)+?([ab]+?(?:b|bc)?(ab|a)|$c){1,2}|$|.(ab|a)", "ca1cac1c", "0-2 3-5 8-8 ", "<>1<>c1c<>"),
	Case(r"(?:b|bc){0,2}(ab|a)?", "x", "0-0 1-1 ", "<>x<>"),
	Case(r"[^a][a-c]([^a]{1,2}){1,2}.", "1b", "", "1b"),
	Case("b*?x+?\\d*", "1bxa", "1-3 ", "1<>a"),
	Case(r"[^a]cc{1,2}\d|[a-c]a*?(?:b|bc)?\d?|^bb[a-c]", "", "", ""),
	Case(".c(?:b|bc)\\d", "1bbca1aa1ca1", "", "1bbca1aa1ca1"),
	Case("\\d?x", "c\n", "", "c\n"),
	Case(r"bx((.{2,}^b*)(^x{1,2}){2}){2}", "xccxbcacb\nax", "", "xccxbcacb\nax"),
]

test "patterns agree with Python's re":
	for c in cases:
		re = regex.compile(c.pattern) ?? fail
		got = ""
		for m in re.findAll(c.text):
			got += "{m.start}-{m.end} "
		expect got == c.spans
		expect re.replace(c.text, "<>") == c.replaced

# Flags lead the pattern: `(?m)` makes `^` and `$` hold at the ends of each line too, `(?i)` makes
# ASCII letters match in either case, `(?s)` makes `.` match a newline (Python's re.M, re.I, re.S).

test "(?m): ^ and $ match at the ends of each line":
	expect found("(?m)^b", "a\nb") == "2-3"
	expect found("^b", "a\nb") == "none"
	expect found("(?m)a$", "ba\nb") == "1-2"
	expect found("a$", "ba\nb") == "none"
	expect found("(?m)^$", "a\n\nb") == "2-2"
	expect found("(?m)a$\nb", "xa\nb") == "1-4"
	expect found("(?m)a$|a\nb", "a\nb") == "0-1"
	expect found("(?m)a\n^b|a", "a\nb") == "0-3"
	lines = regex.compile(r"(?m)^\w+$") ?? fail
	expect lines.count("ab\ncd\n\nef") == 3
	expect lines.replace("ab\ncd\n\nef", "<>") == "<>\n<>\n\n<>"
	expect lines.count("ab cd\nef") == 1
	ends = regex.compile("(?m)$") ?? fail
	expect ends.count("a\nb\n") == 3
	starts = regex.compile("(?m)^a") ?? fail
	expect (starts.find("aa\na", 1) ?? fail("none")).start == 3
	expect starts.find("ba", 1) == none

# ^, $ and the matches in a text of lines agree with the pattern run on each line alone.
test "(?m) over random lines is the pattern over each line":
	patterns = ["^a", "b$", "^$", "a$|^b", "^a+b?$", "a*", "^[ab]*$", "b*$", "(^a|b$)+", "^|a", "$"]
	seed u32 = 11
	for pattern in patterns:
		whole = regex.compile("(?m){pattern}") ?? fail
		alone = regex.compile(pattern) ?? fail
		for size in [12, 12, 12, 12, 12, 12, 12, 12, 300, 300]:
			text = ""
			loop size:
				seed = (seed * 1_103_515_245 + 12_345) % 2_147_483_648
				text += "ab\n"[(seed >> 16) % 3..][..1]
			expected = ""
			at = 0
			for line in "{text}\n".lines():
				for m in alone.findAll(line):
					expected += "{at + m.start}-{at + m.end} "
				at += line.len + 1
			got = ""
			for m in whole.findAll(text):
				got += "{m.start}-{m.end} "
			expect got == expected

test "(?i): ASCII letters match in either case":
	expect found("(?i)abc", "xxABc") == "2-5"
	expect found("abc", "xxABc") == "none"
	expect found("(?i)[a-c]+", "xxBcAz") == "2-5"
	expect found("(?i)[^a]", "Ab") == "1-2"
	expect found(r"(?i)\x41", "xa") == "1-2"
	expect found("(?i)é", "É") == "none"

test "(?s): . matches a newline":
	expect found("(?s)a.c", "a\nc") == "0-3"
	expect found("a.c", "a\nc") == "none"
	expect found("(?s)a.*c", "xa\nbc") == "1-5"

test "flags together, and a flag that is not one":
	expect found("(?ims)^A.c$", "x\nA\nC") == "2-5"
	expect found("(?i)(?m)^a", "b\nA") == "2-3"
	match regex.compile("(?x)a"):
		error: expect error.startsWith("regex: ")
		_: expect false
	match regex.compile("(?i"):
		error: expect error.startsWith("regex: ")
		_: expect false
