# The Zap compiler, written in Zap: tokens, syntax tree and declarations.
# Nodes live in one arena (Node[]) and refer to each other by index, so the checker can
# annotate them in place through list paths (nodes[id].ty = t).

import fold
import fs

pub type Tok:
	kind i64
	text str
	line i64
	col i64

# token kinds (same order as the C bootstrap)
pub tkEof = 0
pub tkNewline = 1
pub tkInt = 2
pub tkFloat = 3
pub tkStr = 4
pub tkStrBegin = 5
pub tkStrMid = 6
pub tkStrEnd = 7
pub tkIdent = 8
pub tkUident = 9
pub tkFn = 10
pub tkType = 11
pub tkMut = 12
pub tkMove = 13
pub tkRead = 14   # (no longer a word: a parameter reads by default)
pub tkReturn = 15
pub tkIf = 16
pub tkElse = 17
pub tkMatch = 18
pub tkImport = 19
pub tkFrom = 20   # (no longer a word: `from` is an identifier the parser reads in its places)
pub tkPub = 21
pub tkTrue = 22
pub tkFalse = 23
pub tkNone = 24
pub tkShared = 25
pub tkThis = 28
pub tkWhile = 29
pub tkFor = 30
pub tkIn = 31
pub tkBreak = 32
pub tkContinue = 33
pub tkLparen = 34
pub tkRparen = 35
pub tkLbrace = 36
pub tkRbrace = 37
pub tkLbracket = 38
pub tkRbracket = 39
pub tkComma = 40
pub tkDot = 41
pub tkDotdot = 42
pub tkColon = 44
pub tkPlus = 45
pub tkMinus = 46
pub tkStar = 47
pub tkSlash = 48
pub tkPercent = 49
pub tkStarstar = 50
pub tkAt = 51
pub tkEq = 52
pub tkEqeq = 53
pub tkBangeq = 54
pub tkLt = 55
pub tkGt = 56
pub tkLe = 57
pub tkGe = 58
pub tkAmp = 62
pub tkCaret = 63
pub tkTilde = 64
pub tkShl = 65
pub tkShr = 66
pub tkQq = 67
pub tkQdot = 68
pub tkQuestion = 69
pub tkPipe = 70
pub tkRef = 71
pub tkIs = 72
pub tkLoop = 73
pub tkExtern = 74
pub tkOpAssign = 75   # x += y, x <<= y ...: the text is the operator ("+", "<<")
pub tkByte = 76   # 'a', '\n': the text is the byte's value in decimal
pub tkTernary = 78   # ` ? ` with a space on each side: a result, T ? E (`T?`, an optional, is written close)
pub tkRawBlock = 77   # the body of an `expects` test, kept as source text (it may not even lex)
pub tkFormatSpec = 79   # `:.2` closing an interpolation (`"{x:.2}"`): the text is the spec after the colon
pub tkIndent = 80   # the line after one ending in `:` is indented: a block opens
pub tkDedent = 81   # a line indented less than the block's lines: the block ends
pub tkDotdotEq = 82   # `..=`: a range that includes its end
pub tkElif = 83   # `elif c:`: another condition after an if's block
pub tkAnd = 84   # `a and b`
pub tkOr = 85   # `a or b`
pub tkNot = 86   # `not x`
pub tkTry = 87   # `try x`: the value, or its error (none, for an optional) returned to the caller
pub tkIt = 88   # `it`: the value of the call argument it stands in (placeholder.zap)
pub tkYield = 89   # `yield v`: a generator gives v to the loop walking it
# the markup of a .zapx file (lexmarkup.zap)
pub tkMarkOpen = 90   # `<div`, `<Stat`, `<` of a fragment: the text is the tag ("" for a fragment)
pub tkMarkAttr = 91   # an attribute's name in a tag
pub tkMarkTagEnd = 92   # the `>` ending a tag whose children follow
pub tkMarkSelfClose = 93   # `/>`, or the `>` of a void element (`<br>`): the element ends
pub tkMarkText = 94   # text between tags, its whitespace across lines made one space
pub tkMarkClose = 95   # `</div>`: the text is the tag

# what a token of kind k is called in a message: a keyword or an operator as written (the lexer's
# tables), the others by what they are
pub fn tokKindName(k i64) str:
	if keywordTokens.indexOf(k) is i: return "'{keywords[i]}'"
	if binaryOperators.find(.token == k) is o: return "'{o.text}'"
	if punctuation.find(.token == k) is o: return "'{o.text}'"
	names = [
		TokenText("end of file", tkEof),
		TokenText("newline", tkNewline),
		TokenText("int literal", tkInt),
		TokenText("float literal", tkFloat),
		TokenText("string", tkStr),
		TokenText("string start", tkStrBegin),
		TokenText("string middle", tkStrMid),
		TokenText("string end", tkStrEnd),
		TokenText("identifier", tkIdent),
		TokenText("type name", tkUident),
		TokenText("'read'", tkRead),
		TokenText("'from'", tkFrom),
		TokenText(r"'{'", tkLbrace),
		TokenText("'\}'", tkRbrace),
		TokenText("compound assignment", tkOpAssign),
		TokenText("byte literal", tkByte),
		TokenText("raw block", tkRawBlock),
		TokenText("' ? '", tkTernary),
		TokenText("format spec", tkFormatSpec),
		TokenText("indented block", tkIndent), TokenText("end of block", tkDedent),
		TokenText("tag", tkMarkOpen),
		TokenText("attribute", tkMarkAttr),
		TokenText("'>'", tkMarkTagEnd),
		TokenText("'/>'", tkMarkSelfClose),
		TokenText("markup text", tkMarkText),
		TokenText("closing tag", tkMarkClose)]
	if names.find(.token == k) is n: return n.text.copy()
	"?"

# ---------- nodes ----------

# a checked node's type (one not checked reads as the error type)
# whether the node e, when there is one, has the flag
pub fn isFlagged(ns Node[], e NodeId?, flag i64) bool:
	match e:
		e: ns[e].hasFlag(flag)
		none: false

pub fn typeOf(ns Node[], e NodeId) TypeId:
	ns[e].ty ?? tyError

# expressions
pub nInt = 1
pub nFloat = 2
pub nStr = 3
pub nInterp = 4
pub nBool = 5
pub nNone = 6
pub nIdent = 7
pub nField = 8
pub nIndex = 9
pub nCall = 10
pub nUnary = 11
pub nBinary = 12
pub nStructLit = 13
pub nLambda = 14
pub nMatch = 15
pub nArray = 16
pub nTry = 17
pub nRange = 18
pub nMapLit = 19
pub nSome = 20
pub nDeref = 21   # the value a reference points to (inserted by the checker)
# statements
pub nLet = 30
pub nAssign = 31
pub nReturn = 32
pub nExprStmt = 33
pub nIf = 34
pub nWhile = 35
pub nFor = 36
pub nBreak = 37
pub nContinue = 38
pub nBlock = 39
# match arms and patterns
pub nArm = 40
pub nPattern = 41
pub nYield = 42   # yield v: kids [v], in a function whose result is a Seq<T>
# type expressions
pub nTyName = 50
pub nTyOpt = 51
pub nTyResult = 52
pub nTyFn = 53
pub nTyAbsent = 54
pub nTyRef = 55
pub nTyArray = 56   # T[N], a fixed array (in registers when regarrays.zap can): ival N, types[0] T
pub nTyRange = 57   # T in a..b: types[0] T, kids the bounds (one for an open end), ival 0 `..`, 1 `..=`, 2 `a..`
# declarations and pieces
pub nParam = 60
pub nFieldDecl = 61
pub nVariant = 62
pub nFnDecl = 63
pub nStructDecl = 64
pub nEnumDecl = 65
pub nConstDecl = 66
pub nImplDecl = 67
pub nImportDecl = 68
pub nNamedArg = 70   # name = value in a call's arguments: text the parameter, kids [value]
pub nPartsDecl = 72   # parts lex, check: names the files (lex.zap) or dirs (check/) beside the file that are its module's
pub nBoundDecl = 71   # bound Name { fn m(params) R ... }: kids the methods it asks for (nFnDecl without bodies)
pub nTestDecl = 69   # test "name" [expects Kind.Name {source}] { body }: ival 0 plain, 1 prints,
# 2 expects a CompileError (text2 its code, names2 a part of its message, names[0] the source),
# 3 expects a RuntimeError (text2 a part of the error report, names[0] the program)

# unary operators
pub unNeg = 0
pub unNot = 1
pub unBnot = 2
pub unMove = 3
pub unRef = 4
pub unMutRef = 5
pub unOut = 6   # `out x`, the argument of an extern's out parameter: x's address
# binary operators
pub binAdd = 0
pub binSub = 1
pub binMul = 2
pub binDiv = 3
pub binMod = 4
pub binPow = 5
pub binMatmul = 6
pub binEq = 7
pub binNe = 8
pub binLt = 9
pub binGt = 10
pub binLe = 11
pub binGe = 12
pub binAnd = 13
pub binOr = 14
pub binCoalesce = 15
pub binBand = 16
pub binBor = 17
pub binBxor = 18
pub binShl = 19
pub binShr = 20
pub binIn = 21   # x in xs (membership; `x not in xs` is not (x in xs))
# patterns: each written as its value is built, any part of one a pattern of its own (kids)
pub patWildcard = 0
pub patBind = 1   # a name (text), bound to the value; `name is pattern` tests kids[0] too
pub patCtor = 2   # a variant or a struct (text): kids its parts, names their fields ("" by position)
pub patNone = 3
pub patLit = 4
pub patRange = 5   # lo..hi of number literals (kids [lo, hi], or [lo] for lo..): hi included when text2 is "="
pub patTuple = 6   # (a, b): kids the parts
pub patList = 7   # [a, ..rest, b]: kids the elements, one of them a patRest at most
pub patRest = 8   # `..name` (text, "" for `..`) in a list: the elements between, lent as a slice
pub patStr = 9   # "GET {path}": names the text around the captures, kids the captures (names or _)
pub patMap = 10   # {"k": v}: kids the keys (the checker makes each a lookup) and value patterns in turn

# whether a pattern of a match on a result takes its error: the name `error` (any other name takes
# the value)
pub fn bindsError(pat Node) bool:
	pat.ival == patBind and pat.text == errorWord
# parameter modes
pub modeRead = 0
pub modeMut = 1
pub modeMove = 2
pub modeOut = 3   # an extern's `out x T`: the system writes a T where the word points
pub methodInBlock = 1   # a function's ival: a method written in its type's block (parseunit.zap)

pub flagMut = 1
pub flagPub = 2
pub flagSafe = 4
pub flagFnRef = 8
pub flagClosure = 16
pub flagShared = 32
pub flagAlias = 256   # a let whose value aliases memory it does not own (runtime only)
pub flagDerefPayload = 512   # `??` on an optional reference to plain data: the result is the value
pub flagExtern = 1024   # a function of the operating system: no body, names2[0] is its DLL
pub flagAutoCopy = 1024   # the compiler copies this value here (neither a move nor a borrow would do)
pub flagAutoWiden = 4096   # a conversion call the checker inserted to widen a number: undone and
# redone whenever the expression is checked again (generic instances)
pub flagAutoRef = 4_398_046_511_104   # a reference or a dereference the checker inserted (refNode,
# derefNode): undone and redone whenever the expression is checked again (generic instances)
pub flagVecLit = 16_384   # f64x4(a, b, c, d), i32x8(...): a vector from its lanes
pub flagByte = 8192   # an int literal written as a byte ('a'): a u8 when nothing else decides
pub flagMethod = 32_768   # a method call the checker made a call of its runtime function (names[0] of
# the callee: the method), the receiver its first argument
pub flagKeyLambda = 524_288   # sortedBy/minBy/maxBy's key or map's value: a str part of the element is lent, kept as a window
pub flagOnce = 262_144   # a lambda that runs once (a background job's): its body may give away what it captured
pub flagTaken = 131_072   # a move out of a place the ownership pass wrote: a part of an owned local given away
pub flagInternal = 65_536   # a node the checker wrote for a surface form (Simd<4>(x) is x.splat4()): its
# spelling is the backend's and is not accepted from a program; on a let, the binding of a loop's
# element (always a new name); on a for, the parser's `for i, x in xs` (a map's is walked by cells)
pub flagLocalLambda = 1_048_576   # a lambda bound to a name that the function only calls: it borrows
# what it captures (a changed scalar through a pointer), and the
# calls' callee names carry the names it changes (names2)
pub flagParallelSort = 2_097_152   # `xs.parallel()...sortedBy(f)`: the sort runs on every processor
pub flagFieldwise = 8_388_608   # a number method on a struct of numbers, field by field: text2 its $fw function's family (derive.zap)
pub flagDotVariant = 16_777_216   # `.Circle(2.0)`: a variant of the enum the place expects (kids[0] an empty name the checker fills)
pub flagWritten = 33_554_432   # a pattern Variant(...) written with its parentheses (Variant alone matches any payload)
pub flagIsTest = 70_368_744_177_664   # a pattern written after `is` (`opt is x`): the name it binds is read, or the test is `!= none`
pub flagFromBase = 134_217_728   # a field the checker reads for `..base` in a struct's literal (its message names ..base)
pub flagCompound = 67_108_864   # a let or an assignment written x op= v, and its operation (its value the operation on a copy of x)
pub flagFirstK = 1_073_741_824   # `xs.sortedBy(f).slice(0, k)` made the sortedBy alone: only its first k (ival) kept
pub flagOrdered = 137_438_953_472   # a top-level binding of a program file whose value is computed: assigned by
#   main's statement in its place (its storage zero before it)
pub flagOptionBlocks = 2_199_023_255_552   # a function with a block inside it that sets options (`use`): its tree is walked for them
pub flagNoLocks = 1_099_511_627_776   # a function or block under `use noLocks`: nothing it reaches waits (options.zap)
pub flagInBounds = 576_460_752_303_423_488   # proven inside, no check made: xs[i] inside xs (`for i in 0..xs.len` whose body leaves xs's length alone, stops.zap; a check against its length, lengths.zap), a sum of such an index inside its type
pub flagNoStops = 1_152_921_504_606_846_976   # a function or block under `use noStops`: nothing it reaches stops the program (options.zap)
pub flagNoAllocation = 549_755_813_888   # a function or block under `use noAllocation`: nothing it reaches allocates (options.zap)
pub flagInit = 274_877_906_944   # that assignment statement
pub flagOpenEnd = 68_719_476_736   # a range written without its end (`xs[lo..]`, `xs[.. step 2]`): a slice to the end, which fills it
pub flagWidenCandidate = 34_359_738_368   # a conversion call written on a number (i64(n)): where a place would widen n to that type anyway, zap fmt drops it
pub flagArena = 17_592_186_044_416   # an `arena:` block (an if true whose block allocates from a region)
pub flagArenaPause = 35_184_372_088_832   # a statement in an arena that stores outside it: it allocates from the heap
pub flagTable = 1_125_899_906_842_624   # a struct the checker made for a Table<T>: a List per field of T (table.zap)
pub flagSize = 8_796_093_022_208   # the callee of a size's call (`xs.len`, `q.isEmpty`): read as a field
pub flagGpu = 17_179_869_184   # a function of a GPU file: checked in the GPU's terms (gpucheck.zap), compiled for the GPU only (irgpu.zap)
pub flagFusedMath = 8_589_934_592   # a function or block under `use fusedMultiplyAdd`: its floats' a * b + c rounded once (fuse.zap)
pub flagTypeAlias = 4_294_967_296   # `type Name = T`: a type of its own over T (types[0]), resolved where it is declared
pub flagBytesSum = 2_147_483_648   # `bytes.sum(b => i64(b))` (or toU64, or b itself): the receiver's bytes added (rt bytesSum)
pub flagPlaceholder = 140_737_488_355_328   # `it` or the `.` of `.hp`: an identifier for the value of the call
# argument it stands in, named by the lambda the checker makes of that argument (placeholder.zap)
pub flagWrap = 281_474_976_710_656   # a conversion written T.wrap(x), or the end x + 1 of lo..=x: the value wrapped to T, never checked
pub flagRangeConversion = 562_949_953_421_312   # `Percent(x)`, `n64(i)`, `Meters(x)`: a call of a range
# type's or a defined type's name, its checked conversion (kids [callee, x])
pub flagBaseView = 288_230_376_151_711_744   # a receiver of a defined type read as its base, for a method of the base
pub flagFromTuple = 9_007_199_254_740_992   # a tuple `(a, b)` or `(f = a)` the checker made the struct its place expects (zap fmt keeps the annotation that place gives)
pub flagDrop = 2_251_799_813_685_248   # a struct with a drop function (`fn drop(mut self T)`): not plain data
pub flagComma = 2_305_843_009_213_693_952   # an index after a comma (`g[x, y]` is g[x][y] so marked): a Grid's coordinates, a list's next layer
pub flagMayChange = 268_435_456   # a let without mut that what follows may change (changes.zap)
pub flagModuleVar = 4_503_599_627_370_496   # an identifier naming a module variable declared mut (purity.zap)
pub flagBoundCall = 72_057_594_037_927_936   # x.f(a) on a value of a type parameter, f a method its bound declares: an instance whose type meets it by a function taking it first calls that (Checker.boundCalls)
pub flagShownIfAny = 144_115_188_075_855_872   # an interpolation an expect's report shows: a part without a text (a function's value) reads (no text)
pub flagJammed = 4_194_304   # a loop of two turns of a nest at once (irjam.zap): the rows its statements write do not meet
pub flagBorrowLambda = 2048   # a lambda passed to a read parameter: it cannot outlive the call, so its
# environment borrows the captured values (pointers, no copies)

# a node the compiler writes (a rewrite of a surface form): its kind, place, text and children
# the statement calling the runtime's function `name` with args (a call no program writes: the
# checker finds it among the runtime's own)
pub fn internalCallStmt(mut nodes Node[], move name str, args NodeId[], line i64, col i64) NodeId:
	callee = newNode(nodes, nIdent, line, col, name)
	nodes[callee].flags = flagInternal
	call = newNode(nodes, nCall, line, col)
	nodes[call].kids.push(callee)
	nodes[call].kids.extend(args)
	st = newNode(nodes, nExprStmt, line, col)
	nodes[st].kids.push(call)
	st

pub fn newNode(
	mut nodes Node[],
	kind i64,
	line i64,
	col i64,
	move text str = "",
	move kids NodeId[] = []
) NodeId:
	nodes.push(
		Node(
			kind = u8(kind),
			line = i32(line),
			col = nodeCol(col),
			text,
			kids,
			flags = 0,
			ival = 0,
			ty = none
		)
	)
	NodeId(nodes.len - 1)

# a column as a node keeps it: one past 30,000 (a generated line's) is that, room left above
# for the sums made of it
pub fn nodeCol(col i64) i16:
	i16(col.min(30_000))

# `of.len`: the length of what `of` gives, a call the checker reads as the field it is written as
pub fn lenOf(mut nodes Node[], line i64, col i64, of NodeId) NodeId:
	f = newNode(nodes, nField, line, col, text = "len", kids = [of])
	nodes[f].flags = flagSize
	newNode(nodes, nCall, line, col, kids = [f])

# "{e}": the value of e as text
pub fn shownValue(mut nodes Node[], e NodeId) NodeId:
	before = newNode(nodes, nStr, nodes[e].line, nodes[e].col)
	after = newNode(nodes, nStr, nodes[e].line, nodes[e].col)
	newNode(nodes, nInterp, nodes[e].line, nodes[e].col, kids = [before, e, after])

pub fn hasFlag(n Node, f i64) bool:
	(n.flags & f) != 0

# whether a let `name = value` assigns name when it is already bound: written bare, and not the
# binding of a loop's element, which is always a new name
pub fn canAssign(s Node) bool:
	not s.hasFlag(flagMut) and s.types().isEmpty and not s.hasFlag(flagInternal)

# ---------- program ----------

pub type Module:
	id str   # "a.b", or "" for the main module
	prefix str   # "a_b__", or ""
	file str
	imports NodeId[]   # import declaration nodes
	std bool   # a module of the standard library: it reaches the runtime's private functions
	unit bool = false   # a source of a together check, a program of its own (loadUnits)
	expects str = ""   # a unit's: the code of the error its test expects
	unparsed bool = false   # a std module loaded from its index, parsed once no kept stage holds it (stdindex.zap)

# the module id of a together check's source (loadUnits): a `$` no module's name holds
pub fn unitModuleId(i i64) str:
	"u${i}"

# whether a global name is one of a together check's source's, which errors show as the program's
pub fn isUnitKey(key str) bool:
	key.startsWith("u$")

# whether name is the global name of a together check's source's main (loadUnits): an entry as
# much as a program's main
pub fn isUnitMain(modules Module[], name str) bool:
	name.endsWith("__main") and modules.any(.unit and name == "{.prefix}main")

pub type GenInst:
	fnDecl NodeId   # the generic function declaration node
	decl NodeId   # the declaration checked and generated: fnDecl, or its copy for the numbers given
	mangle str
	sub Subst   # its type parameters and the types they stand for
	site str   # file:line:col of the call that made the instance
	asked TypeId[] = []   # the type arguments as the call gave them, before numberArgs
	checked bool = false   # its body checked (checkInstance)
	recorded i64[] = []   #   and the instances its check asked for, in order (a kept form asks again)
	end i64 = 0   # past the nodes of decl's tree when decl is a copy (numbered from decl on), else 0

pub type Program:
	nodes Node[]
	decls NodeId[]
	file str
	modules Module[]
	instances GenInst[]
	types Ty[]
	derived TypeId[]   # the types printed or encoded, $Ty0, $Ty1... (derive.zap)
	tests NodeId[]   # the test declarations, apart from the program (zap test runs them)
	entry str   # the function the executable starts with: main, or the tests' entry
	boundFns {str: NodeId} = {}   # the checker's, kept for a checker made again (Checker.boundFns)
	boundCalls {str: NodeId} = {}   # the same (Checker.boundCalls), read by the backend
	fnEffects {NodeId: i64} = {}   # what each function does (purity.zap), for the backend
	effects {str: str[]} = {}   # what each function changes through its mut parameters (effects.zap)
	kept Checker? = none   # the checker as the kept stages left it, for the check to go on from (keptstages.zap)
	stages CheckStage[] = []   # its declarations and modules by the stage that checks them (stages.zap)
	stageKeys {str: i64} = {}   # the key of each stage of the runtime and std it loads (keptstages.zap)
	stageFiles {str: str} = {}   #   and the file it is kept in
	readsAside {str: bool} = {}   # what the std modules loaded from their index read, and the runtime's
	needsAside str[] = []   #   dirs they need (stdindex.zap)
	keptBodies {NodeId: NodeId} = {}   # the bodies the kept stages keep of functions with number parameters (regarrays.zap)
	keptWaiting WaitingBodies = WaitingBodies()   # the bodies of the kept stages that wait (keptbodies.zap)

# What the checker checks at once, alone after the stages before it (spec 14.2): a dir of the
# runtime ("rt/core"), a std module ("fs") or the program (""). Its declarations and modules end at
# those places in Program.decls and Program.modules, the ones the checker adds while it checks the
# stage counted once it is done; a stage of the runtime or std has the key it is kept under.
pub type CheckStage:
	name str
	decls i64
	modules i64
	done bool = false
	key i64 = 0
	nodes i64 = 0   # the checker's nodes, types and instances once it is done
	types i64 = 0
	instances i64 = 0
	file str = ""   # where it is kept (stagePath): named by it and the stages before it

# A compile error, as the agent or person fixing it needs it: the place and the message on one
# line (file:line:col: error: message, or error[code] for a named one, what editors and the LSP
# read), then the line of source
# with a caret under the column. With ZAP_RUN=errors=json, one line of JSON instead: the same
# fields and the source line.
pub fn errorAtFile(file str, line i64, col i64, msg str):
	filesWithErrors[file.copy()] = true
	source = sourceLineOf(file, line)
	code, text = errorCode(msg)
	if (errorsWord().value() ?? "") == "json":
		named = "compile" if code == "" else code
		eprint("\{\"error\":{jsonQuote(named)},\"file\":{jsonQuote(file)},\"line\":{line},\"col\":{col},\"message\":{jsonQuote(text)},\"source\":{jsonQuote(source)}}")
		return
	shownCode = "" if code == "" else "[{code}]"
	said = "{file}:{line}:{col}: error{shownCode}: {text}"
	errorLines.push(said.copy())
	eprint(said)
	if source != "":
		shown = caretLines(source, line, col)   # the runtime's, as a program's errors show it
		eprint(shown[..len - 1])

# the files errors were reported in (a together check's sources that said something)
pub mut filesWithErrors {str: bool} = {}

# the first line of each error the program loaded said (a check again of the lint's notes in this
# process reads them)
mut errorLines str[] = []

# the text of the files errors were reported in, read once each
mut sourceTexts {str: str} = {}

# line `line` of the file, without its line break ("" when the file cannot be read)
fn sourceLineOf(file str, line i64):
	if file not in sourceTexts:
		sourceTexts[file.copy()] = fs.readFile(file) ?? ""
	if sourceTexts.get(file) is text: return textLine(text, line) ?? ""
	""

# A binary operator as every pass reads it: its source text, its token, its level in the parser
# (0 binds tightest, ** tighter still, ?? loosest) and whether x op= y is written with it
# a token and how it is written or called
pub type TokenText:
	text str
	token i64

pub type BinaryOperator:
	text str
	token i64
	level i64
	compound bool

# the binary operators, each at its code (binAdd .. binShr)
pub binaryOperators = [BinaryOperator(text = "+", token = tkPlus, level = 1, compound = true),
	BinaryOperator(text = "-", token = tkMinus, level = 1, compound = true),
	BinaryOperator(text = "*", token = tkStar, level = 0, compound = true),
	BinaryOperator(text = "/", token = tkSlash, level = 0, compound = true),
	BinaryOperator(text = "%", token = tkPercent, level = 0, compound = true),
	BinaryOperator(text = "**", token = tkStarstar, level = -1, compound = false),
	BinaryOperator(text = "@", token = tkAt, level = 0, compound = false),
	BinaryOperator(text = "==", token = tkEqeq, level = 3, compound = false),
	BinaryOperator(text = "!=", token = tkBangeq, level = 3, compound = false),
	BinaryOperator(text = "<", token = tkLt, level = 2, compound = false),
	BinaryOperator(text = ">", token = tkGt, level = 2, compound = false),
	BinaryOperator(text = "<=", token = tkLe, level = 2, compound = false),
	BinaryOperator(text = ">=", token = tkGe, level = 2, compound = false),
	BinaryOperator(text = "and", token = tkAnd, level = 4, compound = false),
	BinaryOperator(text = "or", token = tkOr, level = 5, compound = false),
	BinaryOperator(text = "??", token = tkQq, level = 6, compound = false),
	BinaryOperator(text = "&", token = tkAmp, level = 0, compound = true),
	BinaryOperator(text = "|", token = tkPipe, level = 1, compound = true),
	BinaryOperator(text = "^", token = tkCaret, level = 1, compound = true),
	BinaryOperator(text = "<<", token = tkShl, level = 0, compound = true),
	BinaryOperator(text = ">>", token = tkShr, level = 0, compound = true),
	BinaryOperator(text = "in", token = tkIn, level = 3, compound = false)]

# the source text of a binary operator
pub fn binName(op i64) str:
	if op >= 0 and op < binaryOperators.len: return binaryOperators[op].text.copy()
	"?"

# the code of the binary operator written as text, or -1
pub fn binaryCode(text str) i64:
	binaryOperators.findIndex(.text == text) ?? -1

# the texts of the operators x op= y is written with
pub fn compoundTexts() str[]:
	binaryOperators.filter(.compound).map(.text.copy())

# Whether a break or a continue under e leaves the loop e is in. With `ownLoopsOnly`, one inside
# a nested loop or a lambda belongs to that one and does not count.
pub fn breaksOut(nodes Node[], e NodeId, ownLoopsOnly bool) bool:
	k = nodes[e].kind
	if k == nBreak or k == nContinue: return true
	if ownLoopsOnly and (k in [nWhile, nFor, nLambda]): return false
	nodes[e].kids.any(breaksOut(nodes, it, ownLoopsOnly)) or
		nodes[e].sub().any(breaksOut(nodes, it, ownLoopsOnly))

# Whether the name is used under e (an identifier), or with `declared`, also declared there (a
# let or a for that binds it).
pub fn mentions(nodes Node[], e NodeId, declared bool, name str) bool:
	k = nodes[e].kind
	if nodes[e].text == name and (k == nIdent or (declared and (k == nLet or k == nFor))):
		return true
	nodes[e].kids.any(mentions(nodes, it, declared, name)) or
		nodes[e].sub().any(mentions(nodes, it, declared, name))

# whether the trees at a and b are written alike: kinds, texts, values and kids
pub fn isSameTree(nodes Node[], a NodeId, b NodeId) bool:
	nodes[a].kind == nodes[b].kind and nodes[a].text == nodes[b].text and
		nodes[a].ival == nodes[b].ival and nodes[a].kids.len == nodes[b].kids.len and
		(0..nodes[a].kids.len).all(isSameTree(nodes, nodes[a].kids[it], nodes[b].kids[it]))

# A pipeline's steps, each with what it allows: `fuses` it runs over an array as over a list and
# takes the maps and filters before it into its own loop; `onRange` it runs over (lo..hi);
# `parallel` it runs on every processor after .parallel() (sortedBy, minBy and maxBy pick their
# result in parallel apart); `calls` a function value given it runs in its loop as a lambda does.
pub type PipelineStep:
	name str
	fuses bool
	onRange bool
	parallel bool
	calls bool

pub pipelineTable = [
	PipelineStep("map", true, true, true, true),
	PipelineStep("filter", true, true, true, true),
	PipelineStep("flatMap", true, true, true, true),
	PipelineStep("all", true, true, true, true),
	PipelineStep("any", true, true, true, true),
	PipelineStep("count", true, true, true, true),
	PipelineStep("reduce", true, true, false, false),
	PipelineStep("sortedBy", false, true, false, false),
	PipelineStep("sortBy", false, false, false, false),
	PipelineStep("find", false, true, false, true),
	PipelineStep("findIndex", false, false, false, true),
	PipelineStep("minBy", false, true, false, false),
	PipelineStep("maxBy", false, true, false, false),
	PipelineStep("sum", false, true, true, false),
	PipelineStep("mean", true, true, false, false),
	PipelineStep("groupBy", true, true, true, true),
	PipelineStep("countBy", true, true, true, true),
	PipelineStep("zip", true, true, false, false)]
pub pipelineSteps = pipelineTable.map(.name.copy())

# the steps a Seq<T> takes (the rest need a list: .toList() makes one); filter and map give a Seq
pub seqSteps = [
	"filter",
	"map",
	"all",
	"any",
	"count",
	"reduce",
	"sum",
	"mean",
	"groupBy",
	"countBy",
	"zip"
]

# whether a type as written is a Seq<T>, what a function that yields gives
pub fn isSeqName(te Node) bool:
	te.kind == nTyName and te.text == "Seq"

pub fn stepFuses(m str) bool:
	pipelineTable.any(.name == m and .fuses)

pub fn isStepOnRange(m str) bool:
	pipelineTable.any(.name == m and .onRange)

pub fn isStepParallel(m str) bool:
	pipelineTable.any(.name == m and .parallel)

pub fn stepCalls(m str) bool:
	pipelineTable.any(.name == m and .calls)

# The step a call is when it can run in the loop of the step that consumes it: "map" or
# "filter" over one receiver with a plain lambda of one parameter (no block); "" otherwise.
pub fn fusableStep(nodes Node[], e NodeId) str:
	if nodes[e].kind != nCall or nodes[e].kids.len != 2: return ""
	callee = nodes[e].kids[0]
	lam = nodes[e].kids[1]
	m = nodes[callee].text
	if nodes[callee].kind != nField or nodes[callee].kids.len != 1 or
		m != "map" and m != "filter":
		return ""
	m.copy() if nodes[lam].kind == nLambda and nodes[lam].sub().isEmpty and nodes[lam].names().len == 1
		else ""

fn isCompareOp(op i64):
	op >= binEq and op <= binGe

# the conversions between integers: to the signed widths, then the unsigned, 8 to 64 bits
pub intConversions = ["toI8", "toI16", "toI32", "toI64", "toU8", "toU16", "toU32", "toU64"]
# an integer's methods on its bits, each a few instructions in place
pub intBitMethods = [
	"bitCount",
	"trailingZeros",
	"leadingZeros",
	"rotateLeft",
	"rotateRight",
	"byteSwap",
	"mulHigh"
]
# an integer's bits by position, read and set (x.bits(4, 2), x.withBit(7, on)): each a few
# instructions in place, stopping only for a position past the width the compiler cannot see
pub bitFieldMethods = ["bit", "bits", "withBit", "withBits"]

# the method a conversion written with a number type's name is (`i64(x)` is toI64 on x);
# "" for any other name
pub fn conversionMethod(name str) str:
	if name.len < 2: return ""
	m = "to{name[..1].upper()}{name[1..]}"
	m if m in intConversions or m in floatConversions else ""

# the conversions to floats, by their methods' names
pub floatConversions = ["toF32", "toF64"]

# the number type a conversion method converts to (toI64 to i64), the name a conversion is written with
pub fn conversionType(m str) str:
	m[2..].lower()

# the bits of the integer conversion m converts to (0 when m is none)
pub fn conversionBits(m str) i64:
	i = intConversions.indexOf(m) ?? -1
	0 if i < 0 else 8 << (i % 4)

# a copy of the tree under e, new nodes all the way down; its index
pub fn cloneTree(mut nodes Node[], e NodeId) NodeId:
	first = nodes.len
	copies {NodeId: NodeId} = {}
	id = copyTree(nodes, e, copies)
	# a node's origin (a method's callee kept for undoing the call, a known value) is copied
	# too: the copy's own, which checking the copy may change
	i = first
	while i < nodes.len:
		if nodes[i].origin() is o:
			mine = copies.get(o) ?? copyTree(nodes, o, copies)
			nodes[i].setOrigin(mine)
		i += 1
	id

fn copyTree(mut nodes Node[], e NodeId, mut copies {NodeId: NodeId}) NodeId:
	n = nodes[e].copy()
	n.kids = []
	n.nodePart().sub = []
	nodes.push(n)
	id = NodeId(nodes.len - 1)
	copies[e] = id
	# by index: cloning pushes nodes, which may move the list these are read from
	for i in 0..nodes[e].kids.len:
		ck = copyTree(nodes, nodes[e].kids[i], copies)
		nodes[id].kids.push(ck)
	for i in 0..nodes[e].sub().len:
		ck = copyTree(nodes, nodes[e].sub()[i], copies)
		nodes[id].nodePart().sub.push(ck)
	id

# whether any of the names is used under e
pub fn mentionsAny(nodes Node[], e NodeId, names str[]) bool:
	names.any(mentions(nodes, e, false, it))

# whether the result of runtime intrinsic `nm` aliases memory it does not own (a view into a
# block, a value read in place): it is never dropped
pub fn intrinsicAliases(nm str) bool:
	intrinsicHas(nm, "L")

pub fn nodeCalls(nodes Node[], e NodeId) bool:
	nodes[e].kind == nCall or nodes[e].kids.any(nodeCalls(nodes, it))

# whether e makes a call other than reading a size (`xs.len`, read in place): a list reached so
# is a place, as `blocks[way[len - 1]]` is once its `len` is filled in
pub fn nodeCallsPastSizes(nodes Node[], e NodeId) bool:
	if nodes[e].kind == nCall and nodes[e].kids.len == 1 and
		nodes[nodes[e].kids[0]].kind == nField and nodes[nodes[e].kids[0]].hasFlag(flagSize):
		return nodeCallsPastSizes(nodes, nodes[nodes[e].kids[0]].kids[0])
	nodes[e].kind == nCall or nodes[e].kids.any(nodeCallsPastSizes(nodes, it))
pub moduleOrigin = "$module"   # the origin of a reference into the module's own data (a constant)

# the source text of an expression, for messages: what `expect` shows when its condition fails,
# the place a checker error names
fn exprText(nodes Node[], id NodeId) str:
	e = nodes[id]
	k = e.kind
	if k in [nInt, nFloat, nIdent]:
		return e.text.copy()   # the text of an expression is a string of its own
	if k == nStr: return "\"{e.text}\""
	if k == nBool:
		if e.ival == 1: return "true"
		return "false"
	if k == nNone: return "none"
	if k == nInterp: return "interp[{listText(nodes, e.kids, ", ")}]"
	if k == nField:
		sep = "."
		if e.hasFlag(flagSafe):
			sep = "?."
		return exprText(nodes, e.kids[0]) + sep + e.text
	if k == nIndex: return "{exprText(nodes, e.kids[0])}[{exprText(nodes, e.kids[1])}]"
	if k == nCall: return "{exprText(nodes, e.kids[0])}({listText(nodes, e.kids[1..], ", ")})"
	if k == nDeref: return exprText(nodes, e.kids[0])
	if k == nUnary:
		op = "!"
		if e.ival == unNeg:
			op = "-"
		elif e.ival == unBnot:
			op = "~"
		elif e.ival == unMove:
			op = "move "
		elif e.ival == unRef:
			op = "ref "
		elif e.ival == unMutRef:
			op = "mut ref "
		return op + exprText(nodes, e.kids[0])
	if k == nBinary:
		return "({exprText(nodes, e.kids[0])} {binName(e.ival)} {exprText(nodes, e.kids[1])})"
	if k == nStructLit:
		s = ""
		if e.text2() != "":
			s = "{e.text2()}."
		fields = (0..e.names().len)
			.map(" {e.names()[it]} = {exprText(nodes, e.kids[it])}")
			.join(",")
		return "{s}{e.text} \{{fields} }"
	if k == nLambda:
		s = "({e.names().join(", ")}) => "
		if not e.kids.isEmpty:
			s += exprText(nodes, e.kids[0])
		else:
			s += r"{ ... }"
		return s
	if k == nMatch: return "match {exprText(nodes, e.kids[0])} \{ {e.kids.len - 1} arms }"
	if k == nArray and e.ival > 0: return "fill({e.ival}, {listText(nodes, e.kids, ", ")})"
	if k == nArray: return "[{listText(nodes, e.kids, ", ")}]"
	if k == nTry: return "try {exprText(nodes, e.kids[0])}"
	if k == nRange: return "{exprText(nodes, e.kids[0])}..{exprText(nodes, e.kids[1])}"
	if k == nSome: return "some({exprText(nodes, e.kids[0])})"
	if k == nMapLit:
		entries = (0..e.kids.len)
			.map("{exprText(nodes, e.kids[it])}: {exprText(nodes, e.sub()[it])}")
			.join(", ")
		return "\{{entries}}"
	"<?>"

fn listText(nodes Node[], ids NodeId[], sep str):
	ids.map(exprText(nodes, it)).join(sep)

# ---------- constant folding ----------

# a number folded: an integer, or a float (held as an f64, rounded to the width it was folded at)
pub type Folded:
	float bool
	i i64
	f f64

# The value of a number expression of literals (+ - * / % and the bitwise operators, unary -)
# computed at `bits` bits (the CPU's 64, the GPU's 32: an integer wraps, a float is rounded at
# each step), or none. leaf gives what an identifier stands for when it is known (the backend's
# inlined constant arguments, a GPU constant's value), or -1.
pub fn foldedNumber(nodes Node[], e NodeId, bits i64, leaf fn(NodeId) NodeId?) Folded?:
	k = nodes[e].kind
	if k == nInt:
		v = try i64.parse(nodes[e].text)
		return Folded(float = false, i = fold.wrapBits(v, bits), f = 0.0)
	if k == nFloat:
		v = try f64.parse(nodes[e].text)
		return Folded(float = true, i = 0, f = fold.roundBits(v, bits))
	if k == nIdent: return foldedNumber(nodes, try leaf(e), bits, leaf)
	if k == nUnary and nodes[e].ival == unNeg:
		v = try foldedNumber(nodes, nodes[e].kids[0], bits, leaf)
		return Folded(..v, f = -v.f) if v.float else Folded(..v, i = fold.wrapBits(-v.i, bits))
	if k != nBinary: return none
	a = try foldedNumber(nodes, nodes[e].kids[0], bits, leaf)
	b = try foldedNumber(nodes, nodes[e].kids[1], bits, leaf)
	op = binName(nodes[e].ival)
	if a.float != b.float: return none
	if a.float:
		v = try fold.floatOp(op, a.f, b.f, bits)
		return Folded(float = true, i = 0, f = v)
	v = try fold.intOp(op, a.i, b.i, bits)
	Folded(float = false, i = v, f = 0.0)

# a folded number's literal text (none for a float a literal does not write back: infinite, not
# a number, or a negative zero)
pub fn foldedText(v Folded, bits i64) str?:
	if not v.float: return "{v.i}"
	if v.f - v.f != 0.0 or v.f == 0.0 and 1.0 / v.f < 0.0: return none
	text = "{f32(v.f)}" if bits == 32 else "{v.f}"
	text if "." in text or "e" in text else "{text}.0"

# The value of an integer expression of literals (+ - * / %, unary -), or none. leaf gives what
# an identifier stands for when it is known (the backend's inlined constant arguments), or -1.
pub fn foldedInt(nodes Node[], e NodeId, leaf fn(NodeId) NodeId?) i64?:
	v = try foldedNumber(nodes, e, 64, leaf)
	none if v.float else v.i

# an integer expression of literals folded into one literal in place, its parts first; false
# when it is not one
pub fn foldInt(mut nodes Node[], e NodeId) bool:
	k = nodes[e].kind
	if k == nInt: return true
	if k == nUnary and nodes[e].ival == unNeg:
		if not foldInt(nodes, nodes[e].kids[0]): return false
	elif k != nBinary or not foldInt(nodes, nodes[e].kids[0]) or
		not foldInt(nodes, nodes[e].kids[1]):
		return false
	value = foldedInt(nodes, e, x: none) ?? return false
	nodes[e].kind = nInt
	nodes[e].text = "{value}"
	nodes[e].kids = []
	nodes[e].flags = 0
	true

# a condition of literals (comparisons of integers, && || !) folded into a bool in place
pub fn foldBool(mut nodes Node[], e NodeId) bool:
	k = nodes[e].kind
	if k == nBool: return true
	value = false
	if k == nUnary and nodes[e].ival == unNot and foldBool(nodes, nodes[e].kids[0]):
		value = nodes[nodes[e].kids[0]].ival == 0
	elif k == nBinary:
		op = nodes[e].ival
		l = nodes[e].kids[0]
		r = nodes[e].kids[1]
		if (op == binAnd or op == binOr) and foldBool(nodes, l) and foldBool(nodes, r):
			a = nodes[l].ival == 1
			b = nodes[r].ival == 1
			value = a and b if op == binAnd else a or b
		elif isCompareOp(op) and foldInt(nodes, l) and foldInt(nodes, r):
			value = fold.compareOp(
				binName(op),
				i64.parse(nodes[l].text) ?? 0,
				i64.parse(nodes[r].text) ?? 0
			) ??
				false
		else:
			return false
	else:
		return false
	nodes[e].kind = nBool
	nodes[e].ival = 1 if value else 0
	nodes[e].kids = []
	true
