# binary-trees: every node allocated on its own (a box); each short-lived tree inside an `arena:`
# block, the language's pool, which frees the tree whole at the block's end (as the Rust program's
# bumpalo and the C programs' library pools).
import problems

type Node:
	left Box<Node>?   # none for a leaf
	right Box<Node>?
fn bottomUp(depth i64) Node:
	if depth == 0: return Node(left = none, right = none)
	Node(left = Box(bottomUp(depth - 1)), right = Box(bottomUp(depth - 1)))
fn check(n Node) i64:
	l = n.left ?? return 1
	1 + check(l) + check(n.right ?? return 1)
# one tree built in an arena of its own and checked
fn tree(depth i64):
	c = 0
	arena:
		c = bottomUp(depth).check()
	c
n = arg(0, 10)
minDepth = 4
maxDepth = n.max(minDepth + 2)
stretch = maxDepth + 1
print("stretch tree of depth {stretch}	 check: {tree(stretch)}")
workers = cpuCount()
levels = (maxDepth - minDepth) / 2 + 1
fn depthAt(level i64):
	minDepth + 2 * level
fn iterationsAt(level i64):
	1 << (maxDepth - depthAt(level) + minDepth)
# the long-lived tree in an arena too (as the Rust program's), given back whole at the end
arena:
	longLived = bottomUp(maxDepth)
	# every level's trees cut in a share per worker, the levels' shares taking turns so that the
	# deepest trees are not all built at once
	parts = (0..levels * workers).parallel().map(t:
		level = t % levels
		(t / levels..iterationsAt(level) step workers).sum(_: tree(depthAt(level)))
	)
	for level in 0..levels:
		total = (level..parts.len step levels).sum(parts[it])
		print("{iterationsAt(level)}	 trees of depth {depthAt(level)}	 check: {total}")
	print("long lived tree of depth {maxDepth}	 check: {longLived.check()}")

test "trees made in an arena are checked and freed whole at its end":
	main()
	prints """
	    stretch tree of depth 11	 check: 4095
	    1024	 trees of depth 4	 check: 31744
	    256	 trees of depth 6	 check: 32512
	    64	 trees of depth 8	 check: 32704
	    16	 trees of depth 10	 check: 32752
	    long lived tree of depth 10	 check: 2047
	    """

test "the C, Rust and Python programs print the same bytes":
	expect problems.agree("binaryTrees")
