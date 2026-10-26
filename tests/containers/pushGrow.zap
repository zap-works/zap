# A push whose argument grows the list that holds the receiver: p.nodes[e].kids.push(grow(p))
# reallocates p.nodes while computing the value, so the receiver's address must be taken after
# the value is computed (both the call path and the in-place push for scalars), and the same for
# move on an element whose index is such a call.
type Node:
	kids i64[]
	name str
type Parser:
	nodes Node[]
fn grow(mut p Parser):
	for i in 0..64:
		p.nodes.push(Node(kids = [], name = "n{i}"))
	p.nodes.len - 1
mut p = Parser(nodes = [Node(kids = [], name = "root")])
loop 4:
	p.nodes[0].kids.push(p.grow())
	p.nodes[0].name += "!"
print(p.nodes[0].kids)
print(p.nodes[0].name)
print(p.nodes.len)
mut names = []
loop 3:
	names.push(move p.nodes[p.grow()].name)
print(names)

test "a push whose argument grows the list holding the receiver finds the receiver after":
	main()
	prints """
	    [64, 128, 192, 256]
	    root!!!!
	    257
	    ["n63", "n63", "n63"]
	    """
