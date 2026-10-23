# What A64's vector structure loads and stores do (arm64/structure.zap decodes them).

import recomp.switch.arm64

pub fn vectorStructure(mut c Cpu, i arm64.Instr):
	c.stop(c.pc - 4, "structure")
