# Word edges and captured groups, with the results Python's re gives (the word bytes are ASCII).

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

test "a word's edge is told by the bytes at both sides, as the automata read them":
	expect spansOf(r"x\b|y", "xy x") == "1-2 3-4"
	expect spansOf(r"(?m)^\bab$", "ab\ncd\nab") == "0-2 6-8"
	expect spansOf(r"(?m)\b$", "ab\ncd") == "2-2 5-5"
	expect spansOf(r"\b(?:a|ab)\b", "ab a") == "0-2 3-4"
	expect spansOf(r"\bé", "é") == ""
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
	optional = (compiled("(?P<a>x)|(?P<b>y)").find("y") ?? fail("none"))
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
	expect compiled(r"fs\.(readFile|readBytes)\(").replace("a fs.readFile(x)", r"fs.load(") == "a fs.load(x)"
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
