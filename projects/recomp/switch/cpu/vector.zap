# What A64's Advanced SIMD and crypto instructions do (arm64/vector.zap decodes them).

import recomp.switch.arm64

pub fn vector(mut c Cpu, i arm64.Instr):
	match i.vop:
		ThreeSame: c.threeSame(i)
		ThreeDifferent: c.threeDifferent(i)
		Indexed: c.indexed(i)
		TwoMisc: c.twoMisc(i)
		AcrossLanes: c.acrossLanes(i)
		Copy: c.elementCopy(i)
		ModifiedImmediate: c.modifiedImmediate(i)
		ShiftImmediate: c.shiftImmediate(i)
		Permute: c.permute(i)
		Extract: c.extractBytes(i)
		Table: c.tableLookup(i)
		Aes: c.aes(i)
		ShaThree: c.shaThree(i)
		ShaTwo: c.shaTwo(i)
		_: c.stop(c.pc - 4, "vector {i.vop}")
