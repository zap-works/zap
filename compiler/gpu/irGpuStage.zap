# The stage values a lowered GPU program reads and writes (irGpu.zap).

import shader

alias nodes = w.c.nodes
alias tys = w.c.types

# the functions the one named `entry` calls, itself and on through them (their places)
fn reachedFns(prog GpuProgram, entry str):
	out = [prog.fns.findIndex(.name == entry) ?? fail("shader: no function {entry}")]
	i = 0
	while i < out.len:
		for b in prog.fns[out[i]].f.blocks:
			for inst in b.insts:
				if inst.op == irCall:
					k = prog.fns.findIndex(.name == inst.key()) ??
						fail("shader: no function {inst.key()}")
					if k not in out:
						out.push(k)
		i += 1
	out

# the name of the variable a value passed on goes by (zapB_<field>, zapB alone)
fn passedName(field str):
	"zapB" if field == "" else "zapB_{field}"

# the length of the array a stage reads by name: a parameter's, a texture array's (0: as many as
# the RHI binds), a storage buffer's (0)
fn arrayLength(l shader.Lowering, name str):
	if l.params.find(.name == name) is p: return p.arr
	if l.resources.find(.name == name) is r and r.kind == shader.resArray:
		return l.arrays[r.binding].count
	0

# Each texture array without a length that the functions read only at literal indices given the
# length past the last of them: an array of that many needs no descriptor indexing (a device of
# Vulkan 1.1, or 1.2 without it, binds it).
fn sizeLiteralArrays(mut l shader.Lowering, prog GpuProgram, fns i64[]):
	for r in l.resources:
		if r.kind != shader.resArray or l.arrays[r.binding].count != 0: continue
		most = 0
		for f in fns:
			g = prog.fns[f]
			defs = g.f.spvVregDefs(g.tys.len)
			for b in g.f.blocks:
				for inst in b.insts:
					if inst.op != irStageIn or inst.key != r.name: continue
					index = g.f.literalOf(defs, inst.b) ?? -1
					most = -1 if index < 0 or most < 0 else most.max(index + 1)
		if most > 0:
			l.arrays[r.binding].count = most

# the value of vreg v when one irConst alone gives it
fn literalOf(f IrFn, defs i64[], v i64) i64?:
	if v < 0 or defs[v] != 1: return none
	for b in f.blocks:
		for inst in b.insts:
			if inst.dst == v: return inst.imm if inst.op == irConst else none
	none

# What the stage's functions read or write where it is (irStageIn, irStageOut), each name its
# whole value's type (an array's when an element is reached).
fn stageReads(prog GpuProgram, fns i64[], l shader.Lowering):
	read {str: shader.Ty} = {}
	for f in fns:
		g = prog.fns[f]
		for b in g.f.blocks:
			for inst in b.insts:
				if inst.op != irStageIn and inst.op != irStageOut or inst.key() in read: continue
				if prog.groupMemory.get(inst.key()) is t:
					read[inst.key().copy()] = t
					continue
				t = g.tys[inst.dst if inst.op == irStageIn else inst.a]
				if inst.b >= 0:
					t = t.arrayOf(l.arrayLength(inst.key()))
				read[inst.key().copy()] = t
	read

# the storage buffers the functions write (a compute stage's)
fn stageWrites(prog GpuProgram, fns i64[]):
	out str[] = []
	for f in fns:
		for b in prog.fns[f].f.blocks:
			for inst in b.insts:
				if inst.op == irStageOut and inst.key().startsWith("zapP") and
					inst.key() not in out:
					out.push(inst.key().copy())
	out

fn stageName(stage i64):
	["vertex", "pixel", "compute"][stage].copy()

# What the stage's code reaches that only a stage of another kind has is the error that stops
# the compile: the pixel's position and discard() a pixel stage's, a compute stage's values,
# group memory, barrier() and writes.
fn checkStageValues(c Checker, prog GpuProgram, stage i64, entry str) ? shader.GpuError:
	for f in prog.reachedFns(entry):
		g = prog.fns[f]
		for b in g.f.blocks:
			for inst in b.insts:
				only = -1
				what = ""
				if inst.op == irStageIn and gpuValues.find(.name == inst.key()) is v:
					only = v.stage
					what = "'{inst.key()}'"
				elif inst.op == irStageIn and inst.key().startsWith("zapW_") or
					inst.op == irStageOut:
					only = shader.stageCompute
					what = "memory written where it is"
				elif inst.op == irBarrier:
					only = shader.stageCompute
					what = "barrier()"
				elif inst.op == irDiscard:
					only = shader.stageFragment
					what = "discard()"
				if only >= 0 and only != stage:
					return stopAt(
						c.nodes[g.decl].file(c.kidIds),
						inst.line,
						inst.col,
						compileError(
							"GpuStageOnly",
							["{what}", "{stageName(only)}", "{stageName(stage)}"]
						)
					)
