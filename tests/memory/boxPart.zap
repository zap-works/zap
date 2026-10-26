# A `mut ref` of a box a `mut` name of an `is` test holds: the place the box's word is in.
type Node:
	v i64
	b Box<Node>?

	fn child() mut ref Box<Node>:
		if self.b is mut m: return mut ref m
		fail("no child")

test "a mut ref of a box read from an optional field is that field's box":
	n = Node(v = 1, b = Box(Node(v = 2, b = none)))
	c = n.child()
	c = Box(Node(v = 7, b = none))
	print("{n.v} {(n.b ?? fail("none")).v}")
	prints "1 7"
