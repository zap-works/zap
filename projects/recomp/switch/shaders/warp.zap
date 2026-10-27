# The instructions of a warp's lanes and the special registers (fields as yuzu's warp_shuffle.cpp,
# vote.cpp and move_special_register.cpp read them): S2R, SHFL, VOTE. A Maxwell warp runs 32
# lanes: a lane's index is Zap's `lane` (a compute stage's) or the lanes before it that run, its
# low five bits; a ballot the lanes' bits summed.

# the lane's index among the warp's 32
fn laneId(e Emitter) str:
	"(u32(lane) & 31)" if e.stage == .Compute else "maxwell.laneIndex()"

# S2R: the lane and its masks, a compute stage's thread and group ids, the y direction (1.0: the
# renderer gives the picture's y downward as the guest's); any other the 0 the hardware gives
# where yuzu stubs it (the invocation, a thread killed, the clock...)
pub fn emitS2r(mut e Emitter, i Instr):
	sr = i.field(20, 8)
	bit = "(u32(1) << {e.laneId()})"
	value = match sr:
		0: e.laneId()
		18: "0x3F80_0000"
		32: "u32(localId.x) | u32(localId.y) << 16 | u32(localId.z) << 26"
		33..36: "u32(localId.{components[sr - 33]})"
		37..40: "u32(groupId.{components[sr - 37]})"
		56: bit.copy()
		57: "{bit} - 1"
		58: "({bit} << 1) - 1"
		59: "~(({bit} << 1) - 1)"
		60: "~({bit} - 1)"
		_: "0"
	if sr >= 32 and sr < 40 and e.stage != .Compute:
		e.lack(i, "special register {sr} outside a compute stage", [i.rd])
		return
	e.set(i.rd, value)

# SHFL: A from the lane that the mode, the index (B: a register, or 5 bits at 20 when bit 28) and
# the clamp and segment mask (C: a register, or 13 bits at 34 when bit 29) give, A itself when it
# lies outside the segment; the predicate at 48 whether it lay inside
pub fn emitShfl(mut e Emitter, i Instr):
	index = "{i.field(20, 5)}" if i.flag(28) else e.x(i.field(20, 8))
	mask = "{i.field(34, 13)}" if i.flag(29) else e.x(i.field(39, 8))
	e.line("source = maxwell.shuffleSource({index}, {mask}, {i.field(30, 2)}, {e.laneId()})")
	a = e.x(i.ra)
	e.line("shuffled = {a}.laneAt(source.max(0))")
	e.set(i.rd, "shuffled if source >= 0 else {a}")
	e.setP(i.field(48, 3), "source >= 0")

# VOTE: ALL, ANY or EQ of the predicate at 39 (negated by 42) into the predicate at 45; the ballot
# (each lane's predicate a bit) into rd
pub fn emitVote(mut e Emitter, i Instr):
	p = e.pred(i.field(39, 3), i.flag(42))
	vote = match i.field(48, 2):
		0: "{p}.laneAll()"
		1: "{p}.laneAny()"
		2: "({p}.laneAll() or not {p}.laneAny())"
		_: "false"
	e.setP(i.field(45, 3), vote)
	if i.rd != rz: e.set(i.rd, "(maxwell.bit({p}) << {e.laneId()}).laneSum()")
