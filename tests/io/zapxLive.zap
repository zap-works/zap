# std/zapx's diff: the patches between two renders, checked by applying them as the client does,
# and a live page served over loopback: its page, a click in, the patch out.

import net
import zapx

# the patches between two trees as JSON, and whether they turn the first into the second
fn checked(old zapx.Node, new zapx.Node) str:
	before = old.flat()
	after = new.flat()
	patches = before.diff(after)
	same = zapx.fragment(before.patched(patches)).render() == zapx.fragment(after).render()
	"{patches.encoded()}{"" if same else " WRONG"}"

fn items(keys str[]) zapx.Node:
	zapx.element("ul", [], keys.map(zapx.element("li", [zapx.attr("key", it)], [zapx.text(it)])))

test "a list's keyed items added, removed and moved: runs of the old ones and the new ones' HTML":
	print(checked(items(["a", "b", "c"]), items(["a", "b", "c", "d"])))
	print(checked(items(["a", "b", "c", "d"]), items(["x", "a", "c", "d"])))
	print(checked(items(["a", "b", "c"]), items(["c", "b", "a"])))
	print(checked(items(["a", "b", "c"]), items(["a", "b", "c"])))
	prints """
		[["o",[0],[[0,2],"<li key=\\"d\\">d</li>"]]]
		[["o",[0],["<li key=\\"x\\">x</li>",0,[2,3]]]]
		[["o",[0],[2,1,0]]]
		[]
		"""

test "texts and attributes patched in place, fragments and adjacent texts as the DOM holds them":
	old = zapx.element(
		"p",
		[zapx.attr("class", "a"), zapx.flag("hidden", true), zapx.attr("title", "t")],
		[zapx.text("n = "), zapx.fragment([zapx.text("1"), zapx.empty()]), zapx.element("b", [], [zapx.text("x")])]
	)
	new = zapx.element(
		"p",
		[zapx.attr("class", "b"), zapx.flag("hidden", false), zapx.attr("id", "i")],
		[zapx.text("n = 2"), zapx.element("b", [], [zapx.text("x")]), zapx.text("!")]
	)
	print(checked(old, new))
	print(zapx.fragment([zapx.text("a"), zapx.fragment([zapx.text(""), zapx.text("b")]), zapx.raw("")]).flat())
	prints """
		[["a",[0],"class","b"],["a",[0],"id","i"],["r",[0],"hidden"],["r",[0],"title"],["o",[0],[[0,1],"!"]],["t",[0,0],"n = 2"]]
		[Text("ab")]
		"""

test "unkeyed children in order, a changed tag written anew, Raw HTML compared as HTML":
	old = zapx.element("div", [], [zapx.element("p", [], [zapx.text("1")]), zapx.element("p", [], [zapx.text("2")])])
	new = zapx.element("div", [], [zapx.element("p", [], [zapx.text("1")]), zapx.element("h2", [], [zapx.text("2")])])
	print(checked(old, new))
	print(checked(zapx.element("div", [], [zapx.raw("<i>a</i>")]), zapx.element("div", [], [zapx.raw("<i>b</i>")])))
	print(checked(zapx.element("div", [], [zapx.raw("<i>a</i>")]), zapx.element("div", [], [zapx.raw("<i>a</i>")])))
	print(checked(zapx.text("a"), zapx.element("br", [], [])))
	prints """
		[["o",[0],[0,"<h2>2</h2>"]]]
		[["h",[0],"<i>b</i>"]]
		[]
		[["o",[],["<br>"]]]
		"""

fn choose(mut rng Random, words str[]) str:
	words[rng.nextInt(0, words.len)].copy()

# a small random tree: lists of keyed or unkeyed items, texts, attributes, fragments
fn randomNode(mut rng Random, depth i64) zapx.Node:
	pick = rng.nextInt(0, 6 if depth > 0 else 2)
	if pick == 0: return zapx.text(rng.choose(["a", "b", ""]))
	if pick == 1: return zapx.fragment([zapx.text("x"), zapx.text(rng.choose(["y", ""]))])
	kids = []
	loop rng.nextInt(0, 5):
		kids.push(randomNode(rng, depth - 1))
	attrs = []
	if rng.nextInt(0, 2) == 0: attrs.push(zapx.attr("key", rng.choose(["k1", "k2", "k3"])))
	if rng.nextInt(0, 2) == 0: attrs.push(zapx.attr("class", rng.choose(["c", "d"])))
	zapx.element(rng.choose(["div", "p", "li"]), attrs, kids)

test "random trees: the patches always turn one into the other":
	rng = Random(7)
	wrong = 0
	loop 500:
		old = randomNode(rng, 3)
		new = randomNode(rng, 3)
		if checked(old, new).endsWith(" WRONG"): wrong += 1
	print(wrong)
	prints "0"
