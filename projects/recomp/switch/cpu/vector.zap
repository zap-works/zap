# What A64's Advanced SIMD and crypto instructions do (arm64/vector.zap decodes them).

import recomp.switch.arm64

pub fn vector(mut c Cpu, i arm64.Instr):
	c.stop(c.pc - 4, "vector {i.vop}")
