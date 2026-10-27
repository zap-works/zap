# std/regex against Python's re (3.14, Unicode 16): what a fuzz of random patterns over short texts
# found different, each as a test, word edges and groups, and a table of random patterns with the
# matches Python's `finditer` gives (the span of each match in bytes, then its groups, `@@` for one
# that took no part).

import regex

fn compiled(pattern str) regex.Regex:
	regex.compile(pattern) ?? fail("{pattern} does not compile")

# the spans of the matches of the pattern, as `start-end` words
fn spansOf(pattern str, text str) str:
	re = compiled(pattern)
	re.findAll(text).map("{it.start}-{it.end}").join(" ")

# the groups of the first match, as `0:...|1:...`, `-` for one that took no part
fn groupsOf(pattern str, text str) str:
	re = compiled(pattern)
	match re.find(text):
		m:
			parts = []
			for g in 0..m.cuts.len / 2:
				parts.push("{g}:{m.group(g) ?? "-"}")
			parts.join("|")
		none: "none"

# whether the pattern is refused with a message that holds `part`
fn says(pattern str, part str) bool:
	match regex.compile(pattern):
		error: error.indexOf(part) != none
		_: false

test "a quantifier after a quantifier is refused: a possessive one by name, the others as Python's multiple repeat":
	expect says("a*+", "possessive quantifier is unsupported")
	expect says("a++b", "possessive quantifier is unsupported")
	expect says("a?+", "possessive quantifier is unsupported")
	expect says(r"a{1,2}+", "possessive quantifier is unsupported")
	expect says("(?>a)", "atomic group is unsupported")
	expect says("a**", "multiple repeat")
	expect says("a*??", "multiple repeat")
	expect says(r"a{2}{3}", "multiple repeat")
	expect says("a+*", "multiple repeat")
	expect spansOf("a*?", "aa") == "0-0 0-1 1-1 1-2 2-2"
	expect spansOf("(?:a*)*", "b") == "0-0 1-1"

test "an assertion cannot be repeated, a group that holds one can":
	expect says("^*", "nothing to repeat")
	expect says("$+", "nothing to repeat")
	expect says(r"\b?", "nothing to repeat")
	expect says(r"\B{2}", "nothing to repeat")
	expect says("*a", "nothing to repeat")
	expect says("a|*", "nothing to repeat")
	expect says(r"{2}", "nothing to repeat")
	expect spansOf("(?:^)*a", "a") == "0-1"
	expect spansOf(r"(\b)+a", "a") == "0-1"

test "a brace that does not begin a repetition is a literal one, and a missing low bound is zero":
	expect spansOf(r"a{", r"a{ a") == "0-2"
	expect spansOf(r"a{2", r"a{2") == "0-3"
	expect spansOf(r"a{x}", r"a{x}") == "0-4"
	expect spansOf(r"a{,2}", "aaa") == "0-2 2-3 3-3"
	expect spansOf(r"a{,}", "aa") == "0-2 2-2"
	expect spansOf(r"a{2}{", r"aa{") == "0-3"
	expect says(r"a{3,1}", "reversed repetition")

test "$ holds before the text's last newline, ^ and \\b do not move":
	expect spansOf("a$", "a\n") == "0-1"
	expect spansOf("a$", "a\n\n") == ""
	expect spansOf("$", "a\n") == "1-1 2-2"
	expect spansOf("$", "\n") == "0-0 1-1"
	expect spansOf("$", "") == "0-0"
	expect spansOf("^$", "\n") == "0-0"
	expect spansOf("$^", "") == "0-0"
	expect spansOf(r"a$\n", "a\n") == "0-2"
	expect spansOf(r"a$\s", "a\n") == "0-2"
	expect spansOf("$|b", "b\n") == "0-1 1-1 2-2"
	expect spansOf("$\\D", "a\n") == "1-2"
	expect spansOf(r"a\b$", "a\n") == "0-1"
	expect spansOf("(?m)a$", "a\na\n") == "0-1 2-3"
	expect groupsOf("(a)$", "a\n") == "0:a|1:a"
	expect compiled("x$").isMatch("x\n")
	expect not compiled("x$").isMatch("x\n\n")
	expect not compiled("x$").isMatch("x\ny")

test "after a match, an empty one is found right at its end, and after an empty one the next may not be empty there":
	expect spansOf("a*", "baac") == "0-0 1-3 3-3 4-4"
	expect spansOf("a*?", "aa") == "0-0 0-1 1-1 1-2 2-2"
	expect spansOf("|a", "a") == "0-0 0-1 1-1"
	expect spansOf("a??", "a1") == "0-0 0-1 1-1 2-2"
	expect spansOf("$|\\D", "a\n") == "0-1 1-1 1-2 2-2"
	expect compiled("x*").replace("abxd", "-") == "-a-b--d-"
	expect compiled("a??").replace("a1", "-") == "---1-"
	expect compiled("|a").count("a") == 3
	expect compiled("(|a)+").replace("a", "<>") == "<><><>"
	expect groupsOf("(|a)+", "a") == "0:|1:"

test "a group repeated by a loop that reads nothing in its last turn keeps what the last turn gave":
	expect groupsOf("(a*)*", "b") == "0:|1:"
	expect groupsOf("(a*)*", "aa") == "0:aa|1:"
	expect groupsOf("(a*)+", "aa") == "0:aa|1:"
	expect groupsOf("(a|b)*", "ab") == "0:ab|1:b"
	expect groupsOf("(a?)*", "") == "0:|1:"
	expect groupsOf("(a*)*b", "aab") == "0:aab|1:"
	expect groupsOf(r"(\w*)*", "ab") == "0:ab|1:"
	expect groupsOf("(a|)*", "a") == "0:a|1:"
	expect groupsOf("(?:(a)|b)*", "ab") == "0:ab|1:a"
	expect groupsOf(r"(a){0,2}", "a") == "0:a|1:a"
	expect groupsOf(r"(|a){0,2}", "a") == "0:|1:"

test "a group by name is named, not the argument of group":
	re = compiled("(?P<year>[0-9]+)-(?P<month>[0-9]+)")
	m = re.find("on 2026-10 ok") ?? fail("none")
	expect (m.named("year") ?? "-") == "2026"
	expect (m.named("month") ?? "-") == "10"
	expect (m.group(2) ?? "-") == "10"
	expect m.named("day") == none

test "a character is a unit: . [^a] and a class match the whole of it":
	expect spansOf("caf.", "café") == "0-5"
	expect spansOf("^.$", "é") == "0-2"
	expect spansOf("^.$", "世") == "0-3"
	expect spansOf("^.$", "😀") == "0-4"
	expect spansOf("^..$", "é") == ""
	expect spansOf("[^a]", "aé世b") == "1-3 3-6 6-7"
	expect spansOf("[é-ü]+", "xéüy") == "1-5"
	expect spansOf("[^é]", "éa") == "2-3"
	expect spansOf("[世-界]", "世a界") == "0-3 4-7"
	expect spansOf(r"\xe9", "é") == "0-2"
	expect spansOf(r"世\U0001F600", "世😀") == "0-7"
	expect spansOf("", "é") == "0-0 2-2"
	expect spansOf("x*", "éé") == "0-0 2-2 4-4"
	expect spansOf("(?s).", "\n") == "0-1"
	expect spansOf(".", "\n") == ""

test "\\w, \\d and \\s are Unicode's, and the flag a keeps them to ASCII":
	expect spansOf(r"\w+", "naïve 世界_1 x") == "0-6 7-15 16-17"
	expect spansOf(r"\W", "é-") == "2-3"
	expect spansOf(r"\d+", "a٣٤b5") == "1-5 6-7"
	expect spansOf(r"\D", "٣a") == "2-3"
	expect spansOf(r"\s+", "a b　c d") == "1-3 4-7 8-9"
	expect spansOf(r"\S+", "a b") == "0-1 4-5"
	expect spansOf(r"[\w-]+", "é-é") == "0-5"
	expect spansOf(r"[^\w]", "é世!") == "5-6"
	expect spansOf(r"(?a)\w+", "naïve") == "0-2 4-6"
	expect spansOf(r"(?a)\d", "٣5") == "2-3"
	expect spansOf(r"(?a)\W", "é") == "0-2"
	expect spansOf(r"(?a)(?i)k", "Kk") == "3-4"
	expect spansOf(r"(?i)k", "Kk") == "0-3 3-4"

test "(?i) takes the letters of every script that are one letter in two cases for each other":
	expect spansOf("(?i)é", "É é") == "0-2 3-5"
	expect spansOf("(?i)straße", "STRAßE") == "0-7"
	expect spansOf("(?i)σ", "Σ ς σ") == "0-2 3-5 6-8"
	expect spansOf("(?i)s", "S ſ s") == "0-1 2-4 5-6"
	expect spansOf("(?i)[a-k]+", "xAbKKy") == "1-7"
	expect spansOf("(?i)[^a]", "Aa b") == "2-3 3-4"
	expect spansOf("(?i)ǆ", "Ǆ ǅ ǆ") == "0-2 3-5 6-8"
	expect spansOf("(?i)i", "İı") == "0-2 2-4"

test "a word's edge is the edge of a word of any script":
	expect spansOf(r"\bé", "é") == "0-2"
	expect spansOf(r"\bcaf\b", "café caf") == "6-9"
	expect spansOf(r"\b", "é a") == "0-0 2-2 3-3 4-4"
	expect spansOf(r"\B", "éa") == "2-2"
	expect spansOf(r"\w+\b", "世界-x") == "0-6 7-8"
	expect spansOf(r"x\b", "xé x") == "4-5"
	expect spansOf(r"(?a)\b", "é") == ""
	expect spansOf(r"\b世", "a世 世") == "5-8"
	expect groupsOf(r"(\b\w+\b) (\w+)", "été ça") == "0:été ça|1:été|2:ça"
	text = "the café sat on the mat ".repeat(2000)
	expect compiled(r"\bthe\b").count(text) == 4000
	expect compiled(r"\bcafé\b").count(text) == 2000
	expect compiled(r"\Bé\B").count(text) == 0

test "\\b and \\B hold at a word's edge and away from it":
	expect spansOf(r"\bcat\b", "cat concat cat.") == "0-3 11-14"
	expect spansOf(r"\Bcat", "cat concat") == "7-10"
	expect spansOf(r"\b", "ab cd") == "0-0 2-2 3-3 5-5"
	expect spansOf(r"\b\w", "ab cd") == "0-1 3-4"
	expect spansOf(r"\w+\b", "foo-bar") == "0-3 4-7"
	expect spansOf(r"\B", "ab") == "1-1"
	expect spansOf(r"\bfoo\b", "foo") == "0-3"
	expect spansOf(r"\bfoo\b", "foobar foo_ foo") == "12-15"
	expect spansOf(r"a\b", "ba a") == "1-2 3-4"

test "a word's edge is told by the bytes at both sides":
	expect spansOf(r"x\b|y", "xy x") == "1-2 3-4"
	expect spansOf(r"(?m)^\bab$", "ab\ncd\nab") == "0-2 6-8"
	expect spansOf(r"(?m)\b$", "ab\ncd") == "2-2 5-5"
	expect spansOf(r"\b(?:a|ab)\b", "ab a") == "0-2 3-4"
	expect spansOf(r"\bé", "é") == "0-2"
	expect compiled(r"\b[a-z]+\b").count("one two  three") == 3
	text = "the cat sat on the mat ".repeat(2000)
	expect compiled(r"\bthe\b").count(text) == 4000

test "a refused escape or group is named":
	expect says(r"\A", "escape \\A is unsupported")
	expect says(r"a\q", "escape \\q is unsupported")
	expect says(r"(a)\1", "escape \\1 is unsupported")
	expect says("(?=a)", "lookahead is unsupported")
	expect says("(?!a)", "lookahead is unsupported")
	expect says("(?<=a)b", "lookbehind is unsupported")
	expect says("(?<!a)b", "lookbehind is unsupported")
	expect says("(?P=n)", "backreference is unsupported")
	expect says("(?P<n>a)(?P<n>b)", "the group name n is used twice")
	expect says("(?P<1n>a)", "a bad group name")
	expect says("(?<n a)", "a bad group name")

test "groups are read from the match":
	expect groupsOf(r"(\w+)@(\w+)\.com", "mail bob@ex.com now") == "0:bob@ex.com|1:bob|2:ex"
	expect groupsOf("(a)|(b)", "b") == "0:b|1:-|2:b"
	expect groupsOf("(a*)b", "b") == "0:b|1:"
	expect groupsOf("(a+?)(a*)", "aaa") == "0:aaa|1:a|2:aa"
	expect groupsOf("(a|ab)(c|bcd)(d*)", "abcd") == "0:abcd|1:a|2:bcd|3:"
	expect groupsOf("((a)|(b))+", "ab") == "0:ab|1:b|2:a|3:b"
	expect groupsOf("(a)(?:b)(c)", "xabc") == "0:abc|1:a|2:c"
	expect groupsOf(r"(a){2}", "aaa") == "0:aa|1:a"
	expect groupsOf("(?i)(ab)c", "xABC") == "0:ABC|1:AB"
	expect groupsOf("(x)?y", "y") == "0:y|1:-"
	expect groupsOf("(é+)(!)", "caféé!") == "0:éé!|1:éé|2:!"
	expect groupsOf("(a)", "b") == "none"
	expect groupsOf(r"(\b\w+\b) (\w+)", "ab cd") == "0:ab cd|1:ab|2:cd"
	expect groupsOf(r"(?m)^(\w+)$", "ab\ncd") == "0:ab|1:ab"
	expect groupsOf(r"(\w*)\b", "ab") == "0:ab|1:ab"

test "a group has a name":
	re = compiled(r"(?P<key>\w+)=(?<val>\d+)")
	m = re.find("x a=12;") ?? fail("no match")
	expect (m.named("key") ?? "-") == "a"
	expect (m.named("val") ?? "-") == "12"
	expect m.named("other") == none
	expect (m.group(1) ?? "-") == "a"
	expect (m.group(0) ?? "-") == "a=12"
	expect m.group(3) == none
	expect m.start == 2
	expect m.end == 6
	optional = compiled("(?P<a>x)|(?P<b>y)").find("y") ?? fail("none")
	expect optional.named("a") == none
	expect (optional.named("b") ?? "-") == "y"

test "findAll gives each match its groups":
	re = compiled(r"(\w)=(\d)")
	all = re.findAll("a=1, b=2 c=x d=4")
	expect all.map("{it.group(1) ?? "-"}{it.group(2) ?? "-"}").join(",") == "a1,b2,d4"
	expect all.map("{it.start}").join(",") == "0,5,13"

test "a replacement writes groups":
	re = compiled(r"(?P<k>\w)=(?P<v>\d)")
	expect re.replace("a=1, b=2", r"\2=\1") == "1=a, 2=b"
	expect re.replace("a=1, b=2", r"\g<v>=\g<k>") == "1=a, 2=b"
	expect re.replace("a=1, b=2", r"[\g<0>]") == "[a=1], [b=2]"
	expect re.replace("a=1", r"\g<1>\g<2>\\n") == "a1\\n"
	expect re.replace("a=1", "\\1\\t|") == "a\t|"
	expect re.replace("a=1", r"\.\1") == "\\.a"
	optional = compiled("(a)|(b)")
	expect optional.replace("ab", r"<\1\2>") == "<a><b>"
	expect compiled("x").replace("axb", r"\\") == "a\\b"
	expect compiled("(o)").replace("foo", r"\1\1") == "foooo"
	expect compiled(r"fs\.(readFile|readBytes)\(").replace("a fs.readFile(x)", r"fs.load(") ==
		"a fs.load(x)"
	expect compiled(r"(\d+)").replace("a1b22", r"<\g<1>>") == "a<1>b<22>"

test "a replacement that is not one" stops Failure:
	compiled("(a)").replace("a", r"\2")

test "a replacement by a function of the match":
	re = compiled(r"(\w)=(\d)")
	expect re.replaceWith("a=1, b=2", m: "{m.group(2) ?? "-"}{m.group(1) ?? "-"}") == "1a, 2b"
	expect re.replaceWith("none", m: "?") == "none"
	numbers = compiled(r"\d+")
	expect numbers.replaceWith("a1b22", m: "{(i64.parse(m.text) ?? 0) * 2}") == "a2b44"
	expect numbers.replaceWith("x", m: "y") == "x"

type Case:
	pattern str
	text str
	matches str

cases = [
	Case(r"", "s\nẞkΣÉK\n", "0-0 ; 1-1 ; 2-2 ; 5-5 ; 6-6 ; 8-8 ; 10-10 ; 11-11 ; 12-12"),
	Case(r"c*", "c", "0-1 ; 1-1"),
	Case(r"(?P<n419404>c*a+[^b-c](?P<n453531>cb))+?", "a\n_", ""),
	Case(r"\D*?c|a()*?", "", ""),
	Case(r"(?:b[^é]b+|c(?:[^é]|a|\da)(?:[^\s]+|a{2,}|b{1,2}?)[É-Ü])*?", "Sb\nſ", "0-0 ; 1-1 ; 2-2 ; 3-3 ; 5-5"),
	Case(r"(?m)c{0,2}", "σ٣", "0-0 ; 2-2 ; 4-4"),
	Case(r"a{1,2}?(|(.a\Bc{1,2}?)[\w]{2})|", "1", "0-0:@@:@@ ; 1-1:@@:@@"),
	Case(r"a[^a]{1,2}", "", ""),
	Case(r"|bc{0,2}(?P<n251152>c??)?", "éſK", "0-0:@@ ; 2-2:@@ ; 4-4:@@ ; 7-7:@@"),
	Case(r"(?i)", "٣KẞkS\nK世", "0-0 ; 2-2 ; 5-5 ; 8-8 ; 9-9 ; 10-10 ; 11-11 ; 12-12 ; 15-15"),
	Case(r"(?P<n39354>|(b*.{1,2})a(é{1,2})?|c+?.)+|(?P<n717428>\b()(){2,})", "", "0-0::@@:@@:@@:@@:@@"),
	Case(r"(?m)(a+?a{1,2}.?)a", "abÉéaé", ""),
	Case(r"|[\w](?P<n728296>[é-ü]|c$^b)(?P<n185987>b{1,2}?.{1,2}?a+?)", "", "0-0:@@:@@"),
	Case(r"(?ms)a(?:)|[^\s]??", "", "0-0"),
	Case(r"c+|b|[a-c][ß-ſ]", "K s", ""),
	Case(r"a|c?a|^ac??é", "c", ""),
	Case(r"\B|\b", "ß", "0-0 ; 2-2"),
	Case(r"(?im)b", "", ""),
	Case(r"(?P<n990130>(?:c*|c+?.)[^a]$)a|", "ß\né٣٣b 世", "0-0:@@ ; 2-2:@@ ; 3-3:@@ ; 5-5:@@ ; 7-7:@@ ; 9-9:@@ ; 10-10:@@ ; 11-11:@@ ; 14-14:@@"),
	Case(r"a(|.|).{0,2}", "é", ""),
	Case(r"ß{2,}(||\B)", "İ1ß", ""),
	Case(r"(?im)c(?P<n884263>\bc[^a]b+)*|[é-ü]|(?:|)[σ]+", "Σ", "0-2:@@"),
	Case(r"(?m)\D*?", " _b", "0-0 ; 0-1 ; 1-1 ; 1-2 ; 2-2 ; 2-3 ; 3-3"),
	Case(r"ab+|.()$|", "ÉſſıSß", "0-0:@@ ; 2-2:@@ ; 4-4:@@ ; 6-6:@@ ; 8-8:@@ ; 9-11: ; 11-11:@@"),
	Case(r".", "\nb٣_世b世ß", "1-2 ; 2-4 ; 4-5 ; 5-8 ; 8-9 ; 9-12 ; 12-14"),
	Case(r"(?P<n851381>b)", "scÉaΣẞbσ", "10-11:b"),
	Case(r"(?ms)b{1,2}?|(\b(?:\D))", "c1K", "0-1:c"),
	Case(r"(?i)|(b|é??)(?:ß)", "k_ẞς1ς", "0-0:@@ ; 1-1:@@ ; 2-2:@@ ; 2-5: ; 5-5:@@ ; 7-7:@@ ; 8-8:@@ ; 10-10:@@"),
	Case(r"(|b|){0,2}[^a]", "٣ßa", "0-2: ; 2-4:"),
	Case(r"|(?:.??)|c{0,2}", "Sc Sς世", "0-0 ; 0-1 ; 1-1 ; 1-2 ; 2-2 ; 2-3 ; 3-3 ; 3-4 ; 4-4 ; 4-6 ; 6-6 ; 6-9 ; 9-9"),
	Case(r"\D{1,2}", "ẞs_Kς", "0-4 ; 4-8 ; 8-10"),
	Case(r"[^\s](.(\sc{1,2}b)*)", "1c", "0-2:c:@@"),
	Case(r"\S+|(?:\dc|.)|a{0,2}", "c\nc_ \n  ", "0-1 ; 1-1 ; 2-4 ; 4-5 ; 5-5 ; 6-7 ; 7-8 ; 8-8"),
	Case(r".{0,2}", "Ks1", "0-4 ; 4-5 ; 5-5"),
	Case(r"[^é]||", " ", "0-1 ; 1-1"),
	Case(r"|(\D)c(c)|^((?:)+(?P<n564043>..))(?:|(?:bc{1,2}|a|a){1,2}b|\d+?)", "ac", "0-0:@@:@@:@@:@@ ; 0-2:@@:@@:ac:ac ; 2-2:@@:@@:@@:@@"),
	Case(r"(?P<n369079>(?:.??b??|c)([a-k]*.))", "K世1 a", "0-1:K:K ; 1-4:世:世 ; 4-5:1:1 ; 5-6: :  ; 6-7:a:a"),
	Case(r"(?P<n10235>(?:\d*?.c|c??a{2}b??)|(|bc){2}b{0,2}){2,}", "11\n _acc", "0-0:: ; 1-1:: ; 2-2:: ; 3-3:: ; 4-4:: ; 5-7:: ; 7-7:: ; 8-8::"),
	Case(r"(?s)\W(?:.)()", "1sς σ_ſς", "4-7:"),
	Case(r"b\B.", "b1\n1", "0-2"),
	Case(r"\D", "ab\nb", "0-1 ; 1-2 ; 2-3 ; 3-4"),
	Case(r"b?c[ß-ſ]{2}.|.{1,2}", "ς٣İ", "0-4 ; 4-6"),
	Case(r"a", "a111", "0-1"),
	Case(r"(?:)*?[\w]", "11 a٣", "0-1 ; 1-2 ; 3-4 ; 4-6"),
	Case(r"(?ms)c*[a-c]", "aaS", "0-1 ; 1-2"),
	Case(r"(?m).(\D+?|(?P<n647393>aa{2,}c*).??(?:)^)", "a1ab", "1-3:a:@@"),
	Case(r".??", "_é1ß世 ", "0-0 ; 0-1 ; 1-1 ; 1-3 ; 3-3 ; 3-4 ; 4-4 ; 4-6 ; 6-6 ; 6-9 ; 9-9 ; 9-10 ; 10-10"),
	Case(r"(\Sc|(c{1,2}?a|b|a))?.|", "ς", "0-2:@@:@@ ; 2-2:@@:@@"),
	Case(r"(?:.{0,2}$)", "sKcKsσ", "8-11 ; 11-11"),
	Case(r"[^b-c]", "_c\n", "0-1 ; 2-3"),
	Case(r"[σ]", "1ßσß_", "3-5"),
	Case(r"\S{2,}b{0,2}[_a]*[a-k]", "ẞsa\nb", "0-5"),
	Case(r"[_a]c", " ac c", "1-3"),
	Case(r"[世]*?c(?:\da)^|(.)|b+?a", "ıς", "0-2:ı ; 2-4:ς"),
	Case(r".\B.+", "1٣٣ 世b", "0-10"),
	Case(r"a(?:)", "\naßσa", "1-2 ; 6-7"),
	Case(r"\w*?c??", "KbSc", "0-0 ; 0-3 ; 3-3 ; 3-4 ; 4-4 ; 4-5 ; 5-5 ; 5-6 ; 6-6"),
	Case(r"\d+a|.", "1a", "0-2"),
	Case(r"(?:\B(?P<n446116>.))", "ac1c", "1-2:c ; 2-3:1 ; 3-4:c"),
	Case(r"b((c|[^b-c]??a)*)", "ab cc1", "1-2::@@"),
	Case(r"(?im)\D", "c", "0-1"),
	Case(r".+|b??c+?", "aab1__ c", "0-8"),
	Case(r".c*?c|(?:.|(|\wa{0,2}b{1,2}?)(.c*?){1,2}(?:ca{2,}[ß-ſ]|cb??)(|))(a)", "ßẞscÉs", "5-7:@@:@@:@@:@@"),
	Case(r"b{2}b??", "b٣_ſ世\nbb", "10-12"),
	Case(r".|.c|a", "a ", "0-1 ; 1-2"),
	Case(r"(c*|^)(b)*(?:^.{0,2}|cca{1,2}?(?P<n706651>b)|)", "ıÉẞİ", "0-4::@@:@@ ; 4-4::@@:@@ ; 7-7::@@:@@ ; 9-9::@@:@@"),
	Case(r".|\bc{1,2}?(?:ba*)?b{2}|(?:[a-c]*?)", "ẞKkÉcΣ", "0-3 ; 3-4 ; 4-5 ; 5-7 ; 7-8 ; 8-10 ; 10-10"),
	Case(r"(?P<n195665>([ab])??)", "b", "0-0::@@ ; 0-1:b:b ; 1-1::@@"),
	Case(r"[a-c]", "bb", "0-1 ; 1-2"),
	Case(r"(?:.)é|(?P<n578480>){1,2}?|a{1,2}?(b?[é-ü]*\D){0,2}", "ééKaσ_\nb", "0-4:@@:@@ ; 4-4::@@ ; 7-7::@@ ; 7-11:@@:_ ; 11-11::@@ ; 12-12::@@ ; 13-13::@@"),
	Case(r"b{1,2}($)|\d", " c1c\n", "2-3:@@"),
	Case(r"\w|", "1\n1_", "0-1 ; 1-1 ; 2-3 ; 3-4 ; 4-4"),
	Case(r".*", "_", "0-1 ; 1-1"),
	Case(r"\w+", "\na_", "1-3"),
	Case(r"b{2}(?:$)|.{1,2}?ß", "Kßsk S", "0-3"),
	Case(r"[ß-ſ]", "Kİẞé k٣ı", "3-5 ; 8-10 ; 14-16"),
	Case(r"(c*?|\Bb)", "éabaẞcSſ", "0-0: ; 2-2: ; 3-3: ; 3-4:b ; 4-4: ; 5-5: ; 8-8: ; 8-9:c ; 9-9: ; 10-10: ; 12-12:"),
	Case(r"(?:(?:b+b{1,2}aa|c\w)+[ab]\s.??|(c+?bb??)*)()((?:\s|bca.)*?.|(c|))", "c\n __1\n ", "0-1:@@::c:@@ ; 1-3:@@::\n :@@ ; 3-4:@@::_:@@ ; 4-5:@@::_:@@ ; 5-6:@@::1:@@ ; 6-8:@@::\n :@@ ; 8-8:@@:::"),
	Case(r"(?:[^a]|b|(?:)c){2}(|a\W()|)|\b", "\n_世_ ", "0-2::@@ ; 2-6::@@ ; 6-6:@@:@@"),
	Case(r"\b(^[^b-c]|\W{0,2}[^é]{2,}|(?P<n187718>[a-k]b|cc)a)*?|b{0,2}c{1,2}|b", "ß_é\n_ı", "0-0:@@:@@ ; 0-2:ß:@@ ; 5-5:@@:@@ ; 5-9:\n_ı:@@ ; 9-9:@@:@@"),
	Case(r"(?:.?)b", "b c\n", "0-1"),
	Case(r"[^b-c]{2}", "11", "0-2"),
	Case(r"(?P<n604090>[^é])", "É", "0-2:É"),
	Case(r"(?im)((?P<n305278>|^|){2,}b|(?:a+)()b*?a*)+?|((b|c.??.+.|a)\S)", "aaab_", "0-3:aaa:@@::@@:@@ ; 3-4:b::@@:@@:@@"),
	Case(r".c{0,2}(?:)$|(c.{1,2}?|c|(c{2,}a)c{2,}(?:b|bbc{1,2}?|)(?:c{0,2}a?c)).", "ςẞÉaσSİa", "13-14:@@:@@"),
	Case(r"(b?|\sc{2}a*?|b{1,2}(c{1,2}?.)c)(?P<n550099>c^|)", "b\n", "0-1:b:@@: ; 1-1::@@: ; 2-2::@@:"),
	Case(r"[É-Ü]+", "İ aKbΣ É", "11-13"),
	Case(r"|.|^", "世٣", "0-0 ; 0-3 ; 3-3 ; 3-5 ; 5-5"),
	Case(r"(?ms)\w", "_1b_", "0-1 ; 1-2 ; 2-3 ; 3-4"),
	Case(r"(b(?:ba|c{1,2}?cab|c){1,2}|\bb|)+?", "b1c", "0-1:b ; 1-1: ; 2-2: ; 3-3:"),
	Case(r"((c))?", "ac1c", "0-0:@@:@@ ; 1-2:c:c ; 2-2:@@:@@ ; 3-4:c:c ; 4-4:@@:@@"),
	Case(r"c.??", "c1a ß1", "0-1"),
	Case(r"[^a]", "1\n_1a_", "0-1 ; 1-2 ; 2-3 ; 3-4 ; 5-6"),
	Case(r"\S", "cbc", "0-1 ; 1-2 ; 2-3"),
	Case(r"(?:c.|é{2}é[世])??", "\nsbΣc_ſK", "0-0 ; 1-1 ; 2-2 ; 3-3 ; 5-5 ; 5-7 ; 7-7 ; 9-9 ; 10-10"),
	Case(r"\w{1,2}?", "ςẞ", "0-2 ; 2-5"),
	Case(r"(?:)(ß|(||b.b+)b{1,2}é?)??", "٣éẞßß", "0-0:@@:@@ ; 2-2:@@:@@ ; 4-4:@@:@@ ; 7-7:@@:@@ ; 7-9:ß:@@ ; 9-9:@@:@@ ; 9-11:ß:@@ ; 11-11:@@:@@"),
	Case(r"(?:|c*[_a]?a*?|b??(.|c*a|){1,2}?){0,2}|", "bẞß1", "0-0:@@ ; 0-1:b ; 1-1:@@ ; 1-4:ẞ ; 4-4:@@ ; 4-6:ß ; 6-6:@@ ; 6-7:1 ; 7-7:@@"),
	Case(r"(c|(?:ba){1,2}?|)??.|b(){0,2}", "cab bbb1", "0-1:@@:@@ ; 1-2:@@:@@ ; 2-3:@@:@@ ; 3-4:@@:@@ ; 4-5:@@:@@ ; 5-6:@@:@@ ; 6-7:@@:@@ ; 7-8:@@:@@"),
	Case(r"\W{1,2}", "a\n1", "1-2"),
	Case(r"(([a-c]|.{1,2}?|)*)", "sſKẞİ", "0-9:sſKẞİ: ; 9-9::"),
	Case(r"a.|[a-c]+(?:.(.[^a]+?|bb[^\s]|c)?(ab)|[ab]{0,2}(b){0,2})+b*", "b \n\n", "0-1:@@:@@:@@"),
	Case(r".{2,}|b", "É_", "0-3"),
	Case(r"b", "\ncbccb", "2-3 ; 5-6"),
	Case(r"b??", "b 11\n_", "0-0 ; 0-1 ; 1-1 ; 2-2 ; 3-3 ; 4-4 ; 5-5 ; 6-6"),
	Case(r"(?:[世]){0,2}.?|[^\s]{0,2}|.{0,2}", "σ٣", "0-2 ; 2-4 ; 4-4"),
	Case(r"[^a]+?", "b\nΣ\nſ", "0-1 ; 1-2 ; 2-4 ; 4-5 ; 5-7"),
	Case(r"世([ab]{2,})((a[ab]a+|a[é-ü]+\W|b)\D*é.*)|(.)*", "世a世b", "0-8:@@:@@:@@:b ; 8-8:@@:@@:@@:@@"),
	Case(r"(?m)ca*(?:)", "__\nc__\n ", "3-4"),
	Case(r"|(?P<n857262>[a-k](|))", "世éıéa", "0-0:@@:@@ ; 3-3:@@:@@ ; 5-5:@@:@@ ; 7-7:@@:@@ ; 9-9:@@:@@ ; 9-10:a: ; 10-10:@@:@@"),
	Case(r"[^a](b*|\ba\d|c){1,2}?|^", " \nab_", "0-1: ; 1-2: ; 3-4: ; 4-5:"),
	Case(r"b.(?:(bb{2}ac+){2,}a.*\s){0,2}", "\n\nba", "2-4:@@"),
	Case(r"(?ms)a*?", " c_ac1", "0-0 ; 1-1 ; 2-2 ; 3-3 ; 3-4 ; 4-4 ; 5-5 ; 6-6"),
	Case(r"[^a]{2}", "b bccß", "0-2 ; 2-4 ; 4-7"),
	Case(r"$|(?:a??)[^é]", " 1K", "0-1 ; 1-2 ; 2-5 ; 5-5"),
	Case(r"[^b-c]*?", "c s Sé", "0-0 ; 1-1 ; 1-2 ; 2-2 ; 2-3 ; 3-3 ; 3-4 ; 4-4 ; 4-5 ; 5-5 ; 5-7 ; 7-7"),
	Case(r"(\Dc|c)*c", "ſıİcẞaaa", "6-7:@@"),
	Case(r"(?s)c??(?P<n743732>)b", "1ab\n\n", "2-3:"),
	Case(r"[^a]*c*", "ςſ", "0-4 ; 4-4"),
	Case(r"c(?:b[É-Ü]\B(?:b)|(c??c.a|aaa{2}b*|)|c(?:ba?b|bb{1,2}){1,2}?){1,2}?|b+", "Σ世1ſc_", "8-9:"),
	Case(r"c", "c1ab", "0-1"),
	Case(r"(?:.)??", " ", "0-0 ; 0-1 ; 1-1"),
	Case(r"()[^\s]||.??.", "_ 1_bb", "0-1: ; 1-1:@@ ; 1-2:@@ ; 2-3: ; 3-4: ; 4-5: ; 5-6: ; 6-6:@@"),
	Case(r"|((ac?|a*c{1,2}?)a(b.+c+?)+.)*?c(?:)+?((?:a+\Da){2,})??", "_世cß\n\n", "0-0:@@:@@:@@:@@ ; 1-1:@@:@@:@@:@@ ; 4-4:@@:@@:@@:@@ ; 4-5:@@:@@:@@:@@ ; 5-5:@@:@@:@@:@@ ; 7-7:@@:@@:@@:@@ ; 8-8:@@:@@:@@:@@ ; 9-9:@@:@@:@@:@@"),
	Case(r"[\w]", "ßc a\n世", "0-2 ; 2-3 ; 4-5 ; 6-9"),
	Case(r"|.{0,2}(?:)", "k", "0-0 ; 0-1 ; 1-1"),
	Case(r"([^a]){1,2}|\d+?|cc{1,2}(?P<n747054>\sb{1,2})", "_\n\n", "0-2:\n:@@ ; 2-3:\n:@@"),
	Case(r"[^\s]", "kKaKs", "0-1 ; 1-2 ; 2-3 ; 3-4 ; 4-5"),
	Case(r"([ab]+|(?:))(?:.)|(?:[^a]|b\S*){1,2}?b{1,2}(?:a*?)*?$", "c", "0-1:"),
	Case(r".{0,2}.|(\D[\w]|$)|.a", "ab", "0-2:@@ ; 2-2:"),
	Case(r"|\D{2}a", "b cbac", "0-0 ; 1-1 ; 2-2 ; 2-5 ; 5-5 ; 6-6"),
	Case(r"c{1,2}", "cc", "0-2"),
	Case(r"(?s)a*b??b", "cb", "1-2"),
	Case(r"(?im)b+c+(?:(cc)a?|c)b{2}|ca\W.+", " a11ca\n_", "4-8:@@"),
	Case(r"(?:a)|(?P<n800931>.){0,2}[ab]()|\d{1,2}", "\nca", "1-3:c:"),
	Case(r"(?:).(?P<n611678>.?)+?", "cb\n_\n1ca", "0-2:b ; 3-4: ; 5-7:c ; 7-8:"),
	Case(r"((?:b??|)[\w])", "b", "0-1:b"),
	Case(r"$||\W((c+?)*?(?:|cab|.b??)b?|b)", "\n_ cba", "0-0:@@:@@ ; 0-1::@@ ; 1-1:@@:@@ ; 2-2:@@:@@ ; 2-3::@@ ; 3-3:@@:@@ ; 4-4:@@:@@ ; 5-5:@@:@@ ; 6-6:@@:@@"),
	Case(r"()((?P<n203933>[ab]{1,2}a*?)|(?:)+?(?:)*c|){1,2}?", "ba__", "0-2::ba:ba ; 2-2:::@@ ; 3-3:::@@ ; 4-4:::@@"),
	Case(r"(?s)(?P<n327544>|ca+)?b|b*?", "11 bb\n", "0-0:@@ ; 1-1:@@ ; 2-2:@@ ; 3-4: ; 4-5: ; 5-5:@@ ; 6-6:@@"),
	Case(r".(?:(?:aa??a??|c|\D*?[ab]*)|\S{2,}a|)*?", "11cb", "0-1 ; 1-2 ; 2-3 ; 3-4"),
	Case(r"\wa?", "\nb", "1-2"),
	Case(r".a(){0,2}\B", "\n1ac\nb", "1-3:"),
	Case(r"(b?.(b+[a-c]ac)+?|.{1,2}){0,2}[^a]", "1  ", "0-3:1 :@@"),
	Case(r"(c(b?b)c)??|[^b-c]|c(a*)*?(.|b.+?b{2,})", "_cccc b1", "0-0:@@:@@:@@:@@ ; 0-1:@@:@@:@@:@@ ; 1-1:@@:@@:@@:@@ ; 1-3:@@:@@:@@:c ; 3-3:@@:@@:@@:@@ ; 3-5:@@:@@:@@:c ; 5-5:@@:@@:@@:@@ ; 5-6:@@:@@:@@:@@ ; 6-6:@@:@@:@@:@@ ; 7-7:@@:@@:@@:@@ ; 7-8:@@:@@:@@:@@ ; 8-8:@@:@@:@@:@@"),
	Case(r".{1,2}?", "c_c ", "0-1 ; 1-2 ; 2-3 ; 3-4"),
	Case(r"$(|(?:\Sb)?|(cc*?)?){2,}|[^\s]|", "c\n1", "0-1:@@:@@ ; 1-1:@@:@@ ; 2-3:@@:@@ ; 3-3::@@"),
	Case(r"[\w]*?|(?P<n365059>(c)+?\S*?(a){2}b)", "b1_a\n", "0-0:@@:@@:@@ ; 0-1:@@:@@:@@ ; 1-1:@@:@@:@@ ; 1-2:@@:@@:@@ ; 2-2:@@:@@:@@ ; 2-3:@@:@@:@@ ; 3-3:@@:@@:@@ ; 3-4:@@:@@:@@ ; 4-4:@@:@@:@@ ; 5-5:@@:@@:@@"),
	Case(r"(?im)[^b-c]a", "b\nc\na_", "3-5"),
	Case(r"\S+?||((|c{2}b)\w*)(?:\w){1,2}?", "c1", "0-1:@@:@@ ; 1-2:@@:@@ ; 2-2:@@:@@"),
	Case(r"()*\w+|[\w]|ca{2,}", "c1b", "0-3:"),
	Case(r"((a)(?:.[^a]*b)){2,}ac|\W(?P<n527977>\S{0,2}[ab]|(a{0,2}\b[ab])|)+?\b", "c\nc\naa\nb", "1-2:@@:@@::@@ ; 3-6:@@:@@:aa:@@ ; 6-8:@@:@@:b:@@"),
	Case(r"[_a]{1,2}(?:\D)*", "ab", "0-2"),
	Case(r"|b*?", "abca", "0-0 ; 1-1 ; 1-2 ; 2-2 ; 3-3 ; 4-4"),
	Case(r"(?:(|c^))[_a]*", "ba", "0-0: ; 1-2: ; 2-2:"),
	Case(r"a[^\s](?:[^b-c]??\db*)a*?|c*a|(|.{1,2}?(?:\d|\s\ba){1,2}){1,2}", "\naca_a\n ", "0-0: ; 1-2:@@ ; 2-4:@@ ; 4-4: ; 5-6:@@ ; 6-6: ; 7-7: ; 8-8:"),
	Case(r"(?im).", "\n1 ba", "1-2 ; 2-3 ; 3-4 ; 4-5"),
	Case(r".|a|b{0,2}a(?:)", " _c  ", "0-1 ; 1-2 ; 2-3 ; 3-4 ; 4-5"),
	Case(r"(?:c*(?:\bbc|bc|.+){2}(?:\sb{1,2}?b{1,2}c))b|.", "ac aaa", "0-1 ; 1-2 ; 2-3 ; 3-4 ; 4-5 ; 5-6"),
	Case(r"a??.|(?:[^b-c]{2,}.)\b[ab]a", "_ ", "0-1 ; 1-2")

]

fn matchesOf(pattern str, text str) str:
	re = compiled(pattern)
	parts = []
	for m in re.findAll(text):
		fields = ["{m.start}-{m.end}"]
		for g in 1..m.cuts.len / 2:
			fields.push((m.group(g) ?? "@@").copy())
		parts.push(fields.join(":"))
	parts.join(" ; ")

test "random patterns give the matches Python's re gives":
	for c in cases:
		expect matchesOf(c.pattern, c.text) == c.matches
