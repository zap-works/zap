# `zap build --loadable`: a build another build of the same program loads while it runs
# (runtime/core/loaded.zap's loadBuild), sharing its state. Its code reaches the state (the global
# slots and the module variables) as any build's does; the `.load` file beside the executable lists
# those references, so the loader leads each to the running program's, and names the entry with
# the system's convention that calls the build's main. Both builds must lay the state out alike:
# each writes the hash of its layout in a global slot, and the loader refuses a build whose hash
# is not the program's.

import fs

alias nodes = g.c.nodes
alias tys = g.c.types

# whether this build is one a program loads (zap build --loadable)
mut loadableBuild = false

# the global slots of the runtime that hold the state's layout hash and the address of the
# module variables (runtime/core/core.zap's map)
layoutSlot = 14
moduleVariablesSlot = 15

# the bytes of the global slots (genX64's first data)
globalSlotsSize = 64 * 8

# the entry of a loadable build: main called with the system's convention, planned when new
fn loadableEntry(mut g Gen, entry str) i64:
	g.callbackLabel(entry, tyFn(g.c.types, [], none))

# The module variables' places and types, a line each, in their order: what a build that loads
# another and the one it loads must have alike (and a live swap, live.zap)
fn stateLayout(mut g Gen):
	out = []
	for d in g.c.decls:
		if g.hasStorage(d):
			name = nodes[d].text.copy()
			out.push("var {name} {g.globalOffs.get(name) ?? -1} {typeKey(tys, g.c.constTypeOf(d))}")
	out

# the layout's hash written in its global slot: the loader compares the two builds'
fn writeLayoutHash(mut g Gen):
	patch64(g.a.data, g.globalsOff + layoutSlot * 8, g.stateLayout().join("\n").hash())

# The `.load` file beside a loadable build's executable: "ZLOD", the layout hash (8 bytes), the
# entry's RVA, the count of references, then each reference as two little-endian u32: the RVA of
# its 32-bit displacement and its place in the state (bit 31 set: an offset among the module
# variables; clear: an offset in the global slots).
fn writeLoadFile(mut g Gen, exePath str, entryLabel i64):
	out = []
	bytesPutStr(out, "ZLOD")
	bytesPut64(out, g.stateLayout().join("\n").hash())
	bytesPut32(out, sectRva + g.a.labelPos[entryLabel])
	at = out.len
	bytesPut32(out, 0)
	count = 0
	for i, kind in g.a.fixKind:
		if kind != fxData: continue
		target = g.a.fixTarget[i]
		place = -1
		if target >= bssBase: place = (1 << 31) | (target - bssBase)
		elif target >= g.globalsOff and target < g.globalsOff + globalSlotsSize:
			place = target - g.globalsOff
		if place < 0: continue
		bytesPut32(out, sectRva + g.a.fixAt[i])
		bytesPut32(out, place)
		count += 1
	patch32(out, at, count)
	fs.writeBytes("{exePath}.load", out) ?? exit(1, "zap: cannot write {exePath}.load: {error}")
