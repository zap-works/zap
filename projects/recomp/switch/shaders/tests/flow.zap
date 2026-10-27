# Control flow rebuilt from hand-written programs (words as deko3d's compiler writes them, the
# jumps' offsets from yuzu's control_flow.cpp): a PBK/BRK loop, an SSY/SYNC if-else, a jump the
# structure cannot hold.

import recomp.switch.shaders

fn word(w u64) i64:
	i64.wrap(w)

# the compute program of these words translated: its entry's lines, or why not
fn translated(words u64[]):
	t = shaders.newTable()
	p = shaders.Program(stage = .Compute, header = none, words = words.map(word(it)), start = 0)
	s = t.translateProgram(p, "Test", [], [1, 1, 1]) ?? return error
	lines = s.text.lines()
	at = lines.indexOf("pub fn computeTest(p Params):") ?? return s.text
	lines[at + 1..].filter(not .isEmpty and not .endsWith(" u32 = 0")).join("\n")

test "PBK, a BRK by a predicate and a jump back: a loop with a break":
	print(translated([
		0xE2A0_0000_0280_000F,   # PBK 0x38
		0x3858_103F_8007_0000,   # FADD R0, R0, 1.0
		0x4BBD_8388_0037_0007,   # FSETP.NEU P0, PT, R0, c[0x2][0xc], PT
		0xE340_0000_0000_000F,   # @P0 BRK
		0xE240_0FFF_FD87_000F,   # BRA 0x10
		0xE300_0000_0007_000F    # EXIT
	]))
	prints """
		\tp0 = false
		\tloop:
		\t\tr0 = (f32.fromBits(r0) + f32.fromBits(1065353216)).toBits()
		\t\ttest = f32.fromBits(r0) != f32.fromBits(p.computeConstants[32768 + 3])
		\t\tp0 = test
		\t\t_ = not test
		\t\tif p0:
		\t\t\tbreak
		"""

test "SSY, a jump by a predicate over the then part, a SYNC at the end of each: an if-else":
	print(translated([
		0xE290_0000_0400_0000,   # SSY 0x50
		0x4BBD_8388_0037_0007,   # FSETP.NEU P0, PT, R0, c[0x2][0xc], PT
		0xE240_0000_0188_000F,   # @!P0 BRA 0x38
		0x0103_F800_0007_F000,   # MOV32I R0, 1.0
		0xF0F8_0000_0007_000F,   # SYNC
		0x0104_0000_0007_F000,   # MOV32I R0, 2.0
		0xF0F8_0000_0007_000F,   # SYNC
		0xE300_0000_0007_000F    # EXIT
	]))
	prints """
		\tp0 = false
		\ttest = f32.fromBits(r0) != f32.fromBits(p.computeConstants[32768 + 3])
		\tp0 = test
		\t_ = not test
		\tif p0:
		\t\tr0 = 1065353216
		\telse:
		\t\tr0 = 1073741824
		"""

test "a jump out of an if's part past the end of the if around it breaks out of a block run once":
	print(translated([
		0xE240_0000_0180_000F,   # @P0 BRA 0x28
		0xE240_0000_0181_000F,   # @P1 BRA 0x30
		0x50B0_0000_0007_0F00,   # NOP
		0x50B0_0000_0007_0F00,   # NOP
		0xE300_0000_0007_000F    # EXIT
	]))
	prints """
			p0 = false
			p1 = false
			loop:
				if not p0:
					if p1:
						break
				break
		"""

test "a BRA by a condition code: an if of what it skips, by the codes the IADD.CC before it set":
	print(translated([
		0x5C11_8000_0007_01FF,   # IADD.CC RZ, R1, -R0
		0xE240_0000_0107_0001,   # BRA.LT 0x28
		0x0103_F800_0007_F000,   # MOV32I R0, 1.0
		0xE300_0000_0007_000F    # EXIT
	]))
	prints """
		\tzf = false
		\tsf = false
		\tof = false
		\tca = r1
		\tcb = ~r0
		\tcr = ca + cb + 1
		\t_ = maxwell.carriesOut(ca, cb, 1)
		\tof = ((ca ^ cr) & (cb ^ cr)) >> 31 != 0
		\tzf = cr == 0
		\tsf = cr >> 31 != 0
		\t_ = cr
		\tif not (((sf and not zf) != of)):
		\t\tr0 = 1065353216
		"""

# CAL of a function that sets r0 and returns, then EXIT
callWords u64[] = [
	0xE260_0000_0187_000F,   # CAL 0x28
	0xE300_0000_0007_000F,   # EXIT
	0x50B0_0000_0007_0F00,   # NOP
	0x0103_F800_0007_F000,   # MOV32I R0, 1.0
	0xE320_0000_0007_000F    # RET
]

# BRX by r1 (set to 0x18: the instruction at 0x30), each target exiting
branchWords u64[] = [
	0x0100_0000_0187_F001,   # MOV32I R1, 0x18
	0xE250_0000_0007_010F,   # BRX R1
	0x0103_F800_0007_F000,   # MOV32I R0, 1.0
	0xE300_0000_0007_000F,   # EXIT
	0x0104_0000_0007_F000,   # MOV32I R0, 2.0
	0xE300_0000_0007_000F    # EXIT
]

test "CAL and RET: a machine of blocks, the return address pushed and taken back":
	print(translated(callWords))
	prints """
		\tat i32 = 8
		\treturns i32[16]
		\tcalled = 0
		\tloop:
		\t\tmatch at:
		\t\t\t8:
		\t\t\t\tat = 16
		\t\t\t\treturns[called] = 16
		\t\t\t\tcalled += 1
		\t\t\t\tat = 40
		\t\t\t16:
		\t\t\t\tat = 24
		\t\t\t\treturn
		\t\t\t24:
		\t\t\t\tat = 40
		\t\t\t40:
		\t\t\t\t_ = 1065353216
		\t\t\t\tat = 56
		\t\t\t\tif called == 0: break
		\t\t\t\tcalled -= 1
		\t\t\t\tat = returns[called]
		\t\t\t_:
		\t\t\t\tbreak
		"""

test "BRX: a jump to the register's address, any block's":
	text = translated(branchWords)
	expect "at = i32.wrap(r1) + 24" in text
	expect "\t\t\t24:" in text and "\t\t\t48:" in text

test "a jump from an inner loop past the end of the outer one: a machine of blocks":
	text = translated([
		0x50B0_0000_0007_0F00,   # NOP
		0x50B0_0000_0007_0F00,   # NOP
		0xE240_0000_0180_000F,   # @P0 BRA 0x38
		0xE240_0FFF_FE01_000F,   # @P1 BRA 0x10
		0xE240_0FFF_FD02_000F,   # @P2 BRA 0x8
		0xE300_0000_0007_000F    # EXIT
	])
	expect "\t\t\t16:\n\t\t\t\tat = 40\n\t\t\t\tif p0:\n\t\t\t\t\tat = 56" in text
	expect "\t\t\t48:\n\t\t\t\tat = 56\n\t\t\t\tif p2:\n\t\t\t\t\tat = 8" in text

# a compute program of the words, under the name
fn computeSource(name str, words u64[]):
	program = shaders.Program(stage = .Compute, header = none, words = words.map(word(it)), start = 0)
	shaders.Source(name = name.copy(), program, group = [1, 1, 1])

test "the module of the machines builds":
	sources = [computeSource("Calls", callWords), computeSource("Branches", branchWords)]
	done, said = shaders.writeBuilt(sources, "projects/recomp/switch/out/tests/machines") ?? fail
	if said != "": print(said)
	expect said == ""
	expect done.shaders.all(.missing.isEmpty)
