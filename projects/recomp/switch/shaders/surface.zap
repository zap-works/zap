# The surface instructions translated (yuzu's surface_load_store.cpp and
# surface_atomic_operations.cpp): SULD and SUST read and write a 2D surface's texel by integer
# coordinates, SUATOM and SURED change it by an atomic. A surface is a UintImage, a field of
# Params by its slot (imageField), so of one 32-bit number a texel (R32UI): a load or store of more
# components, of a 1D, layered or 3D surface, a clamp, and the atomics Zap has not (INC, DEC, a
# signed MIN or MAX, CAS) are noted missing.

# the 2D type of SULD, SUST, SUATOM and SURED's field 33 (1D, a 1D buffer, a 1D array, 2D...)
surface2D = 3

# The surface an instruction names: its slot's field for a bound one (`bound`: field 36's
# handle), for a bindless one the constant buffer word its register (39) was loaded from when
# the code shows it; none (noted missing) for another type, a clamp, or an unknown handle.
fn surfaceOf(mut e Emitter, i Instr, bound bool, zeroed i64[]) str?:
	if i.field(33, 3) != surface2D or i.field(49, 2) != 0:
		e.lack(i, "{i.op} of type {i.field(33, 3)} (not 2D), or clamped", zeroed)
		return none
	if bound: return e.textureOf(i.field(36, 13), .Image)
	if e.known.get(i.field(39, 8)) is k and k.bank >= 0: return e.textureOf(k.word, .Image, k.bank)
	e.lack(i, "{i.op}: a bindless handle not known when translating", zeroed)
	none

# a 2D texel's coordinates from register c on
fn surfaceTexel(mut e Emitter, c i64):
	"IVec2(i32({e.x(c)}), i32({e.x(c + 1)}))"

# whether a load or store moves one 32-bit number: SULD.D/SUST.D of size B32 (4), or .P of the
# red component alone (swizzle 1)
fn oneNumber(i Instr):
	i.field(20, 3) == 4 if i.flag(52) else i.field(20, 4) == 1

# SULD: the texel's number into rd
pub fn emitSuld(mut e Emitter, i Instr):
	if not i.oneNumber():
		e.lack(i, "SULD of more than one 32-bit number (Zap's UintImage holds one)", [i.rd])
		return
	image = e.surfaceOf(i, i.flag(51), [i.rd]) ?? return
	e.set(i.rd, "{image}.load({e.surfaceTexel(i.ra)}).x")

# SUST: rd's number into the texel
pub fn emitSust(mut e Emitter, i Instr):
	if not i.oneNumber():
		e.lack(i, "SUST of more than one 32-bit number (Zap's UintImage holds one)", [])
		return
	image = e.surfaceOf(i, i.flag(51), []) ?? return
	e.line("{image}.store({e.surfaceTexel(i.ra)}, UVec4({e.x(i.rd)}, 0, 0, 0))")

# the atomics of SUATOM's field 29 and SURED's 24 (ADD, MIN, MAX, INC, DEC, AND, OR, XOR, EXCH) as
# UintImage's, "" for one Zap has not
fn atomicOf(op i64, signed bool):
	if (op == 1 or op == 2) and signed or op == 3 or op == 4 or op > 8: return ""
	[
		"atomicAdd",
		"atomicMin",
		"atomicMax",
		"",
		"",
		"atomicAnd",
		"atomicOr",
		"atomicXor",
		"atomicExchange"
	][op]

# SUATOM (sizes U32 and S32 at 51): the texel changed by B's number, what it held into rd
pub fn emitSuatom(mut e Emitter, i Instr):
	size = i.field(51, 3)
	m = atomicOf(i.field(29, 4), size == 1)
	if size > 1 or m == "":
		e.lack(i, "SUATOM {i.field(29, 4)} of size {size} (INC, DEC, a signed MIN or MAX, 64 bits, floats)", [i.rd])
		return
	image = e.surfaceOf(i, not i.flag(54), [i.rd]) ?? return
	e.set(i.rd, "{image}.{m}({e.surfaceTexel(i.ra)}, {e.x(i.field(20, 8))})")

# SURED: the texel changed by rd's number (what it held left), its fields as yuzu reads them
pub fn emitSured(mut e Emitter, i Instr):
	size = i.field(20, 3)
	m = atomicOf(i.field(24, 3), size == 1)
	if size > 1 or m == "":
		e.lack(
			i,
			"SURED {i.field(24, 3)} of size {size} (INC, DEC, a signed MIN or MAX, 64 bits, floats)",
			[]
		)
		return
	image = e.surfaceOf(i, i.flag(51), []) ?? return
	e.line("_ = {image}.{m}({e.surfaceTexel(i.ra)}, {e.x(i.rd)})")
