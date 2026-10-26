# The behavior graphs one root graph refers to (hkbBehaviorReferenceGenerator: the master graph
# names mt_behavior, 1hm_behavior, sit, sleep...) joined into one: every file's nodes after the
# ones before it, each reference playing the root of the graph it names, the variables shared by
# name (the first file to hold one gives its initial value).

# one graph of many files
pub type Graph:
	nodes Node[]
	root i64
	variables Variable[]

# a reference's file name as the install's key of it: "Behaviors\Sit.hkx" is "sit.hkx"
pub fn behaviorFileOf(reference str) str:
	parts = reference.lower().replace("/", "\\").split("\\")
	parts[len - 1].copy()

# the file names the behavior refers to
pub fn referencesOf(b Behavior) str[]:
	b.nodes.filter(.reference != "").map(behaviorFileOf(.reference))

fn shifted(n Node, by i64):
	out = n.copy()
	out.children = n.children.map(it + by if it >= 0 else it)
	out.states = n.states.map(State(
		id = it.id,
		name = it.name.copy(),
		generator = it.generator + by if it.generator >= 0 else -1,
		transitions = it.transitions.copy(), enter = it.enter.copy(), exit = it.exit.copy()))
	out

# The root file's graph with the files it refers to (`files`, by file name, those the caller
# read) joined in; a reference to a file that is not there plays nothing.
pub fn joinBehaviors(files {str: Behavior}, rootFile str) Graph ? str:
	root = files.get(rootFile) ?? return "{rootFile} is not among the files"
	g = Graph(nodes = [], root = 0, variables = [])
	starts {str: i64} = {}
	order str[] = [rootFile.copy()]
	k = 0
	while k < order.len:
		file = order[k].copy()
		k += 1
		b = files.get(file) ?? continue
		starts[file.copy()] = g.nodes.len
		for n in b.nodes:
			g.nodes.push(n.shifted(starts[file]))
		for name in b.referencesOf():
			if starts.get(name) == none and name not in order: order.push(name.copy())
		for v in b.variables:
			if g.variables.findIndex(.name == v.name) == none:
				g.variables.push(Variable(name = v.name.copy(), value = v.value))
	for file in order:
		b = files.get(file) ?? continue
		start = starts[file]
		for i, n in b.nodes:
			if n.reference == "": continue
			target = behaviorFileOf(n.reference)
			other = files.get(target) ?? continue
			g.nodes[start + i].children = [(starts[target]) + other.root]
	g.root = (starts[rootFile]) + root.root
	g
