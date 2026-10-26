# A for loop reads the place it goes over at each step: a body that grows what holds it (a list
# of nodes while the loop goes over one node's kids) moves that place, and the loop finds it
# again. Growing the very list it goes over is refused.

type Node:
	kids i64[]
	name str

fn grow(mut nodes Node[]):
	loop 50:
		nodes.push(Node(kids = [], name = "x"))

test "a loop over a place that moves finds it again":
	nodes = [Node(kids = [1, 2, 3], name = "a")]
	sum = 0
	for k in nodes[0].kids:
		grow(nodes)
		sum += k
	for n in nodes[0].kids:
		nodes.push(Node(kids = [n], name = "y"))
	print("{sum} {nodes.len}")
	prints "6 154"

test "a loop cannot grow the list it goes over" refuses ChangeWhileLooped:
	mut xs = [1, 2]
	for k in xs:
		xs.push(k)
	print(xs)

type Spot:
	x i64

fn numbersFrom(ids i64[]):
	for k, id in ids:
		out = [id]
		for later in ids:
			out.push(later)
		return out
	[]

fn spotsFrom(spots Spot[]):
	for k, spot in spots:
		out = [spot]
		for later in spots:
			for k2, again in spots:
				if k2 == 0: out.push(later)
				out.push(again)
		return "{out.map(.x)}"
	""

fn wordsFrom(words str[]):
	for k, word in words:
		out = [word]
		for later in words:
			out.push(later)
		return "{out}"
	""

test "a list literal of a loop's element holds values, with an index or not":
	print(numbersFrom([10, 20, 30]))
	print(spotsFrom([Spot(x = 1), Spot(x = 2)]))
	print(wordsFrom(["a", "b", "c"]))
	print([10, 20].map([it]).map(.len))
	prints """
		[10, 10, 20, 30]
		[1, 1, 1, 2, 2, 1, 2]
		["a", "a", "b", "c"]
		[1, 1]
		"""
