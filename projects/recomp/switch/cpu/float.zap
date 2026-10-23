# What A64's scalar floating-point instructions do (arm64/float.zap decodes them).

import recomp.switch.arm64

pub fn float(mut c Cpu, i arm64.Instr):
	c.stop(c.pc - 4, "float {i.fop}")
