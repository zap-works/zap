# The instructions that read and write a stage's attributes, the constant buffers, local and
# shared memory and the special registers (yuzu's load_store_attribute.cpp, load_constant.cpp,
# load_store_local_shared.cpp, move_special_register.cpp): ALD, AST, IPA, LDC, LDL, STL, LDS, STS,
# S2R, BAR. A vertex stage's generic attribute g is `v.g<g>` (a Vec4), what it passes on the
# locals `o<attribute>`, made into the result at EXIT; a pixel stage reads `b.g<g>`.

import recomp.switch.arm64

components = ["x", "y", "z", "w"]

pub fn emitAld(mut e Emitter, i Instr):
	if e.stage != .Vertex:
		e.lack(i, "ALD in a {e.stage} stage", [i.rd])
		return
	if i.ra != rz or i.flag(31) or i.flag(32):
		e.lack(i, "an indexed, patch or output attribute read", [i.rd])
		return
	for k in 0..=i.field(47, 2):
		a = i.field(20, 10) / 4 + k
		value = e.attributeIn(a) ?? ""
		if value == "":
			e.lack(i, "vertex attribute {a}", [i.rd + k])
		else:
			e.set(i.rd + k, value)

# a vertex stage's input attribute as u32 bits, none when Zap gives the stage no such value
fn attributeIn(mut e Emitter, a i64) str?:
	g = a - generic0
	if g >= 0 and g < 128:
		if g / 4 not in e.inputs: e.inputs.push(g / 4)
		return "v.g{g / 4}.{components[g % 4]}.toBits()"
	if a == vertexId or a == instanceId:
		if a not in e.inputs: e.inputs.push(a)
		return "u32(id)" if a == vertexId else "u32(instance)"
	none

pub fn emitAst(mut e Emitter, i Instr):
	if e.stage != .Vertex:
		e.lack(i, "AST in a {e.stage} stage", [])
		return
	if i.ra != rz or i.flag(31):
		e.lack(i, "an indexed or patch attribute write", [])
		return
	for k in 0..=i.field(47, 2):
		a = i.field(20, 10) / 4 + k
		if a < positionX or a >= generic0 + 128:
			e.lack(i, "output attribute {a} (point size, clip distances, layer...)", [])
			continue
		g = a - generic0
		if g >= 0 and g / 4 not in e.interface:
			e.line("_ = {e.f(i.rd + k)}")
			continue
		if a not in e.outputs: e.outputs.push(a)
		e.line("o{a} = {e.f(i.rd + k)}")

# IPA: an attribute interpolated for the pixel. A perspective one comes as the value times the
# position's w (1 / clip w): the program multiplies it back (yuzu's reading).
pub fn emitIpa(mut e Emitter, i Instr):
	if e.stage != .Pixel or (i.flag(38) and i.ra != rz):
		e.lack(i, "an IPA outside a pixel stage or indexed", [i.rd])
		return
	a = i.field(30, 8)
	g = a - generic0
	value = ""
	if a >= positionX and a < generic0:
		value = "pixelPosition.{components[a - positionX]}"
	elif g >= 0 and g < 128:
		value = "b.g{g / 4}.{components[g % 4]}" if g / 4 in e.interface else "0.0"
		if e.header is h and h.pixelMode(g) == 2: value = "{value} * pixelPosition.w"
	else:
		e.lack(i, "attribute {a} (front face, point coordinates...)", [i.rd])
		return
	if i.field(54, 2) == 1: value = "{value} * {e.f(i.field(20, 8))}"
	e.setF(i.rd, saturated(value, i.flag(51)))

# LDC: constant buffer `bank` (36) at A + a signed 16-bit offset; 8 and 16-bit reads extracted
pub fn emitLdc(mut e Emitter, i Instr):
	size = i.field(48, 3)
	if i.field(44, 2) != 0 or size > 5:
		e.lack(i, "LDC mode {i.field(44, 2)} or size {size}", [i.rd])
		return
	bank = i.field(36, 5)
	offset = arm64.signedBits(i.word, 20, 16)
	if i.ra != rz: e.line("address = {e.x(i.ra)} + {offset & 0xFFFF_FFFF}")
	dynamic = i.ra != rz
	if size == 5:
		e.set(i.rd, e.ldcWord(bank, dynamic, offset, 0))
		e.set(i.rd + 1, e.ldcWord(bank, dynamic, offset, 1))
	elif size == 4:
		e.set(i.rd, e.ldcWord(bank, dynamic, offset, 0))
		if not dynamic and i.rd != rz: e.known[i.rd] = Known(bank, word = offset / 4)
	else:
		width = 8 if size < 2 else 16
		shift = "(address & 3) * 8" if dynamic else "{(offset & 3) * 8}"
		value = e.ldcWord(bank, dynamic, offset, 0)
		e.set(i.rd, "maxwell.extractBits({value}, {shift}, {width}, {size % 2 == 1})")

# word k of an LDC's read: at `address` when the address is a register's
fn ldcWord(mut e Emitter, bank i64, dynamic bool, offset i64, k i64):
	if not dynamic: return e.constant(bank, "{offset / 4 + k}")
	e.constant(bank, "i32(address >> 2) + {k}" if k > 0 else "i32(address >> 2)")

# local memory (LDL, STL): `local`, words of the thread; shared (LDS, STS): the group's `shared`
pub fn emitLoadStore(mut e Emitter, i Instr):
	isShared = i.op == .Lds or i.op == .Sts
	isStore = i.op == .Stl or i.op == .Sts
	if isShared and e.stage != .Compute:
		e.lack(i, "shared memory in a {e.stage} stage", [] if isStore else [i.rd])
		return
	size = i.field(48, 3)
	if size < 4:
		e.lack(i, "an 8 or 16-bit access", [] if isStore else [i.rd])
		return
	words = [1, 2, 4, 4][size - 4]
	offset = arm64.signedBits(i.word, 20, 24)
	at = "{offset / 4}" if i.ra == rz else "i32(({e.x(i.ra)} + {offset & 0xFFFF_FFFF}) >> 2)"
	memory = "shared{e.name}" if isShared else "local"
	reach = (offset / 4 + words) if i.ra == rz else 0
	if isShared:
		e.sharedWords = e.sharedWords.max(reach)
	else:
		e.localWords = e.localWords.max(reach)
	for k in 0..words:
		place = "{memory}[{at} + {k}]" if k > 0 else "{memory}[{at}]"
		if isStore:
			e.line("{place} = {e.x(i.rd + k)}")
		else:
			e.set(i.rd + k, place)

# S2R: the compute stage's thread and group ids, the lane; others are not translated
pub fn emitS2r(mut e Emitter, i Instr):
	sr = i.field(20, 8)
	value = match sr:
		0: "u32(lane)"
		32: "u32(localId.x) | u32(localId.y) << 16 | u32(localId.z) << 26"
		33..36: "u32(localId.{components[sr - 33]})"
		37..40: "u32(groupId.{components[sr - 37]})"
		_: ""
	if value == "" or (sr >= 32 and e.stage != .Compute):
		e.lack(i, "special register {sr}", [i.rd])
		return
	e.set(i.rd, value)

pub fn emitBar(mut e Emitter, i Instr):
	if e.stage != .Compute:
		e.lack(i, "BAR outside a compute stage", [])
		return
	e.line("barrier()")
