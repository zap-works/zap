# What each function's lowering adds to the program's shared state (irBodyShared, the generic
# instances, the data), for splitting the lowering into a part per function run on every
# processor and a shared part merged in order (card compiler-5): ZAP_RUN=lowershared counts
# the functions whose lowering adds nothing, and their share of the lowering's time.

fn lowerSharedWord():
	TraceWord(
		"lowershared",
		"the functions whose lowering adds nothing shared (labels, strings, types, nodes, instances, lambdas), their share of its time, and what the others add"
	)

# the shared state's sizes a lowering may grow, by the names lowerSharedNames gives them
fn lowerSharedSizes(g Gen):
	sizes = g.irBodyShared()
	sizes.push(g.c.instances.len)
	sizes.push(g.a.data.len)
	sizes

# the answers kept for asking again a lowering may add to (a part per function keeps its own or
# reads them made before), by the names lowerMemoNames gives them
fn lowerMemoSizes(g Gen):
	[g.mayBorrow.len,
		g.holdsClosure.len,
		g.owning.len,
		g.aggregate.len,
		g.tdOffs.len,
		g.loadedSlots.len,
		g.fnValueNames.len,
		g.c.layouts.len,
		g.c.views.len,
		g.c.instancesAsked.len,
		g.c.madeAsked.len,
		g.c.rangeTypes.len,
		g.c.effects.len,
		g.c.reads.len,
		g.c.fnEffects.len,
		g.irWorth.len,
		g.irReporters.len,
		numberBodies.len,
		typeIndex.len,
		irOwnSaid.len]

fn lowerSharedNames():
	["lambdas",
		"lambda numbers",
		"spans",
		"given instances",
		"types",
		"nodes",
		"drops planned",
		"strings",
		"labels",
		"globals named",
		"floats",
		"call stores",
		"instances",
		"data"]

fn lowerMemoNames():
	["mayBorrow",
		"holdsClosure",
		"owning",
		"aggregate",
		"type descriptors",
		"loaded slots",
		"function values",
		"layouts",
		"views",
		"instances asked",
		"made asked",
		"range types",
		"effects",
		"reads",
		"function effects",
		"g.irWorth",
		"g.irReporters",
		"numberBodies",
		"typeIndex",
		"irOwnSaid"]

# the lowerings counted: all, those that added nothing, the seconds of each, and how many grew
# each size
type LowerShared:
	functions i64 = 0
	alone i64 = 0
	seconds f64 = 0.0
	aloneSeconds f64 = 0.0
	memoFree i64 = 0   #   of those, the ones that added no answer kept either
	grew i64[] = []
	memoGrew i64[] = []

mut lowerShared = LowerShared()

# a lowering that took seconds counted, its sizes (lowerSharedSizes then lowerMemoSizes) before
# and after
fn noteLowerShared(before i64[,], after i64[,], seconds f64):
	lowerShared.functions += 1
	lowerShared.seconds += seconds
	alone = grownCounted(lowerShared.grew, before[0], after[0])
	memoFree = grownCounted(lowerShared.memoGrew, before[1], after[1])
	if alone:
		lowerShared.alone += 1
		lowerShared.aloneSeconds += seconds
		if memoFree: lowerShared.memoFree += 1

# each size that grew counted in grew: whether none did
fn grownCounted(mut grew i64[], before i64[], after i64[]):
	if grew.isEmpty:
		grew = fill(before.len, 0)
	same = true
	for i in 0..before.len:
		if after[i] != before[i]:
			grew[i] += 1
			same = false
	same

fn sayLowerShared():
	eprint(
		"lowershared: {lowerShared.alone} of {lowerShared.functions} functions add nothing shared, {lowerShared.aloneSeconds} of {lowerShared.seconds} s lowering"
	)
	eprint("  {lowerShared.memoFree} of those add no answer kept either")
	sayGrown(lowerSharedNames(), lowerShared.grew)
	sayGrown(lowerMemoNames(), lowerShared.memoGrew)

fn sayGrown(names str[], grew i64[]):
	for i, n in grew:
		if n > 0: eprint("  {names[i]}: grown by {n}")
