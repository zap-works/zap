# Scalar locals held in registers across a loop: the register ids, and the moves between a
# register and the local's frame slot.

alias tys = g.c.types
alias vars = g.f.vars

# A scalar local held in a register for the loops being generated: the variable, the register
# (0..4 rbx, r12, r13, r14, r15; 5..14 xmm6..xmm15; 15..18 the scratch registers)
type CachedVar:
	variable i64
	reg i64

# A register reserved for a local a loop body declares at its top level, bound when its let is
# generated: the local's name, the register, the loop's nesting (g.f.loopMarks.len) and the
# scope depth of the let that binds it (a let of the same name in a nested block is another
# variable).
type PendingReg:
	name str
	reg i64
	depth i64
	scope i64

# A body local given a register for part of a loop: after statement `stmt`, its last read, the
# register is free for the next local (the loop at nesting `depth`).
type Release:
	stmt i64
	name str
	depth i64
