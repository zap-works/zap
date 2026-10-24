# What one walk of each body of the kept stages found (bodyfacts.zap: the names it mentions, what
# it calls and changes, what it does itself) kept beside each stage in build/cache/, the records
# of the stage's own functions under its key: a body of those stages and what it names are the
# same in every program whose stages begin with them, so the next such build reads their records
# instead of walking their bodies again, and walks only those past the first stage it has none
# of. A build keeps them only when it found no error by then: none of the stages' module
# variables reads another in a circle (initorder.zap).

import fs

keptFactsMagic = "ZKFA"
keptFactsVersion = 3

# the stages of the runtime, std or the program's modules a build checked or read; none when the
# build keeps nothing
fn factsStages(stages CheckStage[]):
	if not keepsStages() or noting: return []
	stages.filter(.key != 0 and .done)

# where the records of the functions of the stage ending a chain are kept
fn keptFactsPath(stage CheckStage):
	"{stage.stagePath()}.facts"

# the records kept for the functions of the stage ending a chain, by function; none when there
# are none
fn keptFactsOf(stage CheckStage) {NodeId: FnFacts}?:
	d = fs.readBytes(stage.keptFactsPath()) ?? return none
	parts = try d.unpack(keptFactsMagic, keptFactsVersion)
	if not d.keptFor(parts, stage.key): return none
	r = Reader(d, at = parts.bodyAt)
	read {NodeId: FnFacts} = {}
	loop r.count():
		f = r.readFnFacts()
		read[f.fnd] = f
	if r.short or r.at != parts.end: return none
	read

# the records kept of the first stages' functions, those of each while the stages before it had
# theirs, by function; and the nodes the stages read end at (0 none)
fn keptFactsUpTo(stages CheckStage[]):
	out {NodeId: FnFacts} = {}
	below = 0
	for s in stages:
		read = s.keptFactsOf() ?? break
		for d, f in read:
			out[d] = f
		below = s.nodes
	(out, below)

# the records of the functions of each stage past the nodes below (those not below its first
# node and below its last) kept, when none are
fn keepFacts(stages CheckStage[], below i64, facts FnFacts[]):
	from = 0
	for s in stages:
		if from >= below: s.keepStageFacts(facts.filter(i64(.fnd) >= from and i64(.fnd) < s.nodes))
		from = s.nodes

fn keepStageFacts(stage CheckStage, kept FnFacts[]):
	path = stage.keptFactsPath()
	if fs.readBytes(path) is d and d.unpack(keptFactsMagic, keptFactsVersion) is parts and
		d.keptFor(parts, stage.key):
		return
	body = []
	body.pushVarint(kept.len)
	for f in kept:
		body.pushFnFacts(f)
	head = []
	head.pushU64le(compilerKey())
	head.pushU64le(stage.key)
	_ = fs.createDir(cachesDir)
	placeFile(path, str(PackedParts.pack(keptFactsMagic, keptFactsVersion, head, body)))

fn pushFnFacts(mut out u8[], f FnFacts):
	out.pushVarint(i64(f.fnd))
	out.pushTexts(f.fields)
	out.pushTexts(f.names)
	out.pushIds(f.calls, 0)
	out.pushVarint(1 if f.closureCalls else 0)
	out.pushChanges(f.placesChanged)
	out.pushVarint(f.own)
	out.pushIds(f.reaches, 0)
	out.pushVarint(f.keeps)
	out.pushVarint(1 if f.memory else 0)
	out.pushVarint(f.lambdas.len)
	for l in f.lambdas:
		out.pushChanges(l.placesChanged)
		out.pushVarint(l.calls.len)
		for d in l.calls:
			out.pushVarint(i64(d ?? NodeId(0)) + 1 if d != none else 0)
	out.pushIds(f.valued, 0)

fn pushChanges(mut out u8[], changes ChangeAt[]):
	out.pushVarint(changes.len)
	for ch in changes:
		out.pushText(ch.root)
		out.pushText(ch.below)
		out.pushVarint(i64(ch.callee ?? NodeId(0)) + 1 if ch.callee != none else 0)
		out.pushText(ch.param)
		out.pushVarint(1 if ch.named else 0)

fn readFnFacts(mut r Reader):
	f = FnFacts(fnd = NodeId(r.varint()))
	f.fields = r.readTexts()
	f.names = r.readTexts()
	f.calls = r.readIds(0)
	f.closureCalls = r.varint() == 1
	f.placesChanged = r.readChanges()
	f.own = r.varint()
	f.reaches = r.readIds(0)
	f.keeps = r.varint()
	f.memory = r.varint() == 1
	loop r.count():
		l = LambdaChanges(placesChanged = r.readChanges())
		loop r.count():
			d = r.varint() - 1
			l.calls.push(NodeId(d) if d >= 0 else none)
		f.lambdas.push(l)
	f.valued = r.readIds(0)
	f

fn readChanges(mut r Reader):
	out = []
	loop r.count():
		root = r.readText()
		below = r.readText()
		callee = r.varint() - 1
		param = r.readText()
		named = r.varint() == 1
		out.push(
			ChangeAt(root, below, callee = NodeId(callee) if callee >= 0 else none, param, named)
		)
	out
