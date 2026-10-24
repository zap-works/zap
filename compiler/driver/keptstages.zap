# The stages kept checked (spec 14.2), as Rust keeps a crate's rlib and Go its export data: once
# a build checks a stage of the runtime or of std, what the checker then holds (its nodes,
# declarations, modules, instances, types and the tables the stages after it and the backend
# read, keptstate.zap) is written to build/cache/, a file per stage (stagePath), under the stage's
# key: the compiler's key, the target, the stage's sources and the key of the stage before it. A
# build whose stages begin
# with a kept chain reads the last state of it back and checks only the stages after it, the
# checker where it would be had it checked those, so the executable is the same byte for byte. A
# zap answering a test's requests keeps the states it read in memory (keepRuntime).

import fs

keptMagic = "ZKST"
keptVersion = 4

# what a kept file holds: the checker after its stages, the types' index, the bodies kept of
# functions with number parameters and whether a drop function was declared
type KeptStages:
	checker Checker
	stages CheckStage[]
	index {i64: TypeId}
	bodies {NodeId: NodeId}
	drops bool

# set while a zap answers requests: the states read stay in memory for its next programs
mut keepRuntime = false

mut keptInMemory {i64: KeptStages} = {}

fn keptWord():
	TraceWord("kept", "the stages a build read kept checked, and those it checked and kept")

# whether this build reads and writes kept stages: a build with the cache (not nocache), of the
# files as they are (not the lint's patched texts), outside the lint's notes but in a zap
# answering requests (where the notes are of the program's own files)
fn keepsStages():
	not nocacheWord().on() and sourceOverrides.isEmpty and (not noting or keepRuntime)

# the stages of the runtime's dirs and of the std modules, before the program's, each with its
# key: the one before it, its name and its sources' names and texts
fn stageChain(rtDir str, dirs str[], modules Module[]):
	out = []
	key = "{compilerKey()}\n{targets[buildTarget].name}".hash()
	sources = runtimeSources(rtDir)
	for d in dirs:
		key = stageKey(key, "rt/{d}", rtDir, sources.filter(runtimeDirOf(it) == d))
		out.push(CheckStage(name = "rt/{d}", decls = 0, modules = 0, key))
	for m in modules:
		if not m.isStdStage(): continue
		dir = fs.dirOf(m.file)
		files = fs.zapFiles(dir, false).map(it[dir.len + 1..].copy())
		key = stageKey(key, m.id, "{dir}/", files)
		out.push(CheckStage(name = m.id.copy(), decls = 0, modules = 0, key))
	out

# the key of a stage after the one keyed `before`: its name and its files below dir, their names
# and texts
fn stageKey(before i64, name str, dir str, files str[]):
	lines = ["{before}", name.copy()]
	for f in files.sorted():
		hash = fileHash("{dir}{f}")
		noteSourceRead("{dir}{f}", i64.parse(hash) ?? 0)   # (the run's stamp and the compiler's key name it)
		lines.push("{f}\t{hash}")
	lines.join("\n").hash()

# where a stage is kept: a file of build/cache/ named by the stage (rt-core, std-fs) and the
# target, holding the last chain written that ends with it
fn stagePath(name str):
	"{cachesDir}/{stageFile(name)}{targetTag()}"

fn stageFile(name str):
	name.replace("/", "-") if name.startsWith("rt/") else "std-{name}"

# The longest run of the chain's first stages kept read back into prog (its checker, the stages
# done, the types' index), the std modules it holds taken out of those loaded; the names of its
# stages. With the lint's notes only the runtime's stages are read (a std module may be the lint's
# file).
fn keepFrom(mut prog Program, chain CheckStage[]):
	if not keepsStages(): return []
	at = chain.len
	while at > 0:
		stage = chain[at - 1]
		if not noting or stage.name.startsWith("rt/"):
			if stage.keptStages() is kept:
				names = chain[..at].map(.name.copy())
				if keptWord().on(): eprint("kept: read {names.join(" ")}")
				prog.takeKept(kept, names)
				return names
		at -= 1
	[]

# the stages kept ending with stage, from this process's memory or the cache, while they are the
# chain its key names
fn keptStages(stage CheckStage) KeptStages?:
	key = stage.key
	if keptInMemory.get(key) is known: return known.copy()
	d = fs.readBytes(stagePath(stage.name)) ?? return none
	parts = try d.unpack(keptMagic, keptVersion)
	if not d.keptFor(parts, key): return none
	r = Reader(d, at = parts.bodyAt)
	kept = try r.keptRead()
	if r.at != parts.end: return none
	if keepRuntime: keptInMemory[key] = kept.copy()
	kept

# the kept stages put in prog, those of their std modules taken out of the loaded ones
fn takeKept(mut prog Program, move kept KeptStages, names str[]):
	typeIndex = move kept.index
	dropTypesSeen = dropTypesSeen or kept.drops
	prog.keptBodies = move kept.bodies
	prog.stages = move kept.stages
	prog.kept = move kept.checker
	prog.decls = prog.decls.filter(prog.nodes[it].mod() not in names)
	prog.modules = prog.modules.filter(.id not in names)

# After the check of the last of the stages, the checker's state kept when it may be: a stage of
# the runtime or of std, checked clean, with nothing of a body's check left open
fn keepStage(c Checker, stages CheckStage[]):
	stage = stages[len - 1]
	if stage.key == 0 or not keepsStages() or noting or c.errors > 0 or not c.leftClosed(): return
	path = stagePath(stage.name)
	if fs.readBytes(path) is d and d.unpack(keptMagic, keptVersion) is parts and
		d.keptFor(parts, stage.key):
		return
	body = c.keptBytes(stages) ?? return
	head = []
	head.pushU64le(compilerKey())
	head.pushU64le(stage.key)
	_ = fs.createDir(cachesDir)
	if placeFile(path, str(PackedParts.pack(keptMagic, keptVersion, head, body))) and
		keptWord().on():
		eprint("kept: wrote {stages.map(.name).join(" ")}")

# whether a kept file's head is this compiler's and key's
fn keptFor(d u8[], parts PackedParts, key i64):
	h = Reader(d, at = parts.headAt)
	h.i64() == compilerKey() and h.i64() == key and not h.short

# whether the checker holds nothing of a body's check (its scopes, lambdas, retypes, the errors
# held) and nothing a kept state leaves out (the shaders, the facts of the whole program)
fn leftClosed(c Checker):
	c.pending.isEmpty and c.failedGenerics.isEmpty and c.lamStack.isEmpty and
		c.retypes.isEmpty and c.rows.isEmpty and c.rowParams.isEmpty and c.walkLets.isEmpty and
		c.openBlocks.isEmpty and c.trials.isEmpty and c.letTrials.isEmpty and
		c.earlyResults.isEmpty and c.facts.isEmpty and not c.factsMade and not c.lentDone and
		c.subst.names.isEmpty and preparedShaders.isEmpty and c.scopeStarts.len == 1 and
		c.vars.isEmpty
