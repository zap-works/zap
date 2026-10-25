# f64 on the GPU: each invocation makes two doubles of the words it reads and writes what they
# give, each result as its two words; a double's square root is refused.

pub type Doubles:
	inputs u32[]   # each invocation's a and b, two words each
	out u32[]   # each invocation's results, two words each

# the results each invocation writes
count = 12

fn put(mut p Doubles, at i32, x f64):
	p.out[at] = x.lowWord()
	p.out[at + 1] = x.highWord()

fn fused(a f64, b f64) f64:
	use fusedMultiplyAdd
	a * b + 0.1

pub fn arithmetic(mut p Doubles):
	i = globalId.x
	a = f64.fromWords(p.inputs[4 * i], p.inputs[4 * i + 1])
	b = f64.fromWords(p.inputs[4 * i + 2], p.inputs[4 * i + 3])
	at = 2 * count * i
	put(p, at, a + b)
	put(p, at + 2, a - b)
	put(p, at + 4, a * b)
	put(p, at + 6, a / b)
	put(p, at + 8, fused(a, b))
	put(p, at + 10, a.min(b))
	put(p, at + 12, (-a).max(b).abs())
	put(p, at + 14, 1.0 if a < b else 0.0)
	put(p, at + 16, f64(f32(a)))
	put(p, at + 18, f64(i32(a)))
	put(p, at + 20, f64(p.inputs[4 * i]))
	put(p, at + 22, a.clamp(-100.0, 100.0) * 0.5)

pub type Roots:
	out u32[]

pub fn root(mut p Roots):
	x = f64(globalId.x).sqrt()
	p.out[globalId.x] = x.lowWord()
