# Type checker, part 1: scopes, declaration lookups, type resolution and generic instantiation
# (a port of check.c). The checker annotates nodes in place: typeOf(nodes, e), global names,
# inserted nSome wrappers, lambda captures and monomorphized instances.

alias nodes = c.nodes
alias tys = c.types

# the statements of a block naming each name, by the name's number (mutability.zap)
type Mentions:
	byName {i64: i64[]} = {}

# a call in an arena block: its statement and the function it calls

type ArenaCall:
	stmt NodeId
	decl NodeId

type Var:
	name str
	nameNo i64   # its number (interned)
	ty TypeId
	isMut bool
	used bool
	isParam bool   # params and fields: exempt from the unused-variable check
	noneInit NodeId?   # declared as `x = none`: the literal whose type is fixed by the first real assignment
	literal NodeId?   # bound without mut or a type to numbers alone (`steps = 2400.0`): that value, which a use takes as its own literal would
	flexLet NodeId?   # a binding that changes, without a type, of number literals alone (`m = 0.5`): its let, which another type met later makes of it (retypeFlex)
	fromUses bool = false   # its type the one its uses gave (a retyped flexLet): a value that tells no type of its own
	lentFrom NodeId? = none   # a match arm's name for what `x.get(k)` found: that call, made getMut when the arm changes the name
	placeOf NodeId? = none   # the name a `?.` call gives its optional's value: that optional, named when a change needs it mut
	emptyInit NodeId? = none   # `x = []` (or `x T[] = []`): the literal; the first use that tells an element type fixes it
	emptyInfer TypeId? = none   # the list type that use fixes: the binding's own when written without a type, else a shadow zap fmt compares with the written one (none once nothing could tell it)
	emptyLet NodeId? = none   # the let, for zap fmt
	isField bool = false   # a field of the value a method is called on, named bare in its body
	isTest bool = false   # the value `opt is x` names: unread, the test is `opt != none`
	row i64 = -1   # a row of a Table (`r = mut ref t[i]`, a for's element): its place in Checker.rows
	narrowed bool = false   # a variable read as the narrower range a check just made proves (ranges.zap)
	lenRoot i64 = -1   # bound to the length of a list or a text: its variable (lengths.zap)
	lenPath str = ""   # and the list below that variable
	lenPlus i64 = 0   # and what is added to the length (`last = xs.len - 1`)
	line i64
	col i64

# a substitution: type parameters' names and the types they stand for, by position
type Subst:
	names str[]
	types TypeId[]

# a number method asked of a struct of numbers: the noted type, the method, its arguments' shape
# a pipeline lambda's index parameter, its row's name, row and element type
type RowParam:
	index str
	name str
	row i64
	elem TypeId

type FieldwiseAsk:
	derived i64
	method str
	shape str

type Checker:
	nodes Node[]
	kidIds NodeId[]   # the nodes' children (Node.kids)
	decls NodeId[]
	declsByName i64[,]   # a global name's number -> positions in decls, in order
	declsByLocal i64[,]   # a local name's number -> positions in decls, in order
	bareFound {i64: i64} = {}   # a bare name's number << 8 | kind -> its declaration (-1 none) ...
	bareMod i64 = -2   # ... in this module ...
	bareFile str = ""   # ... and file, while c.decls stay (lookupDeclAsWritten)
	layouts {NodeId: i64[]}   # a struct or variant with no type parameter in force -> its field offsets and size
	views {NodeId: bool}   # a struct declaration -> whether it is a view (isViewType)
	modules Module[]
	instances GenInst[]
	instancesAsked {i64: i64[]} = {}   # instanceKey of a generic function and its arguments -> its instances
	instancesByMangle {str: i64[]} = {}   # an instance's mangle -> its instances
	recording i64 = -1   # the instance being checked (checkInstance): what it asks for noted
	madeAsked {i64: NodeId[]} = {}   # instanceKey of a generic type and its arguments -> its instances
	types Ty[]
	file str
	errors i64
	errorsMet i64 = 0   # every errorAt, a place met twice included (resolveTypeOrNumber keeps no type that met one)
	vars Var[]   # every live variable, innermost scope last
	varIndex NameIndex = NameIndex()   # where each name stands in vars
	scopeStarts i64[]   # index into vars where each open scope begins
	chainStarts i64[] = []   # vars' length where each `if` with a pattern test being checked began
	currentRet TypeId?   # the result type of the function being checked
	curFn NodeId? = none   # the function whose body is being checked
	seqOk NodeId? = none   # the expression about to be checked where a Seq may stand (walked: a for's, a step's receiver)
	mapExpected TypeId? = none   # the element type a map's value is expected to have (its list's), else none
	loopDepth i64
	matchStmt bool   # the match about to be checked is a statement (block arms allowed)
	stmtExpr NodeId?   # the expression of the expression statement being checked (its value unused)
	valueTail NodeId?   # the last statement of a lambda's block, which may be its result
	implType TypeId?   # the struct whose impl block is being checked (bare method calls)
	curMod i64   # module whose code is being checked (index into modules, -1 = none)
	curFile str
	atDefinition bool   # the definition check of the generics (bounds.zap)
	failedGenerics NodeId[]   # the generic functions and impls whose definition check failed
	boundFns {str: NodeId}   # "type.name" -> the function taking the type first that met a bound's name
	boundCalls {str: NodeId} = {}   # "call type" -> the call of boundFns' function a bound's call made in an instance of that type
	aliasTy TypeId[]   # the stand-ins of type parameters in the definition check ...
	aliasBounds str[]   # ... their bounds ...
	aliasFn str[]   # ... and the generic each belongs to
	deriveTypes TypeId[]   # the types printed or encoded, $Ty0, $Ty1... (derive.zap)
	deriveKinds i64[]   # the functions wanted for each (deriveFmt | deriveJson ...)
	deriveDone i64[]   # the functions written for each
	fieldwise FieldwiseAsk[] = []
	fieldwiseDone i64 = 0
	gradAsks GradAsk[] = []   # the derivatives grad asked (grad.zap)
	gradDone i64 = 0
	gradHelpers i64[] = []   # the structs of gradients whose $gzeroN and $gaddN are asked
	gradHelpersDone i64 = 0
	gpuCode bool = false   # checking a GPU function (gpuCheck.zap)
	subst Subst   # the type parameters in force and their types
	inferringRet bool   # block lambda without an expected type: the first `return` fixes the type
	inferRet TypeId?
	lamStack NodeId[]   # lambdas being checked, outermost first
	lamBounds i64[]   # the parameter scope (depth) of each lambda in lamStack
	gridLoops GridLoop[] = []   # the loops open over a grid's width or height (grid.zap)
	lambdaCount i64
	safeCallCount i64
	viewDepth i64   # nesting of isViewType (recursive types resolve their own fields)
	plainOpen NodeId[] = []   # the declarations of the types isPlainType is inside of
	lentChecks LentCheck[]   # places lent to calls that also change their owner (effects.zap)
	effects EffectTable   # what each function changes through its mut parameters (effects.zap)
	reads {str: str[]} = {}   # what each function reads of a read parameter, as asked (reads.zap)
	fnEffects {NodeId: i64} = {}   # what each function does besides its result (purity.zap)
	valueEffects {str: str[]} = {}   # what a call through a function value may change in each module variable
	facts FnFacts[] = []   # what each function's body does and calls (bodyFacts.zap)
	factsMade bool = false
	keptFacts {NodeId: FnFacts} = {}   # the records the kept stages kept, taken by takeFacts
	lentDone bool   # judged: later analyses (instances the backend checks) note none
	arenaCalls ArenaCall[] = []   # the calls in arena blocks (pauseArenaGlobalCalls)
	retypes NodeId[]   # mut lets of number literals that met another type: checked again as it (retypeFlex) ...
	retypeTo TypeId[] = []   # ... that type
	relend bool = false   # a get whose value the program changes became getMut: the body is checked again
	round i64   # the round of the body being checked (checkFnBody): 0 the first
	pending PendingError[]   # the errors of the round, reported when it is not checked again
	rows TableRow[] = []   # the rows of tables the variables name (table.zap)
	liveHandles LiveHandle[] = []   # the handles known to name a value of their pool (poolWalk.zap)
	lenFacts LenFact[] = []   # the indexes known inside a list's length (lengths.zap)
	lengthNames i64 = 0   # the names bound to a length in the body being checked (lengths.zap)
	walkLets NodeId[] = []   # the lets of walks over a pool's places that bind a live handle (poolWalk.zap)
	rowParams RowParam[] = []   # (table.zap)
	rowFunctions RowFunction[] = []   # (table.zap)
	rangeTypes {str: TypeId} = {}   # the ranges arithmetic carried, by bounds (spanType)
	openBlocks NodeId[] = []   # the blocks being checked, innermost last (mutability.zap) ...
	openAt i64[] = []   # ... and the statement of each being checked
	openMentions Mentions[] = []   # ... and the statements naming each name, once made (mutability.zap) ...
	openIndexed bool[] = []   # ... whether it is made
	mutParams {str: i64} = {}   # each function name's mut parameters, a bit each (mutability.zap) ...
	mutParamsTo i64 = 0   # ... made of the declarations below this place ...
	mutParamsStage i64 = -1   # ... on the first ask of the stage whose first declaration is here
	weakExpected NodeId? = none   # the expression whose expected type only its siblings give (a list's
	# later elements, a match's later arms): no `.Variant` there
	resultState {NodeId: i64} = {}   # a function whose body gives its result -> where its check stands (results.zap)
	methodImpl {NodeId: NodeId} = {}   # such a function that is a method -> its impl
	resultMode i64 = 0   # how the body being checked gives its result (results.zap)
	tailAgain bool = false   # a trailing expression that is no value: the body again, it a statement
	trials Trial[] = []   # zap fmt's (resultTrials.zap)
	trialCopy NodeId? = none   # the copy whose trial is being made
	asideCopy NodeId? = none   # a copy checked aside (letTrials.zap): its errors counted, not said
	letTrials LetTrial[] = []   # zap fmt's (letTrials.zap)
	trialFails bool = false   # it met a form whose result the inference gives otherwise
	trialAlike bool = false   # it gave the written result
	openReturns NodeId[] = []   # the returns of `none` or `[]` before a return gave the result's type
	openTries NodeId[] = []   # the tries of a body whose result is being found, settled by it
	tryForms NodeId[] = []   # its `x ?? return none`, written `try x` when the result is an optional
	resultValue NodeId? = none   # the value of a return whose function's result is being found (its conversions stay)
	variantFns {NodeId: bool} = {}   # with zap fmt's notes on: the functions whose body notes a `.Variant`, which a dropped result would leave no enum
	resultCalls {NodeId: NodeId[]} = {}   # with zap fmt's notes on: the functions whose results a body asked
	valueOnlyErrors i64 = 0   # the errors only a value makes, not a statement (arms of different types)
	errorsKept i64 = 0   # the errors of the bodies checked in the middle of another (checkBodyNow)
	earlyResults NodeId[] = []   # the functions a generic's definition check needed the result of
	deferred bool = false   # the definition check being made needed one: made again after them
	receiverState {NodeId: i64} = {}   # a block's method whose receiver is inferred -> where its check stands (receivers.zap)
	receiverOf {NodeId: NodeId} = {}   # a copy of such a method (a generic impl's instance's) -> it
	receiverReaders {NodeId: NodeId[]} = {}   # such a method -> the bodies that read its mode
	receiverStale NodeId[] = []   # methods found changing after a body that cannot go again read them
	receiverAgain NodeId[] = []   # the bodies being checked that read a mode found otherwise later: again
	receiversOpen bool = false   # bodies may be checked when their mode is read
	receiverChanged bool = false   # the body being checked changes its receiver, read so far
	receiverSeen bool = false   # its receiver, written mut, changed as an inferred one's would be
	receiverUntold bool = false   # and changed where the inference cannot tell it (a lambda)
	changeVia bool = false   # the change being judged is a call of a method whose mode is inferred
	freshDecls i64 = 0   # the first declaration, and ...
	freshInstances i64 = 0   # ... the first instance, and ...
	freshModules i64 = 0   # ... the first module the stage being checked has to check: those before were checked by the stages before it (checkProgram)

# The checker owns the program while it works on it (see giveBack).
fn newChecker(mut prog Program):
	c = Checker(
		fnEffects = move prog.fnEffects,
		effects = move prog.effects,
		nodes = move prog.nodes,
		kidIds = move prog.kidIds,
		decls = move prog.decls,
		declsByName = [],
		declsByLocal = [],
		layouts = {},
		views = {},
		modules = move prog.modules,
		instances = move prog.instances,
		boundFns = move prog.boundFns,
		boundCalls = move prog.boundCalls,
		types = move prog.types,
		file = move prog.file,
		errors = 0,
		vars = [],
		scopeStarts = [],
		currentRet = none,
		loopDepth = 0,
		matchStmt = false,
		stmtExpr = none,
		valueTail = none,
		implType = none,
		curMod = -1,
		curFile = "",
		atDefinition = false,
		failedGenerics = [],
		aliasTy = [],
		aliasBounds = [],
		aliasFn = [],
		deriveTypes = prog.derived.copy(),
		deriveKinds = allDerived(prog.derived.len),
		deriveDone = allDerived(prog.derived.len),
		subst = Subst(names = [], types = []),
		inferringRet = false,
		inferRet = none,
		lamStack = [],
		lamBounds = [],
		lambdaCount = 0, safeCallCount = 0, viewDepth = 0, lentChecks = [], lentDone = false, retypes = [], round = 0, pending = [])
	for pos in 0..c.decls.len:
		c.indexDecl(pos)
	c.instancesByMangle.reserve(c.instances.len)
	for i in 0..c.instances.len:
		c.indexInstance(i)
	c

# the key of a generic and the type arguments of one of its instances, by their ids: a type
# made once has one id (types.zap), so the same arguments give the same key
fn instanceKey(generic NodeId, args TypeId[]):
	h = mixIn(i64(generic), args.len)
	for t in args:
		h = mixIn(h, i64(t))
	h

fn indexInstance(mut c Checker, i i64):
	gi = c.instances[i]
	addUnder(c.instancesByMangle, gi.mangle.copy(), i)
	if not gi.asked.isEmpty:
		addUnder(c.instancesAsked, instanceKey(gi.fnDecl, gi.asked), i, once = true)

# the instance of the generic function fnd named by mangle, or none
fn findInstance(c Checker, fnd NodeId, mangle str) i64?:
	for i in c.instancesByMangle.get(mangle) ?? return none:
		if c.instances[i].fnDecl == fnd and c.instances[i].mangle == mangle: return i
	none

# ---------- the declarations by name ----------
# Every lookup by name goes through two indexes kept with c.decls: addDecl and truncateDecls are
# the only changes to the list once the checker has it. An index is by the number of the name
# the node holds (interned); the few declarations of one name are told apart by their kind and
# module where they are read (firstIndexed).

fn indexDecl(mut c Checker, pos i64):
	d = c.decls[pos]
	n = interned.numbered(nodes[d].text)
	nodes[d].name = i32(n)   # (a name copied from the declaration takes its number)
	addAtNumber(c.declsByName, n, pos)
	addAtNumber(c.declsByLocal, interned.numbered(nodes[d].text2()), pos)

# v pushed in place onto the list under key (made when the key is new); once: unless it is there
# (the values come in order, so there means last)
pub fn addUnder<K Hash>(mut index {K: i64[]}, move key K, v i64, once bool = false):
	if index.get(key) is mut at:
		if not once or (at.last ?? -1) != v:
			at.push(v)
	else:
		index[key] = [v]

fn dropPosition(mut index i64[,], n i64, pos i64):
	if n >= 0 and n < index.len:
		if index[n].indexOf(pos) is at: index[n].remove(at)

pub fn addDecl(mut c Checker, d NodeId):
	c.decls.push(d)
	c.indexDecl(c.decls.len - 1)
	c.bareFound.clear()

pub fn truncateDecls(mut c Checker, n i64):
	for pos in n..c.decls.len:
		d = c.decls[pos]
		dropPosition(c.declsByName, interned.numberOf(nodes[d].text), pos)
		dropPosition(c.declsByLocal, interned.numberOf(nodes[d].text2()), pos)
	c.decls.truncate(n)
	c.bareFound.clear()
	c.madeAsked.clear()   # their instances may be among those gone

# the instances from n on dropped, with their entries in the indexes
fn truncateInstances(mut c Checker, n i64):
	c.instances.truncate(n)
	c.instancesAsked.clear()
	c.instancesByMangle.clear()
	for i in 0..n:
		c.indexInstance(i)

# the first declaration among the positions under the name (its number n) that is of the kind
# (and, local, of the module)
fn firstIndexed(
	c Checker,
	index i64[,],
	kind i64,
	moduleId str,
	name str,
	n i64,
	local bool
) NodeId?:
	for pos in atNumber(index, n):
		d = c.decls[pos]
		if kindMatches(nodes[d].kind, kind) and
			(
				nodes[d].mod() == moduleId and nodes[d].text2() == name if local
				else nodes[d].text == name
			):
			return d
	none

# for a checker made again over a checked program: every noted type has all its functions
fn allDerived(n i64):
	fill(n, 127)

# Returns the (possibly extended) program to its owner.
fn giveBack(mut c Checker, mut prog Program):
	prog.nodes = move nodes
	prog.kidIds = move c.kidIds
	prog.decls = move c.decls
	prog.modules = move c.modules
	prog.instances = move c.instances
	prog.boundFns = move c.boundFns
	prog.boundCalls = move c.boundCalls
	prog.types = move tys
	prog.derived = move c.deriveTypes
	prog.file = move c.file
	prog.fnEffects = move c.fnEffects
	prog.effects = move c.effects

fn substLookup(c Checker, name str) TypeId?:
	if c.subst.names.indexOf(name) is i: return c.subst.types[i]
	none
