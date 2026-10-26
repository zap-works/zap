pub type Form:
	name str
	operands str[]

fn build():
	out {i64: Form} = {}
	for k in 0..3:
		out[k] = Form(name = "name{k}", operands = "Ev,Gv".split(","))
	out

pub table = build()
