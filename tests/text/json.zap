# The standard library's JSON reader: objects, arrays, numbers, strings with escapes, bools and
# null, read into a flat list of entries, a json.Node a place in it.

import json

test "objects, arrays and numbers":
	doc = json.parse("\{ \"name\": \"Ana\", \"age\": 30, \"tags\": [1, 2.5, -3e2], \"ok\": true, \"none\": null }") ?? fail
	expect doc.textOf(doc.root, "name") == "Ana"
	expect (doc.number(doc.root, "age") ?? 0.0) == 30.0
	tags = doc.numbers(doc.root, "tags") ?? []
	expect tags == [1.0, 2.5, -300.0]
	expect doc[doc.get(doc.root, "ok") ?? doc.root].number == 1.0
	nothing = doc.get(doc.root, "none") ?? doc.root
	expect doc[nothing].kind == .Null
	expect doc.get(doc.root, "missing") == none

test "nested containers and escapes":
	doc = json.parse("[\{\"a\": [[], \{}]}, \"x\\\"y\\n\\u0041\"]") ?? fail
	expect doc.count(doc.root) == 2
	first = doc.at(doc.root, 0)
	a = doc.get(first, "a") ?? doc.root
	expect doc.count(a) == 2
	inner = doc.at(a, 1)
	expect doc[inner].kind == .Object
	escaped = doc.at(doc.root, 1)
	expect doc[escaped].text == "x\"y\nA"

test "a \\u escape past ASCII and a surrogate pair are their UTF-8":
	doc = json.parse("[\"caf\\u00e9\", \"\\ud83d\\ude00\"]") ?? fail
	cafe = doc.at(doc.root, 0)
	expect doc[cafe].text == "café"
	smile = doc.at(doc.root, 1)
	expect doc[smile].text == "😀"

test "a text that is not JSON gives why" for text in [
	"",
	"[1, 2",
	"\{\"a\" 1}",
	"[1] 2",
	"tru",
	"[\"\\u12\"]",
	"\{\"a\": [\{}, ]}"
]:
	match json.parse(text):
		error: expect error.startsWith("JSON: ")
		_: expect false

test "a document nested 10,000 deep parses without stopping":
	deep = "{"[".repeat(10_000)}{"]".repeat(10_000)}"
	doc = json.parse(deep) ?? fail
	expect doc.count(doc.root) == 1

test "a document written back as JSON, compact or indented":
	text = "\{\"name\": \"A \\\"b\\\"\n\", \"n\": [1, 2.5, -0, 1e+21], \"o\": \{}, \"e\": [], \"t\": true, \"z\": null}"
	doc = json.parse(text) ?? fail
	print(doc.text())
	print(doc.text(indent = 2))
	expect (json.parse(doc.text(indent = 4)) ?? fail).text() == doc.text()
	prints r"""
		{"name":"A \"b\"\n","n":[1,2.5,-0,1e+21],"o":{},"e":[],"t":true,"z":null}
		{
		  "name": "A \"b\"\n",
		  "n": [
		    1,
		    2.5,
		    -0,
		    1e+21
		  ],
		  "o": {},
		  "e": [],
		  "t": true,
		  "z": null
		}
		"""

type Reading:
	label str
	values f64[]
	nested {str: i64}

test "a document is written as a type's toJson writes it":
	value = Reading(
		label = "tab\t\0é\"",
		values = [1.0, 0.1 + 0.2, 1e300, 50.0, -0.0],
		nested = {"a": 1}
	)
	expect (json.parse(value.toJson()) ?? fail).text() == value.toJson()

type Tricky:
	text str
	items str[]
	empty str[]

test "toJson with an indent spreads out what the document does, brackets in strings left alone":
	v = Tricky(text = "a,b:(c)[d]\"e\n", items = ["x,y", "]", "\"]", r"{"], empty = [])
	doc = json.parse(v.toJson()) ?? fail
	expect v.toJson(3) == doc.text(indent = 3)
	expect v.toJson(0) == v.toJson()
	expect (json.parse(v.toJson(1)) ?? fail).text() == v.toJson()
