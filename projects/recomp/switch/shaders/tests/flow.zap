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
