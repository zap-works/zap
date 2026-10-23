# A64's scalar floating-point group (Arm ARM C4.1.6, op0 x0x1): data processing of one, two and
# three sources, compares, conditional selects and compares, immediates, and the conversions
# between floats and integers.

pub type FloatOp:
	None

# The scalar FP instruction w, Op.Unknown when it is none the decoder knows.
fn floatScalar(w i64):
	Instr()
