# What a lowering decides of the nodes it reads (irDecide's flags, a kept lambda's shared captures,
# the copies the ownership check asks for, a tail match's type), kept beside them until the lowering
# settles (irOwnSettle) and written to them then: the lowering reads the nodes and never writes
# them, so lowerings on copies of g can share them (card compiler-5).

alias nodes = g.c.nodes

type IrNodeMarks:
	flags {NodeId: i64} = {}   # a node's flags as decided
	shares {NodeId: str} = {}   # a kept lambda's shared captures (irSharedCaptures)
	types {NodeId: TypeId} = {}   # a statement match's type as a body's tail (irBlockValue)

fn irFlags(g Gen, e NodeId):
	g.irMarks.flags.get(e) ?? nodes[e].flags

fn irFlagged(g Gen, e NodeId, flag i64):
	g.irFlags(e) & flag != 0

fn irMark(mut g Gen, e NodeId, flag i64):
	flags = g.irFlags(e)
	if flags & flag != flag:
		g.irMarks.flags[e] = flags | flag

fn irUnmark(mut g Gen, e NodeId, flag i64):
	flags = g.irFlags(e)
	if flags & flag != 0:
		g.irMarks.flags[e] = flags & ~flag

fn irShares(g Gen, lam NodeId):
	(g.irMarks.shares.get(lam) ?? nodes[lam].text2()).copy()

fn irSetShares(mut g Gen, lam NodeId, marks str):
	if g.irShares(lam) != marks:
		g.irMarks.shares[lam] = marks.copy()

# e's type, as the checker left it or a lowering decided it
fn irTyped(g Gen, e NodeId) TypeId?:
	if g.irMarks.types.get(e) is t: return t
	nodes[e].ty

fn irSetTailType(mut g Gen, m NodeId, t TypeId):
	g.irMarks.types[m] = t

# the marks written to the nodes, once the lowering settled
fn irApplyMarks(mut g Gen):
	marks = move g.irMarks
	g.irMarks = IrNodeMarks()
	for e, flags in marks.flags:
		nodes[e].flags = flags
	for lam, shares in marks.shares:
		nodes[lam].setText2(shares.copy())
	for m, t in marks.types:
		nodes[m].ty = t
