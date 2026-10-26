# HTML as values: what the markup of a .zapx file builds (spec 7.11), and `render`, which writes it.
# A module of the standard library: a .zapx file has its names without an import (`Node`), a .zap
# file writes `import zapx` and builds the nodes with the functions below.

# an element's attribute: `class="x"`, or one written bare (`disabled`); one left out (a false
# bool's) is not written
pub type Attr:
	name str
	value str = ""
	bare bool = false
	shown bool = true

# a piece of a page: an element with its attributes and children, text (escaped when written),
# HTML written as it is, or a run of nodes with nothing around them
pub type Node:
	Element(tag str, attrs Attr[], kids Node[])
	Text(text str)
	Raw(html str)
	Fragment(kids Node[])

# the elements that never hold children: written without a closing tag (`<br>`)
pub voidElements = [
	"area",
	"base",
	"br",
	"col",
	"embed",
	"hr",
	"img",
	"input",
	"link",
	"meta",
	"source",
	"track",
	"wbr"
]

pub fn isVoid(tag str) bool:
	tag in voidElements

# the elements whose text HTML reads as it is, never as markup: written unescaped
rawTextElements = ["script", "style"]

pub fn element(move tag str, move attrs Attr[], move kids Node[]) Node:
	.Element(tag, attrs, kids)

pub fn text(s str) Node:
	.Text(s.copy())

# HTML written into the page as it is, not escaped
pub fn raw(html str) Node:
	.Raw(html.copy())

pub fn fragment(move kids Node[]) Node:
	.Fragment(kids)

# the node of nothing: what a markup `if` without `else` gives when its condition fails
pub fn empty() Node:
	.Fragment([])

pub fn attr(name str, value str) Attr:
	Attr(name.copy(), value.copy())

# a bool attribute: written bare when on, left out when off
pub fn flag(name str, on bool) Attr:
	Attr(name.copy(), bare = true, shown = on)

# The node as HTML: text and attribute values escaped (but a script's or a style's text), void
# elements without a closing tag, and a page (an `html` element at the root) after its doctype
pub fn render(node Node) str:
	out = []
	if node.isPage():
		out.extend("<!DOCTYPE html>".bytes())
	out.write(node)
	str(move out)

# whether the node is a page: an `html` element
fn isPage(node Node):
	match node:
		Element(tag, _, _): tag == "html"
		_: false

fn write(mut out u8[], node Node):
	match node:
		Element(tag, attrs, kids):
			out.push('<')
			out.extend(tag.bytes())
			for a in attrs:
				out.writeAttr(a)
			out.push('>')
			if isVoid(tag): return
			for k in kids:
				if k is Text(t) and tag in rawTextElements:
					out.extend(t.bytes())
				else:
					out.write(k)
			out.extend("</{tag}>".bytes())
		Text(t): out.escaped(t, false)
		Raw(html): out.extend(html.bytes())
		Fragment(kids):
			for k in kids:
				out.write(k)

fn writeAttr(mut out u8[], a Attr):
	if not a.shown: return
	out.push(' ')
	out.extend(a.name.bytes())
	if a.bare: return
	out.extend("=\"".bytes())
	out.escaped(a.value, true)
	out.push('"')

# the text with what HTML reads as markup escaped: `&`, `<` and `>`, and in an attribute's value `"`
fn escaped(mut out u8[], t str, quoted bool):
	for b in t.bytes():
		if b == '&':
			out.extend("&amp;".bytes())
		elif b == '<':
			out.extend("&lt;".bytes())
		elif b == '>':
			out.extend("&gt;".bytes())
		elif b == '"' and quoted:
			out.extend("&quot;".bytes())
		else:
			out.push(b)

test "a page renders with its doctype, its text and attributes escaped":
	page = element(
		"html",
		[],
		[
			element(
				"body",
				[attr("class", "a\"b"), flag("hidden", true), flag("open", false)],
				[
					text("1 < 2 & 3"),
					element("br", [], []),
					raw("<i>x</i>"),
					fragment([text("y")]),
					element("script", [], [text("a < b && c")])
				]
			)
		]
	)
	print(page.render())
	expect fragment([text("<p>"), empty()]).render() == "&lt;p&gt;"
	prints """
		<!DOCTYPE html><html><body class="a&quot;b" hidden>1 &lt; 2 &amp; 3<br><i>x</i>y<script>a < b && c</script></body></html>
		"""
