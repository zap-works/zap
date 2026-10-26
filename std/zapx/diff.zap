# The diff of two renders: the patches that turn the browser's DOM of one into the other's, which a
# live page (live.zap) sends and its client (client.zap) applies. Both are first laid out as the
# browser holds them (`flat`). Children are matched by their `key` attribute when they have one
# (React's reconciliation) and the others in their order; a matched pair (same tag, or two texts)
# is patched in place, the rest is written anew. A parent holding Raw HTML is compared as its HTML:
# its DOM is not known node by node.

# one entry of a parent's new children: a run of its old ones (from..to, both in) or a new node
pub type Slot:
	Kept(from i64, to i64)
	Added(node Node)

# A change of the DOM. A path is the children's indices from a container holding the root nodes
# (the first root is [0]).
pub type Patch:
	Order(path i64[], slots Slot[])   # the node's children: the old ones kept, in their new order
	SetText(path i64[], text str)
	SetAttr(path i64[], name str, value str)
	RemoveAttr(path i64[], name str)
	Inner(path i64[], kids Node[])   # the node's children written anew (a parent holding Raw)

# The nodes as the browser's DOM holds them: fragments opened, adjacent texts joined, empty texts
# and empty Raw HTML dropped.
pub fn flat(node Node) Node[]:
	out Node[] = []
	out.flatten(node)
	out

fn flatten(mut out Node[], node Node):
	match node:
		Element(tag, attrs, kids):
			inner Node[] = []
			for k in kids:
				inner.flatten(k)
			out.push(.Element(tag.copy(), attrs.copy(), inner))
		Text(t):
			if t.isEmpty: return
			joined = ""
			if not out.isEmpty and out[len - 1] is Text(before):
				joined = "{before}{t}"
			if joined.isEmpty:
				out.push(.Text(t.copy()))
			else:
				out[len - 1] = .Text(joined)
		Raw(html):
			if not html.isEmpty: out.push(.Raw(html.copy()))
		Fragment(kids):
			for k in kids:
				out.flatten(k)

# The patches that turn the DOM of `old` into that of `new`, both as `flat` lays them out.
pub fn diff(old Node[], new Node[]) Patch[]:
	out Patch[] = []
	out.diffKids([], old, new)
	out

fn diffKids(mut out Patch[], path i64[], old Node[], new Node[]):
	if old.any(.isRaw()) or new.any(.isRaw()):
		if fragment(old.copy()).render() != fragment(new.copy()).render():
			out.push(.Inner(path.copy(), new.copy()))
		return
	from = matches(old, new)
	if not inPlace(from, old.len):
		out.push(.Order(path.copy(), slots(from, new)))
	for j, i in from:
		if i < 0: continue
		at = path.copy()
		at.push(j)
		out.diffNode(at, old[i], new[j])

# whether every old child stays where it was and none is added or dropped
fn inPlace(from i64[], count i64):
	if from.len != count: return false
	for j, i in from:
		if i != j: return false
	true

fn isRaw(node Node):
	match node:
		Raw: true
		_: false

# The old child each new one is matched with, -1 for none: by key among those with one, each old
# one taken once, the others in order; a pair only of the same tag, or of two texts.
fn matches(old Node[], new Node[]) i64[]:
	keyed {str: i64} = {}
	unkeyed = []
	for i, n in old:
		k = keyOf(n)
		if k.isEmpty:
			unkeyed.push(i)
		elif k not in keyed:
			keyed[k] = i
	from = []
	next = 0
	for n in new:
		k = keyOf(n)
		i = -1
		if not k.isEmpty:
			if keyed.remove(k) is at: i = at
		elif next < unkeyed.len:
			i = unkeyed[next]
			next += 1
		from.push(i if i >= 0 and sameKind(old[i], n) else -1)
	from

# an element's `key` attribute, "" for none
fn keyOf(node Node) str:
	if node is Element(_, attrs, _):
		return attrValue(attrs, "key") ?? ""
	""

fn sameKind(a Node, b Node):
	kind = kindOf(a)
	not kind.isEmpty and kind == kindOf(b)

# an element's tag, "#text" for a text (the DOM's nodeName), "" for others
fn kindOf(node Node) str:
	match node:
		Element(tag, _, _): tag.copy()
		Text: "#text"
		_: ""

# the new children as runs of old ones and new nodes
fn slots(from i64[], new Node[]) Slot[]:
	out Slot[] = []
	first = -1   # the run of old ones under way, first..last; -1 for none
	last = -1
	for j, i in from:
		if first >= 0 and i == last + 1:
			last = i
			continue
		if first >= 0: out.push(.Kept(first, last))
		first = i
		last = i
		if i < 0: out.push(.Added(new[j].copy()))
	if first >= 0: out.push(.Kept(first, last))
	out

fn diffNode(mut out Patch[], path i64[], old Node, new Node):
	match new:
		Element(_, attrs, kids):
			if old is Element(_, before, oldKids):
				out.diffAttrs(path, before, attrs)
				out.diffKids(path, oldKids, kids)
		Text(t):
			if old is Text(before) and before != t:
				out.push(.SetText(path.copy(), t.copy()))
		_: pass

fn diffAttrs(mut out Patch[], path i64[], old Attr[], new Attr[]):
	for a in new:
		if not a.shown: continue
		value = "" if a.bare else a.value.copy()
		if attrValue(old, a.name) is before and before == value: continue
		out.push(.SetAttr(path.copy(), a.name.copy(), value))
	for a in old:
		if a.shown and attrValue(new, a.name) == none:
			out.push(.RemoveAttr(path.copy(), a.name.copy()))

# the value the DOM holds for the attribute, as the first one written of that name ("" for a bare
# one); none when it is not written
fn attrValue(attrs Attr[], name str) str?:
	for a in attrs:
		if a.shown and a.name == name: return "" if a.bare else a.value.copy()
	none

# The patches as the client reads them: a JSON array of [op, path, values...], the ops "o" (Order:
# a slot an old index, a run [from, to], or a new node's HTML), "t", "a", "r" and "h" (Inner's HTML).
pub fn encoded(patches Patch[]) str:
	out = []
	out.push('[')
	for k, p in patches:
		if k > 0: out.push(',')
		out.writePatch(p)
	out.push(']')
	str(move out)

fn writePatch(mut out u8[], patch Patch):
	match patch:
		Order(path, slots):
			out.opHead("o", path)
			out.push('[')
			for k, s in slots:
				if k > 0: out.push(',')
				match s:
					Kept(from, to):
						out.extend(("{from}" if from == to else "[{from},{to}]").bytes())
					Added(node): out.extend(jsonQuote(node.render()).bytes())
			out.push(']')
		SetText(path, text):
			out.opHead("t", path)
			out.extend(jsonQuote(text).bytes())
		SetAttr(path, name, value):
			out.opHead("a", path)
			out.extend("{jsonQuote(name)},{jsonQuote(value)}".bytes())
		RemoveAttr(path, name):
			out.opHead("r", path)
			out.extend(jsonQuote(name).bytes())
		Inner(path, kids):
			out.opHead("h", path)
			out.extend(jsonQuote(fragment(kids.copy()).render()).bytes())
	out.push(']')

fn opHead(mut out u8[], op str, path i64[]):
	out.extend("[\"{op}\",[{path.map("{it}").join(",")}],".bytes())

# The nodes with the patches applied in their order, as the client applies them to the DOM: what
# checks the diff.
pub fn patched(nodes Node[], patches Patch[]) Node[]:
	out = nodes.copy()
	for p in patches:
		out = applied(out, p.path(), 0, p)
	out

fn ofKids(patch Patch):
	match patch:
		Order, Inner: true
		_: false

fn path(patch Patch) i64[]:
	match patch:
		Order(path, _), SetText(path, _), SetAttr(path, _, _), RemoveAttr(path, _), Inner(path, _):
			path.copy()

# the children with the patch applied at path[at..] below them
fn applied(kids Node[], path i64[], at i64, patch Patch) Node[]:
	if at == path.len:
		match patch:
			Order(_, slots):
				out = []
				for s in slots:
					match s:
						Kept(from, to):
							for i in from..=to:
								out.push(kids[i].copy())
						Added(node): out.push(node.copy())
				return out
			Inner(_, inner): return inner.copy()
			_: return kids.copy()
	out = kids.copy()
	out[path[at]] = patchedNode(kids[path[at]], path, at + 1, patch)
	out

fn patchedNode(node Node, path i64[], at i64, patch Patch) Node:
	match node:
		Element(tag, attrs, kids):
			if at < path.len or patch.ofKids():
				return .Element(tag.copy(), attrs.copy(), applied(kids, path, at, patch))
			removed = ""
			if patch is RemoveAttr(_, name): removed = name.copy()
			out = attrs.filter(.name != removed)
			if patch is SetAttr(_, name, value):
				out = out.filter(.name != name)
				out.push(attr(name, value))
			.Element(tag.copy(), out, kids.copy())
		Text:
			if patch is SetText(_, t): return .Text(t.copy())
			node.copy()
		_: node.copy()
