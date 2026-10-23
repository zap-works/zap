# A cache of the intermediate form's optimization (irSimplify, the largest share of a build): a
# function's form as lowered, written out, is the key, and the form irSimplify makes of it the
# value, kept from one build to the next in build/cache/ir/, a file per source file and target
# that every program building the file's functions shares. The numbers each program gives its own
# way (types, data offsets, nodes: irNumberTable) are written as their places among the
# function's own, in their order, so a module's function lowered alike by two programs is one
# entry. The key is the whole input of a pass that reads nothing else and keeps those numbers'
# order, so a hit gives the very form the pass would make and the executable is the same byte for
# byte; another compiler's entries are not read. Zaps building at once share the files: one is
# written whole beside its place and moved over it, and one cut short is ignored.

import fs

irCacheMagic = "ZIRC"
irCacheVersion = 5
irCacheKeep = 8   # how many rewrites of its file an entry no build used outlives

# the entries of one source file's functions
type IrShard:
	path str
	index {str: i64}   # a lowered form's bytes -> its entry
	simplified u8[,]
	age i64[]   # the rewrites of the file since a build used the entry
	used bool[]   # by this build
	changed bool   # an entry made: written back at the end

type IrCache:
	entry str   # "" while no build uses it; the shard of the code of no declaration
	compiler i64   # the key of the compiler that made the entries (compilerKey)
	shards {str: i64}   # a source file -> its shard in list
	list IrShard[]

mut irCache = IrCache(entry = "", compiler = 0, shards = {}, list = [])

fn nocacheWord():
	TraceWord("nocache", "builds without build/cache/: a cold build")

# the cache of the program whose entry file is `file`, its files read as its functions ask for
# them (ZAP_RUN=nocache: none, a cold build)
fn irCacheOpen(file str):
	if nocacheWord().on(): return
	irCache = IrCache(entry = file.copy(), compiler = compilerKey(), shards = {}, list = [])

# the files this build made an entry of written back, the cache then closed
fn irCacheSave():
	if irCache.entry != "" and irCache.list.any(.changed):
		_ = fs.createDir("build/cache")
		_ = fs.createDir("build/cache/ir")
		for shard in irCache.list:
			if shard.changed:
				shard.irShardWrite(irCache.compiler)
	irCacheClose()

fn irCacheClose():
	irCache = IrCache(entry = "", compiler = 0, shards = {}, list = [])

# the shard of the functions declared in `file` ("": the entry's), read when first asked for
fn irShardOf(file str):
	source = irCache.entry if file == "" or file.startsWith("<") else file
	if irCache.shards.get(source) is at: return at
	path = "build/cache/ir/{testSlug(fullPath(source))}{targetTag()}.ir"
	irCache.shards[source.copy()] = irCache.list.len
	irCache.list.push(irShardRead(path, irCache.compiler))
	irCache.list.len - 1

fn emptyShard(path str):
	IrShard(path = path.copy(), index = {}, simplified = [], age = [], used = [], changed = false)

# the entries at path when this compiler wrote them whole, else none
fn irShardRead(path str, compiler i64):
	d = fs.readBytes(path) ?? return emptyShard(path)
	parts = d.unpack(irCacheMagic, irCacheVersion) ?? return emptyShard(path)
	r = Reader(d, at = parts.headAt)
	if r.i64() != compiler or r.i64() != str(d[parts.bodyAt..].copy()).hash():
		return emptyShard(path)
	r.at = parts.bodyAt
	count = r.varint()
	if count < 0 or count > d.len: return emptyShard(path)
	shard = emptyShard(path)
	loop count:
		key = str(r.bytes(r.varint()))
		shard.age.push(r.varint())
		shard.index[key] = shard.simplified.len
		shard.simplified.push(r.bytes(r.varint()))
	if r.short or r.at != parts.end: return emptyShard(path)
	shard.used = zeros(shard.simplified.len)
	shard

# the shard written back with what other builds wrote to its file since it was read, an entry
# left out once irCacheKeep rewrites passed without a build using it
fn irShardWrite(shard IrShard, compiler i64):
	disk = irShardRead(shard.path, compiler)
	entries u8[] = []
	count = 0
	for key in shard.index.keys():
		i = shard.index.get(key) ?? continue
		age = 0 if shard.used[i] else shard.age[i] + 1
		if age <= irCacheKeep:
			entries.irPushEntry(key, age, shard.simplified[i])
			count += 1
	for key in disk.index.keys():
		i = disk.index.get(key) ?? continue
		if key not in shard.index and disk.age[i] < irCacheKeep:
			entries.irPushEntry(key, disk.age[i] + 1, disk.simplified[i])
			count += 1
	body = []
	body.pushVarint(count)
	body.extend(entries)
	head = []
	head.pushU64le(compiler)
	head.pushU64le(str(body.copy()).hash())
	_ = placeFile(shard.path, str(PackedParts.pack(irCacheMagic, irCacheVersion, head, body)))

fn irPushEntry(mut out u8[], key str, age i64, simplified u8[]):
	out.pushVarint(key.len)
	out.extend(key.bytes())
	out.pushVarint(age)
	out.pushVarint(simplified.len)
	out.extend(simplified)

# m's form as lowered written out, its numbers by their places among its own: its key
fn irCacheKey(mut m IrMade):
	m.numbers = m.f.irNumbersOf()
	lowered = []
	m.f.irWrite(lowered, irRenamingOf(m.numbers, false))
	m.lowered = str(move lowered)

# the form the cache holds for m's key taken (m.cached) from the shard of `file`, the key then
# dropped; else it stays, for irCacheStore
fn irCacheLookup(mut m IrMade, file str):
	if m.lowered == "": return
	m.shard = irShardOf(file)
	if irCache.list[m.shard].index.get(m.lowered) is i:
		irCache.list[m.shard].used[i] = true
		m.cached = irCache.list[m.shard].simplified[i].copy()
		m.lowered = ""

# the form m's passes made kept for the next build (once for one form as lowered)
fn irCacheStore(m IrMade):
	if m.lowered == "" or m.lowered in irCache.list[m.shard].index: return
	irCache.list[m.shard].index[m.lowered.copy()] = irCache.list[m.shard].simplified.len
	irCache.list[m.shard].simplified.push(m.simplified.copy())
	irCache.list[m.shard].age.push(0)
	irCache.list[m.shard].used.push(true)
	irCache.list[m.shard].changed = true

# ---------- the numbers each program gives its own way ----------

irTyAt = 13   # the places in irInstNumbers of ty (a type + 1, 0 none), imm and other
irImmAt = 5
irOtherAt = 10
irProgramPlaces = [irTyAt, irImmAt, irOtherAt]

# the table of the number at place `at` of an instruction's numbers when the program numbers it
# its own way: 0 the types, 1 the data offsets, 2 the nodes; else -1
fn irNumberTable(op i64, n i64[], at i64):
	if at == irTyAt: return 0 if n[at] != 0 else -1
	if at == irImmAt: return 0 if op == irOwn else 1 if op == irDataAddr else -1
	2 if n[at] >= 0 and (op == irOwnEnd or op == irNote) else -1

# what the place holds above the number (ty's 1)
fn irNumberBias(at i64):
	1 if at == irTyAt else 0

# each table's numbers in f, sorted
fn irNumbersOf(f IrFn):
	seen {i64: bool}[] = [{}, {}, {}]
	for b in f.blocks:
		for inst in b.insts:
			n = inst.irInstNumbers()
			for at in irProgramPlaces:
				table = irNumberTable(inst.op, n, at)
				if table >= 0:
					seen[table][n[at] - irNumberBias(at)] = true
	seen.map(.keys().sorted())

# each table's numbers -> their places, or with back their places -> their numbers
fn irRenamingOf(numbers i64[,], back bool):
	names = []
	for row in numbers:
		m {i64: i64} = {}
		for i, x in row:
			if back:
				m[i] = x
			else:
				m[x] = i
		names.push(m)
	names

# n's numbers of the tables renamed by names (irRenamingOf); false when names lacks
# one
fn irRenumber(op i64, mut n i64[], names {i64: i64}[]):
	for at in irProgramPlaces:
		table = irNumberTable(op, n, at)
		if table >= 0:
			bias = irNumberBias(at)
			n[at] = (names[table].get(n[at] - bias) ?? return false) + bias
	true

# ---------- the form as bytes ----------

# f's blocks, vregs and loops at the end of out, its numbers renamed by names (irRead reads them
# back); false when names lacks one
fn irWrite(f IrFn, mut out u8[], names {i64: i64}[]):
	out.pushVarint(f.blocks.len)
	for b in f.blocks:
		out.pushVarint((1 if b.loopTop else 0) | (2 if b.cold else 0))
		out.pushVarint(b.insts.len)
		for inst in b.insts:
			if not inst.irWriteInst(out, names): return false
	irWriteList(out, f.classes)
	out.pushVarint(f.cur)
	out.pushVarint(f.loops.len)
	for l in f.loops:
		out.pushVarint(l.pre)
		irWriteList(out, l.blocks)
	out.pushVarint(f.switches.len)
	for sw in f.switches:
		irWriteList(out, sw.values)
		irWriteList(out, sw.targets)
	true

# the form irWrite wrote, its numbers renamed by names; none when names lacks one
fn irRead(mut r Reader, names {i64: i64}[]) IrFn?:
	blocks = []
	loop r.varint():
		flags = r.varint()
		insts = []
		loop r.varint():
			insts.push(try r.irReadInst(names))
		blocks.push(IrBlock(insts, loopTop = flags & 1 != 0, cold = flags & 2 != 0))
	classes = r.irReadList()
	cur = r.varint()
	loops = []
	loop r.varint():
		pre = r.varint()
		loops.push(IrLoop(pre, blocks = r.irReadList()))
	switches = []
	loop r.varint():
		values = r.irReadList()
		switches.push(IrSwitch(values, targets = r.irReadList()))
	IrFn(blocks, classes, cur, loops, switches)

# an instruction's numbers and flags in the order they are written (irInstOf takes them back)
fn irInstNumbers(inst IrInst):
	[inst.dst,
		inst.a,
		inst.b,
		inst.c,
		inst.d,
		inst.imm,
		inst.size,
		inst.scale,
		inst.cond,
		inst.target,
		inst.other,
		inst.line,
		inst.col,
		typeNumber(inst.ty),
		inst.pure]

# a type as a cache number: 0 for none, else its index + 1
fn typeNumber(t TypeId?):
	match t:
		t: i64(t) + 1
		none: 0

fn numberType(n i64) TypeId?:
	none if n == 0 else TypeId(n - 1)

fn irInstFlags(inst IrInst):
	[inst.uns, inst.regArgs, inst.header, inst.frame, inst.trap]

fn irInstOf(op i64, n i64[], on bool[], move args i64[], move key str):
	IrInst(
		op,
		dst = n[0],
		a = n[1],
		b = n[2],
		c = n[3],
		d = n[4],
		imm = n[5],
		size = n[6],
		scale = n[7],
		cond = n[8],
		target = n[9],
		other = n[10],
		line = n[11],
		col = n[12],
		ty = numberType(n[13]),
		pure = n[14],
		uns = on[0],
		regArgs = on[1],
		header = on[2],
		frame = on[3],
		trap = on[4],
		args,
		key
	)

# what an instruction holds unless it says otherwise: only the rest is written
irBlankNumbers = irInstNumbers(IrInst(op = irConst))
irFlagCount = irInstFlags(IrInst(op = irConst)).len

# the operation, then a mask of what differs from a blank instruction (a bit per number, per
# flag, then the arguments and the key), then those numbers, the arguments and the key
fn irWriteInst(inst IrInst, mut out u8[], names {i64: i64}[]):
	numbers = inst.irInstNumbers()
	if not irRenumber(inst.op, numbers, names): return false
	mask = 0
	for i, v in numbers:
		if v != irBlankNumbers[i]:
			mask |= 1 << i
	for i, on in inst.irInstFlags():
		if on:
			mask |= 1 << (numbers.len + i)
	argsBit = 1 << (numbers.len + irFlagCount)
	if not inst.args.isEmpty:
		mask |= argsBit
	if inst.key != "":
		mask |= argsBit << 1
	out.pushVarint(inst.op)
	out.pushVarint(mask)
	for i, v in numbers:
		if (mask & (1 << i)) != 0:
			out.pushVarint(v)
	if (mask & argsBit) != 0:
		irWriteList(out, inst.args)
	if (mask & (argsBit << 1)) != 0:
		out.pushVarint(inst.key.len)
		out.extend(inst.key.bytes())
	true

fn irReadInst(mut r Reader, names {i64: i64}[]) IrInst?:
	op = r.varint()
	mask = r.varint()
	numbers = irBlankNumbers.copy()
	for i in 0..numbers.len:
		if (mask & (1 << i)) != 0:
			numbers[i] = r.varint()
	on = (0..irFlagCount).map((mask & (1 << (numbers.len + it))) != 0)
	argsBit = 1 << (numbers.len + irFlagCount)
	args = r.irReadList() if (mask & argsBit) != 0 else []
	key = str(r.bytes(r.varint())) if (mask & (argsBit << 1)) != 0 else ""
	if not irRenumber(op, numbers, names): return none
	irInstOf(op, numbers, on, args, key)

fn irWriteList(mut out u8[], xs i64[]):
	out.pushVarint(xs.len)
	for x in xs:
		out.pushVarint(x)

fn irReadList(mut r Reader):
	xs = []
	loop r.varint():
		xs.push(r.varint())
	xs
