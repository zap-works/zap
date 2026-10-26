# An instruction's bus cycles in the order Mesen 2's 65816 makes them, which the translation emits
# around what the instruction does so the console's clock and hardware run through each: the
# fetches of its opcode and operand (as fast as the code's bank), the internal cycles of its kind,
# then its data's reads and writes. The cycles that depend on the values the code runs with are
# the cpu module's (the direct page off a page boundary, a page crossed by an index, each access as
# long as where it lands); those between a read and a write, or after them, are emitted with the
# operation (emit.zap, emitOps.zap).

readModifyWrite = ["inc", "dec", "asl", "lsr", "rol", "ror", "tsb", "trb"]
pushes = ["pha", "phx", "phy", "php", "phb", "phk", "phd"]
pulls = ["pla", "plx", "ply", "plp", "plb", "pld"]
returns = ["rts", "rtl", "rti"]

# The cycles before the operation: the fetches, then the internal cycles of an implied
# instruction (a read of the code instead when an interrupt is about to come), of a push, a pull,
# a return, rep and sep, a call and a long branch; jsl and jsr (a,x) fetch between their pushes,
# mvn and mvp each byte (cpu.moveBlock).
pub fn leadCycles(i Instr) str[]:
	if i.name == "mvn" or i.name == "mvp": return []
	at = i.atText()
	fetches = 3 if i.name == "jsl" else 2 if i.name == "jsr" and i.mode == "(w,x)" else i.size
	out = ["console.fetch({fetches}, {at})"]
	idles = 0
	if i.name in ["rep", "sep", "jsr", "brl", "per"] or i.name in pushes: idles = 1
	if i.name in returns or i.name in pulls: idles = 2
	if i.mode == "(w,x)": idles = 1 if i.name == "jmp" else 0
	if i.isImplied():
		out.push("console.idleOrRead({at})")
		if i.name == "xba": idles = 1
	loop idles:
		out.push("console.idle()")
	out

# whether its second cycle is the implied one (Mesen's IdleOrRead): no operand, no stack, no flow
fn isImplied(i Instr):
	if not (i.mode.isEmpty or i.mode == "A"): return false
	not (i.name in pushes or i.name in pulls or i.name in returns or i.name == "wai")

# whether the instruction only reads its operand: an 8-bit index then costs an internal cycle
# only where it crosses a page
pub fn readsOnly(i Instr) bool:
	not (i.name.startsWith("st") or i.name in readModifyWrite)

# whether a taken branch crosses a page in emulation mode: an internal cycle more
pub fn crossesPage(i Instr) bool:
	i.widths.e and (i.target() ^ i.next()) & 0xFF00 != 0
