# A pub function named like a built-in: the modules that do not import this one keep the built-in.

pub type Shelf:
	counts i64[]

pub fn fill(mut s Shelf, mut extra i64[], n i64):
	s.counts.push(n)
	extra.push(n)
