# What a cartridge's recompilation is told besides the ROM: where it is read and written, the
# tables that seed the flow (cfg.zap), and what the program written imports, runs at its start
# and translates otherwise than the cartridge has it (its patches). A game project fills one and
# calls prepareGame (prepare.zap).

pub type Game:
	name str   # the program's: <recompDir>/<name>.zap
	romPath str   # the player's dump, read at the program's start too
	recompDir str
	tablesDir str = ""   # the per-bank cfg; none: the flow starts at the vectors alone
	imports str[] = []   # modules the program imports besides recomp.snes's console and cpu
	setup str[] = []   # lines the entry runs before the screen opens (a game's hooks installed)
	patches Patch[] = []
	presets str[] = []   # the presentation the program starts with (console/presets.zap)

# An instruction translated otherwise than the cartridge has it, for a game's presentation (a
# widescreen's windows), never its logic. Each names the instruction it changes and stops the
# preparation when the cartridge has no such instruction, so a table that no longer matches it is
# never half applied.
pub type Patch:
	# the 16-bit immediate `literal`, found exactly once in the block from the instruction at
	# `from` to the next label or branch, written as `call(value)`
	Immediate(from i64, literal i64, call str)
	# the value an instruction reads from memory written as `text`, `{operand}` in it the read
	# (kept, so the access and its cycles stay the cartridge's)
	Operand(at i64, name str, text str)
	# the carry a shift takes written as `text`, `{old}` in it the value shifted
	Carry(at i64, name str, text str)
	# lines run after the instruction
	After(at i64, name str, lines str[])
	# before the instruction: `if condition:` the function goes on at its label at `label`
	RetryBefore(at i64, name str, condition str, label i64)

	# the instruction it is for, after the immediates are found
	fn address():
		match self:
			Immediate(from, _, _): from
			Operand(at, _, _): at
			Carry(at, _, _): at
			After(at, _, _): at
			RetryBefore(at, _, _, _): at

# The patches by the address of the instruction each changes, the immediates found: a patch
# that names no instruction of the functions stops the preparation.
pub fn resolvePatches(functions Function[], patches Patch[]) {i64: Patch}:
	out {i64: Patch} = {}
	for p in patches:
		if p is Immediate(from, literal, call):
			found = immediatesIn(functions, from, literal)
			if found.len != 1:
				fail("patch table: {found.len} immediates {literal:X} from 0x{from:06X}")
			out[found[0]] = .Immediate(found[0], literal, call.copy())
			continue
		name = match p:
			Operand(_, n, _): n
			Carry(_, n, _): n
			After(_, n, _): n
			RetryBefore(_, n, _, _): n
			Immediate: ""
		if not hasInstruction(functions, p.address(), name):
			fail("patch table: no {name} at 0x{p.address():06X}")
		out[p.address()] = p.copy()
	out

fn hasInstruction(functions Function[], at i64, name str):
	for f in functions:
		for i in f.instrs:
			if i.at == at and i.name == name: return true
	false

# the addresses of the 16-bit immediates of `literal` in the block from the instruction at
# `from`, up to its first branch or label
fn immediatesIn(functions Function[], from i64, literal i64):
	found {i64: bool} = {}
	for f in functions:
		for k, i in f.instrs:
			if i.at == from: f.collect(k, literal, found)
	found.keys().sorted()

fn collect(f Function, k i64, literal i64, mut found {i64: bool}):
	j = k
	while j < f.instrs.len:
		i = f.instrs[j]
		if j > k and i.keyOf() in f.labels: return
		if isImmediate(i.mode) and i.size == 3 and i.value == literal: found[i.at] = true
		if not i.fallsThrough() or i.name in conditionalBranches: return
		j += 1
