# A cache of the load (lexing and parsing a file, a tenth of a build and a third of a small
# program's): each source file's nodes as parsed, kept in build/cache/parse/ under its path with
# the hash of its name and text and the compiler's key (compilerKey). A file whose text is
# unchanged is read back instead of parsed; its nodes are numbered from its first, so they go
# wherever the arena ends, and the program is the same node for node (spec/commands.zap); an arm's note of the first arm of
# its patterns (ival) is a node too. What
# the parser notes besides the nodes comes back too: the calls of `shader` and `compute`
# (gpu.zap) and the bodies kept of functions with number parameters (regarrays.zap). A file that
# embeds another (`embed`) is always parsed: its nodes hold that file's bytes.

import fs

parseCacheMagic = "ZPRC"
parseCacheVersion = 5

# where build/cache/parse/ is known made
mut parseCacheReady = false

# while set, the entries parseCached makes wait in parseWrites until writeParsed (a run writes
# them once its program started)
mut parseWritesHeld = false
mut parseWrites (str, str)[] = []

# the declarations parseSource makes of the text of file (read at the path `at`), its nodes
# appended to nodes: read back from the cache when it holds them (ZAP_RUN=nocache: parsed);
# none when it said an error
fn parseCached(text str, file str, at str, mut nodes Node[]) NodeId[]?:
	noteSourceParsed(at, text)
	if nocacheWord().on() or "embed" in text: return parseSource(text, file, nodes)
	path = "{cachesDir}/parse/{testSlug(fullPath(at))}"
	key = "{file}\n{text}".hash()
	if fs.readBytes(path) is d and nodes.readParsed(d, key, file) is decls: return decls
	start = nodes.len
	calls = shaderCalls.len
	decls = try parseSource(text, file, nodes)
	if nodes.parsedBytes(start, decls, calls) is body:
		head = []
		head.pushU64le(compilerKey())
		head.pushU64le(key)
		head.pushU64le(body.len)
		head.pushU64le(str(body.copy()).hash())
		entry = str(PackedParts.pack(parseCacheMagic, parseCacheVersion, head, body))
		parseWrites.push((path, entry))
		if not parseWritesHeld: writeParsed()
	decls

# the entries parseCached made written to build/cache/parse/
fn writeParsed():
	if parseWrites.isEmpty: return
	if not parseCacheReady:
		_ = fs.createDir("{cachesDir}/parse")
		parseCacheReady = true
	for (path, entry) in parseWrites:
		_ = fs.writeFile(path, entry)
	parseWrites = []

# nodes from start on and the declarations, numbered from start (none when one points before it)
fn parsedBytes(nodes Node[], start i64, decls NodeId[], calls i64) u8[]?:
	out u8[] = []
	if not out.pushNodes(nodes, start): return none
	if not out.pushIds(decls, start): return none
	# what the parser noted: its shader calls (shaderCalls from calls on), its number bodies
	noted = []
	for i in calls..shaderCalls.len:
		call, _ = shaderCalls[i]
		noted.push(call)
	if not out.pushIds(noted, start): return none
	kept = []
	for f in numberBodies.keys():
		if i64(f) >= start:
			kept.push(f)
			kept.push(numberBodies.get(f) ?? continue)
	if not out.pushIds(kept, start): return none
	out

# the nodes from start on, each node they name numbered from start (the records of the parse
# cache and of the kept stages): its kind, line and column, then a bit for each part it has and
# those parts (readNodes); false when one points before start
fn pushNodes(mut out u8[], nodes Node[], start i64):
	out.pushVarint(nodes.len - start)
	for i in start..nodes.len:
		origin = -1
		if nodes[i].origin is o: origin = i64(o)
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
		if nodes[i].text2 != "": out.pushText(nodes[i].text2)
		if nodes[i].file() != "": out.pushText(nodes[i].file())
		if nodes[i].mod() != "": out.pushText(nodes[i].mod())
		if not nodes[i].kids.isEmpty and not out.pushIds(nodes[i].kids, start) or
			not nodes[i].sub.isEmpty and not out.pushIds(nodes[i].sub, start) or
			not nodes[i].types.isEmpty and not out.pushIds(nodes[i].types, start):
			return false
		if not nodes[i].names.isEmpty: out.pushTexts(nodes[i].names)
		if not nodes[i].bounds().isEmpty: out.pushTexts(nodes[i].bounds())
		if not nodes[i].names2().isEmpty: out.pushTexts(nodes[i].names2())
	true

# a bit for each part node n has, in the order pushNodes writes them
fn recordParts(n Node, origin i64, ty i64):
	bits = [origin >= 0,
		n.flags != 0,
		n.ival != 0,
		ty >= 0,
		not n.ints().isEmpty,
		n.text != "",
		n.text2 != "",
		n.file() != "",
		n.mod() != "",
		not n.kids.isEmpty,
		not n.sub.isEmpty,
		not n.types.isEmpty,
		not n.names.isEmpty,
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

# the declarations of a cache entry written by this compiler for key, its nodes appended; none
# (nodes untouched) when it is another's or cut short
fn readParsed(mut nodes Node[], d u8[], key i64, parsedAs str) NodeId[]?:
	parts = try d.unpack(parseCacheMagic, parseCacheVersion)
	h = Reader(d, at = parts.headAt)
	if h.i64() != compilerKey() or h.i64() != key: return none
	n = h.i64()
	sum = h.i64()
	if h.short or parts.bodyAt + n != parts.end or
		str(d[parts.bodyAt..parts.end].copy()).hash() != sum:
		return none
	start = nodes.len
	r = Reader(d, at = parts.bodyAt)
	r.readNodes(nodes, start)
	decls = r.readIds(start)
	noted = r.readIds(start)
	kept = r.readIds(start)
	if r.short or r.at != parts.end or kept.len % 2 != 0:
		nodes.truncate(start)
		return none
	for call in noted:
		noteShaderCall(call, parsedAs)
	for i in 0..kept.len / 2:
		numberBodies[kept[2 * i]] = kept[2 * i + 1]
	decls

# the nodes pushNodes wrote appended, numbered from start
fn readNodes(mut r Reader, mut nodes Node[], start i64):
	count = r.varint()
	if count < 0 or count > r.d.len: return
	nodes.reserve(nodes.len + count)
	loop count:
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
		sub = r.readIds(start) if parts & 1024 != 0 else []
		types = r.readIds(start) if parts & 2048 != 0 else []
		names = r.readTexts() if parts & 4096 != 0 else []
		bounds = r.readTexts() if parts & 8192 != 0 else []
		names2 = r.readTexts() if parts & 16_384 != 0 else []
		part DeclPart[] = [] if parts & (16 | 128 | 256 | 8192 | 16_384) == 0
			else [DeclPart(file, mod, bounds, names2, ints)]
		nodes.push(
			Node(
				kind,
				line,
				col,
				text,
				text2,
				origin = none if origin < 0 else NodeId(start + origin),
				kids,
				sub,
				types,
				names,
				part,
				flags,
				ival = start + ival - 1 if kind == nArm and ival != 0 else ival,
				ty = none if ty < 0 else TypeId(ty)
			)
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
