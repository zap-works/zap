# A card of the board (board/README.md): one step of the plan in a file
# board/<order>-<area>/<n>-<slug>.md, its front matter between two `---` lines, then `# title`,
# then the step's text, whose `- [ ]` and `- [x]` items are its progress.

import fs

# what a card's front matter may hold
pub cardKeys = ["needs", "size", "check", "blocked", "branch"]

pub type Card:
	id str   # <area>-<n>
	area str
	areaOrder i64
	n i64
	path str   # from the checkout's root
	title str
	body str   # the text after the title
	needs str[]
	size str
	check str   # the measure that says it is done
	blocked str   # why it waits, "" when it does not
	branch str   # the branch that took it, written by `take` in that branch's copy
	ticked i64
	items i64

# hours of an agent's work a size stands for, 0 for an unknown size
pub fn sizeHours(size str) f64:
	if size == "S": return 1.0
	if size == "M": return 4.0
	if size == "L": return 12.0
	if size == "XL": return 30.0
	0.0

# a name that starts with its place in an order: "12-skyrim"
type Numbered:
	order i64
	name str

fn numbered(name str) Numbered?:
	dash = try name.indexOf("-")
	order = try i64.parse(name[..dash])
	if dash + 1 >= name.len: return none
	Numbered(order, name = name[dash + 1..].copy())

# "board/2-compiler/9-names.md" -> "compiler-9"; "" for a path that names no card
pub fn idOfPath(path str) str:
	parts = path.split("/")
	if parts.len != 3 or parts[0] != "board" or not parts[2].endsWith(".md"): return ""
	area = numbered(parts[1]) ?? return ""
	file = numbered(fs.stem(parts[2])) ?? return ""
	"{area.name}-{file.order}"

# "[a, b]" or "a, b" -> ["a", "b"]
fn listValue(value str):
	inner = value.trimmed("[]").trimmed()
	if inner.isEmpty: return []
	inner.split(",").map(.trimmed().copy())

# the card in the file's text (path from the checkout's root), or what is wrong with it
pub fn parseCard(path str, text str) Card ? str:
	dir = numbered(fs.fileName(fs.dirOf(path))) ?? return "{path}: its dir is not <order>-<area>"
	file = numbered(fs.stem(path)) ?? return "{path}: its name is not <n>-<slug>.md"
	lines = text.lines()
	if lines.isEmpty or lines[0] != "---": return "{path}: no front matter (a first line ---)"
	end = 1
	while end < lines.len and lines[end] != "---":
		end += 1
	if end == lines.len: return "{path}: the front matter has no closing ---"
	card = Card(
		id = "{dir.name}-{file.order}",
		area = dir.name.copy(),
		areaOrder = dir.order,
		n = file.order,
		path = path.copy(),
		title = "",
		body = "",
		needs = [],
		size = "",
		check = "",
		blocked = "",
		branch = "",
		ticked = 0,
		items = 0
	)
	for i in 1..end:
		line = lines[i]
		colon = line.indexOf(":") ?? return "{path}: '{line}' is not key: value"
		key = line[..colon].trimmed().copy()
		value = line[colon + 1..].trimmed().copy()
		if key == "needs": card.needs = listValue(value)
		elif key == "size": card.size = value
		elif key == "check": card.check = value
		elif key == "blocked": card.blocked = value
		elif key == "branch": card.branch = value
		else: return "{path}: unknown key '{key}' (known: {cardKeys.join(", ")})"
	at = end + 1
	while at < lines.len and lines[at].trimmed().isEmpty:
		at += 1
	if at == lines.len or not lines[at].startsWith("# "):
		return "{path}: no `# title` after the front matter"
	card.title = lines[at][2..].trimmed().copy()
	body = lines[at + 1..].join("\n").trimmed().copy()
	for line in body.lines():
		item = line.trimmedStart()
		if item.startsWith("- [x]") or item.startsWith("- [X]"):
			card.ticked += 1
			card.items += 1
		elif item.startsWith("- [ ]"):
			card.items += 1
	card.body = body
	if sizeHours(card.size) == 0.0: return "{path}: size '{card.size}' is not S, M, L or XL"
	card

# the cards under the checkout's board/ dir, ordered by area then number, and what is wrong with
# the files that are no card (an area's README.md and the board's are none)
pub fn loadCards(root str) (Card[], str[]):
	cards = []
	problems = []
	skip = fs.normalize(root).len + 1
	for full in fs.walk("{root}/board", "*.md"):
		whole = fs.normalize(full)
		path = whole[skip..].copy()
		if fs.fileName(path) == "README.md" or path.split("/").len != 3: continue
		text = fs.readFile(full) ?? continue
		match parseCard(path, text):
			card: cards.push(card)
			error: problems.push(error)
	(cards.sortedBy((.areaOrder, .n)), problems)

# an area of the board: its dir's README.md opens with `# title` and a paragraph saying what it
# holds
pub type Area:
	name str
	order i64
	title str
	about str

# the areas under root/board, in their dirs' order
pub fn loadAreas(root str) Area[]:
	out = []
	for dir in fs.list("{root}/board") ?? []:
		numberedDir = numbered(dir) ?? continue
		lines = (fs.readFile("{root}/board/{dir}/README.md") ?? "").lines()
		title = lines[0][2..].copy() if not lines.isEmpty and lines[0].startsWith("# ")
			else numberedDir.name.copy()
		about = []
		for line in lines[1..]:
			if line.trimmed().isEmpty and not about.isEmpty: break
			if not line.trimmed().isEmpty: about.push(line.trimmed().copy())
		out.push(
			Area(
				name = numberedDir.name.copy(),
				order = numberedDir.order,
				title,
				about = about.join(" ")
			)
		)
	out.sortedBy(.order)

# a card with its front matter's line `key: value` set (added before the closing --- when absent)
pub fn withKey(text str, key str, value str) str:
	lines = text.lines()
	out = []
	set = false
	for i, line in lines:
		inFront = i > 0 and lines[..i].count("---") == 1
		if inFront and line.startsWith("{key}:"):
			out.push("{key}: {value}")
			set = true
		elif inFront and line == "---" and not set:
			out.push("{key}: {value}")
			out.push("---")
			set = true
		else:
			out.push(line.copy())
	"{out.join("\n")}\n"

test "a card is read from its front matter, title and checklist":
	text = """
		---
		needs: [compiler-5, language-1]
		size: M
		check: zap test --only size
		---
		# Memory per line

		The text.
		- [x] one
		- [ ] two
		"""
	card = parseCard("board/2-compiler/1-memory-per-line.md", text) ?? fail
	print("{card.id} {card.areaOrder} {card.title} {card.needs.join("+")} {card.size} {card.ticked}/{card.items}")
	prints "compiler-1 2 Memory per line compiler-5+language-1 M 1/2"

test "what is wrong with a card is told":
	for text in [
		"# no front\n",
		"---\nsize: Q\n---\n# T\n",
		"---\nwho: me\n---\n# T\n",
		"---\nsize: S\n---\nno title\n"
	]:
		match parseCard("board/1-language/1-x.md", text):
			card: print("read {card.id}")
			error: print(error)
	prints """
		board/1-language/1-x.md: no front matter (a first line ---)
		board/1-language/1-x.md: size 'Q' is not S, M, L or XL
		board/1-language/1-x.md: unknown key 'who' (known: needs, size, check, blocked, branch)
		board/1-language/1-x.md: no `# title` after the front matter
		"""

test "a key is set in the front matter":
	print(withKey("---\nsize: S\n---\n# T\n", "branch", "b1").replace("\n", "|"))
	print(withKey("---\nbranch: a\n---\n# T\n", "branch", "b2").replace("\n", "|"))
	prints """
		---|size: S|branch: b1|---|# T|
		---|branch: b2|---|# T|
		"""

test "a card's path names its id":
	print("{idOfPath("board/2-compiler/9-names.md")} [{idOfPath("board/README.md")}] [{idOfPath("tools/x.md")}]")
	prints "compiler-9 [] []"
