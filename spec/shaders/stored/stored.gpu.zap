# A struct holding an f64, which the GPU's code refuses.

pub type Roots:
	out u32[]

type Pair:
	x f64
	y f64

pub fn stored(mut p Roots):
	pair = Pair(x = 1.0, y = 2.0)
	p.out[globalId.x] = (pair.x + pair.y).lowWord()
