# The stages a program is checked in (spec 14.2): each dir of the runtime it loads (core first,
# then each after the dirs it reads), each std module after those it imports, each module of the
# program's own after those it imports, then the entry file's module, each stage checked alone
# after those before it, so its types and declarations are numbered as they would be whatever
# comes after it. A module is a stage of its own, as a std module is, not a level of the imports
# (which would check its other modules again on an edit of one): an edit checks again the stages
# from the module edited on, and programs whose imports begin alike (the recompiled parts' cpu and
# arm64 modules before their own) share the stages that begin them.

# the declarations and modules loaded after those of the stages already put (or kept checked) put
# in their stages, each with its key: those of the runtime's dirs in the order the loader put
# them, the std modules' then the program's other modules' in their modules' order (each after
# those it imports), then the rest, the entry's
fn orderStages(mut prog Program):
	declsAt = 0
	modulesAt = 0
	if prog.stages.filter(not .done).last is s:
		declsAt = s.decls
		modulesAt = s.modules
	modules = prog.modules[modulesAt..].copy()
	decls = prog.decls[declsAt..].copy()
	prog.modules.truncate(modulesAt)
	prog.decls.truncate(declsAt)
	of = decls.map(stageOf(prog.nodes, modules, prog.stageKeys, it))
	names str[] = []
	for name in of:
		if name.startsWith("rt/") and name not in names: names.push(name.copy())
	for m in modules:
		if m.isStdStage(): names.push(m.id.copy())
	for m in modules:
		if m.isOwnStage(): names.push(m.id.copy())
	names.push("")
	for name in names:
		for m in modules:
			if m.moduleStage(name, names): prog.modules.push(m.copy())
		for i, d in decls:
			if of[i] == name: prog.decls.push(d)
		prog.stages.push(
			CheckStage(
				name.copy(),
				prog.decls.len,
				prog.modules.len,
				key = prog.stageKeys.get(name) ?? 0,
				file = (prog.stageFiles.get(name) ?? "").copy()
			)
		)

# the stage of declaration d: its runtime dir's, its module's, else the entry's ("", with what the
# linker writes into the runtime)
fn stageOf(nodes Node[], modules Module[], keys {str: i64}, d NodeId):
	id = nodes[d].mod()
	if id == "rt":
		dir = "rt/{runtimeDirOf(nodes[d].file())}"
		return dir if dir in keys else ""
	if modules.find(.id == id) is m and m.isStage(): return id.copy()
	""

# whether module m is checked in a stage of its own: a module the program imports
fn isStage(m Module):
	not m.unit and m.id != "" and m.id != "derive" and m.id != "rt"

fn isStdStage(m Module):
	m.std and m.isStage()

fn isOwnStage(m Module):
	not m.std and m.isStage()

# whether module m goes in the stage named name: rt with the first of the runtime's, an imported
# module in its own, the others in the entry's
fn moduleStage(m Module, name str, names str[]):
	if m.id == "rt": return name == names[0]
	if m.isStage(): return name == m.id
	name == ""
