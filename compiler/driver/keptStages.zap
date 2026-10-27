# The stages kept checked (spec 14.2), as Rust keeps a crate's rlib and Go its export data: once
# a build checks a stage of the runtime, of std or of a module the program imports (stages.zap),
# what the checker then holds (its nodes, declarations, modules, instances, types and the tables
# the stages after it and the backend read, keptState.zap) is written to build/cache/, a file per
# stage (stagePath), under the stage's key: the compiler's key, the target, the stage's sources
# and the key of the stage before it. A build whose stages begin with a kept chain reads the last
# state of it back and checks only the stages after it, the checker where it would be had it
# checked those, so the executable is the same byte for byte. A zap answering a test's requests
# keeps the states of the runtime and std it read in memory (keepRuntime).

import fs

keptMagic = "ZKST"
keptVersion = 7

# what a kept file holds: the checker after its stages, the types' index, the bodies kept of
# functions with number parameters, whether a drop function was declared and the bodies that
# wait in it
type KeptStages:
	checker Checker
	stages CheckStage[]
	index {i64: TypeId}
	bodies {NodeId: NodeId}
	drops bool
	waiting WaitingBodies

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

# the stages of the runtime's dirs, of the std modules and of the program's other modules, before
# the entry's, each with its key: the one before it, its name, its sources' names and texts (an own
# module's also its dir, which its nodes name) and the packers the shaders' link adopted into it
fn stageChain(rtDir str, dirs str[], modules Module[]):
	out CheckStage[] = []
	key = "{compilerKey()}\n{targets[buildTarget].name}".hash()
	sources = runtimeSources(rtDir)
	for d in dirs:
		key = stageKey(key, "rt/{d}", rtDir, sources.filter(runtimeDirOf(it) == d))
		file = out.stageFileAfter("rt/{d}")
		out.push(CheckStage(name = "rt/{d}", decls = 0, modules = 0, key, file))
	for m in modules:
		if not m.isStdStage(): continue
		dir = fs.dirOf(m.file)
		files = fs.walk(dir, sources = true).map(it[dir.len + 1..].copy())
		key = stageKey(key, m.id, "{dir}/", files).withPackers(m.id)
		file = out.stageFileAfter(m.id)
		out.push(CheckStage(name = m.id.copy(), decls = 0, modules = 0, key, file))
	for m in modules:
		if not m.isOwnStage(): continue
		dir, files = m.ownModuleSources()
		key = stageKey(key, "{m.id}\n{dir}", dir, files).withPackers(m.id)
		file = "mod-{m.id}-{"{out.map(.name).join(" ")}\n{dir}".hash() & 4_294_967_295:x}"
		out.push(CheckStage(name = m.id.copy(), decls = 0, modules = 0, key, file))
	out

# the dir an own module's sources are below, as the program spells it, and their paths below it:
# every source under its dir; of a module that is one file beside the program (moduleSources),
# that file, its parts and its system's dirs
fn ownModuleSources(m Module):
	dir = dirPrefix(m.file)
	if dir.endsWith("{m.id.replace(".", "/")}/"):
		return (dir, fs.walk(dir[..len - 1], sources = true).map(it[dir.len..].copy()))
	files = withParts([m.file.copy()])
	for sys in systemDirsOf("{m.file[..len - 4]}/"):
		files.extend(moduleFiles(sys).map("{sys}{it}"))
	(dir, files.map(it[dir.len..].copy()))

# the file the stage name is kept in after the stages before: one a chain of stages' names, so
# programs that reach other dirs before it keep their own (the first stage's its name alone)
fn stageFileAfter(before CheckStage[], name str):
	if before.isEmpty: return stageFile(name)
	"{stageFile(name)}-{before.map(.name).join(" ").hash() & 4_294_967_295:x}"

# the key of a stage after the one keyed `before`: its name and its files below dir, their names
# and texts
fn stageKey(before i64, name str, dir str, files str[]):
	lines = ["{before}", name.copy()]
	for f in files.sorted():
		hash = fileHash("{dir}{f}")
		noteSourceRead("{dir}{f}", i64.parse(hash) ?? 0)   # (the run's stamp and the compiler's key name it)
		lines.push("{f}\t{hash}")
	lines.join("\n").hash()

# a module's stage key after the packers adopted into it, which calls of other modules may add
fn withPackers(key i64, module str):
	lines = ["{key}"]
	for (m, name, hash) in packersAdopted:
		if m == module: lines.push("{name}\t{hash}")
	key if lines.len == 1 else lines.join("\n").hash()

# where a stage is kept: a file of build/cache/ named by the stage and those before it
# (stageFileAfter) and the target, holding the last chain written that ends with it
fn stagePath(stage CheckStage):
	keptPath(stage.file if stage.file != "" else stageFile(stage.name))

fn keptPath(base str):
	"{cachesDir}/{base}{targetTag()}"

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
# chain its key names; those ending with the runtime or std held in memory for the next programs
fn keptStages(stage CheckStage) KeptStages?:
	key = stage.key
	if keptInMemory.get(key) is known: return known.copy()
	d = fs.readBytes(stage.stagePath()) ?? return none
	parts = try d.unpack(keptMagic, keptVersion)
	if not d.keptFor(parts, key): return none
	r = Reader(d, at = parts.bodyAt)
	kept = try r.keptRead()
	if r.at != parts.end: return none
	kept.waiting.bytes = move d
	if keepRuntime and not stage.file.startsWith("mod-"): keptInMemory[key] = kept.copy()
	kept

# the kept stages put in prog, their modules taken out of the loaded ones
fn takeKept(mut prog Program, move kept KeptStages, names str[]):
	typeIndex = move kept.index
	dropTypesSeen = dropTypesSeen or kept.drops
	prog.keptBodies = move kept.bodies
	prog.keptWaiting = move kept.waiting
	prog.stages = move kept.stages
	prog.kept = move kept.checker
	prog.decls = prog.decls.filter(prog.nodes[it].mod(prog.kidIds) not in names)
	prog.modules = prog.modules.filter(.id not in names)

# After the check of the last of the stages, the checker's state kept when it may be: a stage of
# the runtime, std or an imported module, checked clean, with nothing of a body's check left open
fn keepStage(mut c Checker, stages CheckStage[]):
	stage = stages[len - 1]
	if stage.key == 0 or not keepsStages() or noting or c.errors > 0 or not c.leftClosed(): return
	path = stage.stagePath()
	if fs.readBytes(path) is d and d.unpack(keptMagic, keptVersion) is parts and
		d.keptFor(parts, stage.key):
		return
	c.readBodies()   # (the stages before it may have kept theirs waiting)
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
