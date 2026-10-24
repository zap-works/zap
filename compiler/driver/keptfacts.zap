# What one walk of each body of the kept stages found (bodyfacts.zap: the names it mentions, what
# it calls and changes, what it does itself) kept beside the last of them in build/cache/, under
# that stage's key: a body of those stages and what it names are the same in every program whose
# stages begin with them, so the next such build reads their records instead of walking their
# bodies again, and walks only the program's own. A build keeps them only when it found no error
# by then: none of the stages' module variables reads another in a circle (initorder.zap).

import fs

keptFactsMagic = "ZKFA"
keptFactsVersion = 1

# the last stage of the runtime or std a build checked or read, and the declarations it ends at;
# none when there is none or the build keeps nothing
fn factsStage(stages CheckStage[]) CheckStage?:
	if not keepsStages() or noting: return none
	at = -1
	for i, s in stages:
		if s.key != 0 and s.done: at = i
	if at < 0: return none
	stages[at].copy()

# where the records of the stages ending with stage are kept
fn keptFactsPath(stage CheckStage):
	"{stagePath(stage.name)}.facts"

# the records kept for the stages ending with stage, by function: empty when there are none
fn keptFactsOf(stage CheckStage) {NodeId: FnFacts}:
	out {NodeId: FnFacts} = {}
	d = fs.readBytes(keptFactsPath(stage)) ?? return out
	parts = d.unpack(keptFactsMagic, keptFactsVersion) ?? return out
	if not d.keptFor(parts, stage.key): return out
	r = Reader(d, at = parts.bodyAt)
	read {NodeId: FnFacts} = {}
	loop r.count():
		f = r.readFnFacts()
		read[f.fnd] = f
	if r.short or r.at != parts.end: return out
	read

# the records of the stages' functions (those below the stage's last node) kept, when none are
fn keepFacts(stage CheckStage, facts FnFacts[]):
	path = keptFactsPath(stage)
	if fs.readBytes(path) is d and d.unpack(keptFactsMagic, keptFactsVersion) is parts and
		d.keptFor(parts, stage.key):
		return
	kept = facts.filter(i64(.fnd) < stage.nodes)
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
	out.pushVarint(f.placesChanged.len)
	for ch in f.placesChanged:
		out.pushText(ch.root)
		out.pushText(ch.below)
		out.pushVarint(i64(ch.callee ?? NodeId(0)) + 1 if ch.callee != none else 0)
		out.pushText(ch.param)
		out.pushVarint(1 if ch.named else 0)
	out.pushVarint(f.own)
	out.pushIds(f.reaches, 0)
	out.pushVarint(f.keeps)
	out.pushVarint(1 if f.memory else 0)

fn readFnFacts(mut r Reader) FnFacts:
	f = FnFacts(fnd = NodeId(r.varint()))
	f.fields = r.readTexts()
	f.names = r.readTexts()
	f.calls = r.readIds(0)
	f.closureCalls = r.varint() == 1
	loop r.count():
		root = r.readText()
		below = r.readText()
		callee = r.varint() - 1
		param = r.readText()
		named = r.varint() == 1
		f.placesChanged.push(
			ChangeAt(root, below, callee = NodeId(callee) if callee >= 0 else none, param, named)
		)
	f.own = r.varint()
	f.reaches = r.readIds(0)
	f.keeps = r.varint()
	f.memory = r.varint() == 1
	f
