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
parseCacheVersion = 4

# where build/cache/parse/ is known made
mut parseCacheReady = false

# the declarations parseSource makes of the text of file (read at the path `at`), its nodes
# appended to nodes: read back from the cache when it holds them (ZAP_RUN=nocache: parsed);
# none when it said an error
fn parseCached(text str, file str, at str, mut nodes Node[]) NodeId[]?:
	noteSourceParsed(at, text)
	if nocacheWord().on() or "embed" in text: return parseSource(text, file, nodes)
	path = "build/cache/parse/{testSlug(fullPath(at))}"
	key = "{file}\n{text}".hash()
	if fs.readBytes(path) is d and nodes.readParsed(d, key, file) is decls: return decls
	start = nodes.len
	calls = shaderCalls.len
	decls = try parseSource(text, file, nodes)
	if not parseCacheReady:
		_ = fs.createDir("build/cache/parse")
		parseCacheReady = true
	if nodes.parsedBytes(start, decls, calls) is body:
		head = []
		head.pushU64le(compilerKey())
		head.pushU64le(key)
		head.pushU64le(body.len)
		head.pushU64le(str(body.copy()).hash())
		_ = fs.writeFile(
			path,
			str(PackedParts.pack(parseCacheMagic, parseCacheVersion, head, body))
		)
	decls

# nodes from start on and the declarations, numbered from start (none when one points before it)
fn parsedBytes(nodes Node[], start i64, decls NodeId[], calls i64) u8[]?:
	out = []
	out.pushVarint(nodes.len - start)
	for i in start..nodes.len:
		out.pushVarint(nodes[i].kind)
		out.pushVarint(nodes[i].line)
		out.pushVarint(nodes[i].col)
		origin = -1
		if nodes[i].origin is o: origin = i64(o)
		if origin >= 0 and origin < start: return none
		out.pushVarint(-1 if origin < 0 else origin - start)
		out.pushVarint(nodes[i].flags)
		ival = nodes[i].ival
		if nodes[i].kind == nArm and ival != 0 and ival < start: return none
		out.pushVarint(ival - start + 1 if nodes[i].kind == nArm and ival != 0 else ival)
		ty = -1
		if nodes[i].ty is t: ty = i64(t)
		out.pushVarint(ty)
		out.pushText(nodes[i].text)
		out.pushText(nodes[i].text2)
		out.pushText(nodes[i].file())
		out.pushText(nodes[i].mod())
		if not out.pushIds(nodes[i].kids, start) or not out.pushIds(nodes[i].sub, start) or
			not out.pushIds(nodes[i].types, start):
			return none
		out.pushTexts(nodes[i].names)
		out.pushTexts(nodes[i].bounds())
		out.pushTexts(nodes[i].names2())
		out.pushVarint(nodes[i].ints().len)
		for t in nodes[i].ints():
			out.pushVarint(i64(t))
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
	count = r.varint()
	loop count:
		kind = r.varint()
		line = r.varint()
		col = r.varint()
		origin = r.varint()
		flags = r.varint()
		ival = r.varint()
		ty = r.varint()
		text = r.readText()
		text2 = r.readText()
		file = r.readText()
		mod = r.readText()
		kids = r.readIds(start)
		sub = r.readIds(start)
		types = r.readIds(start)
		names = r.readTexts()
		bounds = r.readTexts()
		names2 = r.readTexts()
		ints = []
		loop r.varint():
			ints.push(TypeId(r.varint()))
		part DeclPart[] = [] if file == "" and mod == "" and bounds.isEmpty and names2.isEmpty and
			ints.isEmpty
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

fn readText(mut r Reader):
	str(r.bytes(r.varint()))

fn readTexts(mut r Reader):
	out = []
	loop r.varint():
		out.push(r.readText())
	out

# node ids written from the file's first node: start added back
fn readIds(mut r Reader, start i64):
	out = []
	loop r.varint():
		id = r.varint()
		out.push(NodeId(start + id))
	out
