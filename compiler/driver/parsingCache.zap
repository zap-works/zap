# A cache of the load (lexing and parsing a file, a tenth of a build and a third of a small
# program's): each source file's nodes as parsed, kept in build/cache/parse/ under its path with
# the hash of its name and text and the compiler's key (compilerKey). A file whose text is
# unchanged is read back instead of parsed; its nodes are numbered from its first, so they go
# wherever the arena ends, and the program is the same node for node (spec/commands.zap); an arm's
# note of the first arm of its patterns (ival) is a node too. What the parser notes besides the
# nodes comes back too: the calls of `shader` and `compute` (gpu.zap) and the bodies kept of
# functions with number parameters (regArrays.zap). A file that embeds another (`embed`) is always
# parsed: its nodes hold that file's bytes.
#
# Files are parsed apart (parseApart) on every processor and appended to the program's arena in
# their order (appendParsed), so the program is the same as one parsed a file at a time.

import fs

parseCacheMagic = "ZPRC"
parseCacheVersion = 6

# where build/cache/parse/ is known made
mut parseCacheReady = false

# while set, the entries a parse makes wait in parseWrites until writeParsed (a run writes them
# once its program started)
mut parseWritesHeld = false
mut parseWrites (str, str)[] = []

# A file to parse, all of it read on the thread that asks (a job reads no module variable that can
# change): its name, its text, where its parsed form is kept (none for a file that embeds another
# and with ZAP_RUN=nocache), the compiler's key, and whether a form just parsed is written at once
# (a run holds its writes until its program started, parseWritesHeld).
type ParseAsk:
	file str
	text str
	cache str
	compiler i64
	write bool

# A file parsed apart from the program: its name, where its parsed form is kept, its nodes
# numbered from 0 (appendParsed moves them on to where the program's arena ends), its
# declarations, what the parse noted, the cache entry it made when its ask held the writes, and
# whether it parsed (else the notes say why).
type ParsedApart:
	file str
	cache str
	nodes Node[]
	kidIds NodeId[]
	decls NodeId[]
	notes ParseNotes
	entry str
	ok bool
	names Interned = Interned()   # its nodes' names, numbered apart (numberNames)

# the ask for the text of file (read at the path `at`)
fn parseAsk(move text str, file str, at str):
	noteSourceParsed(at, text)
	kept = not nocacheWord().on() and "embed" not in text
	cache = "{cachesDir}/parse/{testSlug(fullPath(at))}" if kept else ""
	ParseAsk(file.copy(), move text, cache, compilerKey(), not parseWritesHeld)

# The ask's file parsed: read back from the cache when it holds its form, else lexed and parsed.
# It writes and prints nothing outside itself, so a job may run it.
fn parseApart(ask ParseAsk):
	nodes Node[] = []
	kidIds = []
	notes = ParseNotes()
	key = "{ask.file}\n{ask.text}".hash()
	if ask.cache != "" and fs.readBytes(ask.cache) is d and
		nodes.readParsed(kidIds, d, key, ask.compiler, notes) is decls:
		names = numberNames(nodes)
		return ParsedApart(
			file = ask.file.copy(),
			cache = ask.cache.copy(),
			nodes,
			kidIds,
			decls,
			notes,
			entry = "",
			ok = true,
			names
		)
	toks = lexNoted(ask.text, ask.file, false, notes)
	decls = parseNoted(toks ?? [], ask.file, nodes, kidIds, notes) if toks != none else none
	entry = ""
	if decls is parsed and ask.cache != "":
		head = []
		body = nodes.parsedBytes(kidIds, parsed, notes)
		head.pushU64le(ask.compiler)
		head.pushU64le(key)
		head.pushU64le(body.len)
		head.pushU64le(str(body.copy()).hash())
		entry = str(PackedParts.pack(parseCacheMagic, parseCacheVersion, head, body))
		if ask.write:
			_ = fs.createDir(fs.dirOf(ask.cache))
			_ = fs.writeFile(ask.cache, entry)
			entry = ""
	names = numberNames(nodes)
	ParsedApart(
		file = ask.file.copy(),
		cache = ask.cache.copy(),
		nodes,
		kidIds,
		decls = decls ?? [],
		notes,
		entry,
		ok = decls != none,
		names
	)

# the declarations of the file asked, parsed apart and appended to nodes; none (its errors said)
# when it said an error
fn parseCached(text str, file str, at str, mut nodes Node[], mut kidIds NodeId[]) NodeId[]?:
	nodes.appendParsed(kidIds, parseAsk(text.copy(), file, at).parseApart())

# The file's parse appended to the program's arena, its nodes and what it noted numbered on from
# where the arena ended, the cache entry it made kept to be written; the declarations, none (the
# errors said) when it did not parse.
fn appendParsed(mut nodes Node[], mut kidIds NodeId[], move part ParsedApart) NodeId[]?:
	if not part.ok:
		part.notes.report()
		return none
	if part.entry != "":
		parseWrites.push((part.cache.copy(), move part.entry))
		if not parseWritesHeld: writeParsed()
	start = nodes.len
	base = kidIds.len
	for id in part.kidIds:
		kidIds.push(id.movedOn(start))
	nodes.reserve(start + part.nodes.len)
	numbers = part.names.texts.map(interned.numbered(it))   # the file's names by the program's
	part.nodes.reverse()
	while true:
		n = part.nodes.pop() ?? break
		n.kidsAt += i32(base)
		if n.name >= 0: n.name = i32(numbers[n.name])
		n.idsMovedOn(start)
		nodes.push(move n)
	part.notes.apply(start, part.file)
	part.decls.map(.movedOn(start))

fn movedOn(id NodeId, start i64):
	NodeId(i64(id) + start)

# the ids a node holds of other nodes (its arm's first, its origin, its parts) numbered on from
# start
fn idsMovedOn(mut n Node, start i64):
	if n.kind == nArm and n.ival != 0: n.ival += i32(start)
	if n.part == none: return
	if n.origin() is o: n.nodePart().origin = o.movedOn(start)
	for i in 0..n.sub().len:
		n.nodePart().sub[i] = n.sub()[i].movedOn(start)
	for i in 0..n.types().len:
		n.nodePart().types[i] = n.types()[i].movedOn(start)

# the entries parseApart held back, written to build/cache/parse/
fn writeParsed():
	if parseWrites.isEmpty: return
	if not parseCacheReady:
		_ = fs.createDir("{cachesDir}/parse")
		parseCacheReady = true
	for (path, entry) in parseWrites:
		_ = fs.writeFile(path, entry)
	parseWrites = []

# the nodes, the declarations and what the parser noted in bytes (the nodes' ids numbered from the
# first)
fn parsedBytes(nodes Node[], kidIds NodeId[], decls NodeId[], notes ParseNotes):
	out = []
	out.pushVarint(nodes.len)
	for i in 0..nodes.len:
		out.pushNodeRecord(nodes, kidIds, i, 0)
	out.pushIds(decls, 0)
	out.pushIds(notes.shaderCalls, 0)
	out.pushIds(notes.numberBodies, 0)
	out

# node i's record, each node it names numbered from start: its kind, line and column, then a bit
# for each part it has and those parts (readNodeRecord); false when one points before start
fn pushNodeRecord(mut out u8[], nodes Node[], kidIds NodeId[], i i64, start i64):
	origin = -1
	if nodes[i].origin() is o: origin = i64(o)
	ival = nodes[i].ival
	if origin >= 0 and origin < start or nodes[i].kind == nArm and ival != 0 and ival < start:
		return false
	ty = -1
	if nodes[i].ty is t: ty = i64(t)
	out.pushVarint(nodes[i].kind)
	out.pushVarint(nodes[i].line)
	out.pushVarint(nodes[i].col)
	out.pushVarint(nodes[i].recordParts(origin, ty))
	if origin >= 0: out.pushVarint(origin - start)
	if nodes[i].flags != 0: out.pushVarint(nodes[i].flags)
	if ival != 0: out.pushVarint(ival - start + 1 if nodes[i].kind == nArm else ival)
	if ty >= 0: out.pushVarint(ty)
	if not nodes[i].ints().isEmpty:
		out.pushVarint(nodes[i].ints().len)
		for t in nodes[i].ints():
			out.pushVarint(i64(t))
	if nodes[i].text != "": out.pushText(nodes[i].text)
	if nodes[i].text2() != "": out.pushText(nodes[i].text2())
	if nodes[i].file() != "": out.pushText(nodes[i].file())
	if nodes[i].mod() != "": out.pushText(nodes[i].mod())
	if not nodes[i].kids(kidIds).isEmpty and not out.pushIds(nodes[i].kids(kidIds), start) or
		not nodes[i].sub().isEmpty and not out.pushIds(nodes[i].sub(), start) or
		not nodes[i].types().isEmpty and not out.pushIds(nodes[i].types(), start):
		return false
	if not nodes[i].names().isEmpty: out.pushTexts(nodes[i].names())
	if not nodes[i].bounds().isEmpty: out.pushTexts(nodes[i].bounds())
	if not nodes[i].names2().isEmpty: out.pushTexts(nodes[i].names2())
	true

# a bit for each part node n has, in the order pushNodeRecord writes them
fn recordParts(n Node, origin i64, ty i64):
	bits = [origin >= 0,
		n.flags != 0,
		n.ival != 0,
		ty >= 0,
		not n.ints().isEmpty,
		n.text != "",
		n.text2() != "",
		n.file() != "",
		n.mod() != "",
		n.kidsLen != 0,
		not n.sub().isEmpty,
		not n.types().isEmpty,
		not n.names().isEmpty,
		not n.bounds().isEmpty,
		not n.names2().isEmpty]
	parts = 0
	for k, on in bits:
		if on: parts |= 1 << k
	parts

# node ids from start; false when one points before start
fn pushIds(mut out u8[], ids NodeId[], start i64):
	out.pushVarint(ids.len)
	for id in ids:
		x = i64(id)
		if x < start: return false
		out.pushVarint(x - start)
	true

fn pushTexts(mut out u8[], texts str[]):
	out.pushVarint(texts.len)
	for s in texts:
		out.pushText(s)

fn pushText(mut out u8[], s str):
	out.pushVarint(s.len)
	out.extend(s.bytes())

# the declarations of a cache entry written by the compiler with the key `compiler` for key, its
# nodes appended to the empty arena and what it noted to notes; none (nodes untouched) when it is
# another's or cut short
fn readParsed(
	mut nodes Node[],
	mut kidIds NodeId[],
	d u8[],
	key i64,
	compiler i64,
	mut notes ParseNotes
) NodeId[]?:
	parts = try d.unpack(parseCacheMagic, parseCacheVersion)
	h = Reader(d, at = parts.headAt)
	if h.i64() != compiler or h.i64() != key: return none
	n = h.i64()
	sum = h.i64()
	if h.short or parts.bodyAt + n != parts.end or
		str(d[parts.bodyAt..parts.end].copy()).hash() != sum:
		return none
	r = Reader(d, at = parts.bodyAt)
	r.readNodes(nodes, kidIds)
	decls = r.readIds(0)
	noted = r.readIds(0)
	kept = r.readIds(0)
	if r.short or r.at != parts.end or kept.len % 2 != 0:
		nodes.clear()
		kidIds.clear()
		return none
	notes.shaderCalls = noted
	notes.numberBodies = kept
	decls

# the nodes parsedBytes wrote appended
fn readNodes(mut r Reader, mut nodes Node[], mut kidIds NodeId[]):
	count = r.varint()
	if count < 0 or count > r.d.len: return
	nodes.reserve(nodes.len + count)
	loop count:
		nodes.push(r.readNodeRecord(kidIds, 0))

# the node pushNodeRecord wrote, what it names numbered from start, its children put in kidIds
fn readNodeRecord(mut r Reader, mut kidIds NodeId[], start i64):
	kind = r.varint()
	line = r.varint()
	col = r.varint()
	parts = r.varint()
	origin = r.varint() if parts & 1 != 0 else -1
	flags = r.varint() if parts & 2 != 0 else 0
	ival = r.varint() if parts & 4 != 0 else 0
	ty = r.varint() if parts & 8 != 0 else -1
	ints = []
	if parts & 16 != 0:
		loop r.varint():
			ints.push(TypeId(r.varint()))
	text = r.readText() if parts & 32 != 0 else ""
	text2 = r.readText() if parts & 64 != 0 else ""
	file = r.readText() if parts & 128 != 0 else ""
	mod = r.readText() if parts & 256 != 0 else ""
	kids = r.readIds(start) if parts & 512 != 0 else []
	kidIds.extend(kids)
	sub = r.readIds(start) if parts & 1024 != 0 else []
	types = r.readIds(start) if parts & 2048 != 0 else []
	names = r.readTexts() if parts & 4096 != 0 else []
	bounds = r.readTexts() if parts & 8192 != 0 else []
	names2 = r.readTexts() if parts & 16_384 != 0 else []
	part Box<NodePart>? = none if parts & (
		1 | 16 | 64 | 128 | 256 | 1024 | 2048 | 4096 | 8192 | 16_384
	) ==
		0
		else Box(
			NodePart(
				text2,
				origin = none if origin < 0 else NodeId(start + origin),
				sub,
				types,
				names,
				file,
				mod,
				bounds,
				names2,
				ints
			)
		)
	Node(
		kind = u8(kind),
		line = i32(line),
		col = nodeCol(col),
		text,
		part,
		flags,
		ival = i32(start + ival - 1 if kind == nArm and ival != 0 else ival),
		kidsAt = i32(kidIds.len - kids.len),
		kidsLen = i32(kids.len),
		ty = none if ty < 0 else TypeId(ty)
	)

# (most texts and lists of a node are empty: those allocate nothing, the others once)
fn readText(mut r Reader):
	n = r.varint()
	if n <= 0 or not r.has(n): return ""
	r.at += n
	str(r.d[r.at - n..r.at])

fn readTexts(mut r Reader):
	n = r.varint()
	out str[] = []
	if n == 0: return out
	out.reserve(n)
	loop n:
		out.push(r.readText())
	out

# node ids written from the file's first node: start added back
fn readIds(mut r Reader, start i64):
	n = r.varint()
	out NodeId[] = []
	if n == 0: return out
	out.reserve(n)
	loop n:
		id = r.varint()
		out.push(NodeId(start + id))
	out
