# Tuples: (a, b) is Tuple2(_0 = a, _1 = b), the type (A, B) is Tuple2<A, B>, and a, b = t
# takes each value out to a name (a program never reads a position: t.0 is an error). They print as (1, "a").
pub type Tuple2<A, B>:
	_0 A
	_1 B

# (a, b, c); pairs are written as tuple types of their own
pub type Tuple3<A, B, C>:
	_0 A
	_1 B
	_2 C

pub type Tuple4<A, B, C, D>:
	_0 A
	_1 B
	_2 C
	_3 D

pub type Tuple5<A, B, C, D, E>:
	_0 A
	_1 B
	_2 C
	_3 D
	_4 E

pub type Tuple6<A, B, C, D, E, F>:
	_0 A
	_1 B
	_2 C
	_3 D
	_4 E
	_5 F

pub type Tuple7<A, B, C, D, E, F, G>:
	_0 A
	_1 B
	_2 C
	_3 D
	_4 E
	_5 F
	_6 G

pub type Tuple8<A, B, C, D, E, F, G, H>:
	_0 A
	_1 B
	_2 C
	_3 D
	_4 E
	_5 F
	_6 G
	_7 H
