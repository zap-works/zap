# The f64 arithmetic translated (fields as yuzu's double_*.cpp read them): DADD, DMUL, DFMA. A
# double is a register pair, the low word first (emit.zap's d, double and setD); DMNMX, DSET,
# DSETP, the conversions of f64 and MUFU.RCP64H/RSQ64H are float.zap's, beside their f32 forms.
# Each rounds to the nearest whatever mode it asks, as the f32 arithmetic (float.zap).

pub fn emitDadd(mut e Emitter, i Instr):
	a = absNeg(e.d(i.ra), i.flag(46), i.flag(48))
	b = absNeg(e.double(i.b), i.flag(49), i.flag(45))
	e.setD(i.rd, "{a} + {b}")

pub fn emitDmul(mut e Emitter, i Instr):
	e.setD(i.rd, "{e.d(i.ra)} * {absNeg(e.double(i.b), false, i.flag(48))}")

# fused (rounded once), as the hardware does
pub fn emitDfma(mut e Emitter, i Instr):
	b = absNeg(e.double(i.b), false, i.flag(48))
	c = absNeg(e.double(i.c), false, i.flag(49))
	e.setD(i.rd, "maxwell.fusedDouble({e.d(i.ra)}, {b}, {c})")
