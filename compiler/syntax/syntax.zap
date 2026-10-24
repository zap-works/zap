# The Zap language's words: the keywords, the words that declare a test and the words the parser
# reads in place (`zap doc keywords` prints them, doc.zap). The editor's grammar (tools/vscode-zap)
# colours them too, so a view the language server does not read (a diff, a file before the server
# is up) has its colours; `zap lsp`'s semantic tokens (lsptokens.zap) refine them in a file.

import fs

# the words the language keeps (the lexer's tokens for them are in the same order)
pub keywords = [
	"fn",
	"type",
	"mut",
	"move",
	"return",
	"if",
	"else",
	"match",
	"import",
	"pub",
	"true",
	"false",
	"none",
	"shared",
	"self", "while", "for", "in", "break", "continue", "ref", "is", "loop", "extern", "elif", "and", "or", "not", "try", "it", "yield"]

# A test declaration starts with testWord, a name otherwise; after the test's name, a word of
# sourceTestWords makes its body source kept as text (the compiler's to refuse, or a program of
# its own); inside a test's body, a line led by a word of caseWords and an error's name is such
# a source too, a case of its own
pub testWord = "test"
pub refusesWord = "refuses"   # test "name" refuses Name: source the compiler must refuse
pub stopsWord = "stops"   # test "name" stops Name: a program that must stop on that error
pub caseWords = [refusesWord, stopsWord]
pub sourceTestWords = [refusesWord, stopsWord]
pub expectWord = "expect"   # `expect condition`: a statement, the check of a test
pub printsWord = "prints"   # `prints text`: a statement of a test, the check of its output

# the word that is a block with nothing in it (`if c: pass`), a name everywhere else
pub passWord = "pass"
pub lenWord = "len"   # inside an index's brackets, a bare `length`: the indexed list's length
# a size read as a field (`xs.len`, `q.isEmpty`, a process's `p.isDone`, a list's `xs.byteSize`): a
# method of these names that takes nothing is written without parentheses
pub sizeWords = ["len", "isEmpty", "isDone", "byteSize"]
# a list's ends, read as fields as a size is (`xs.first`, `xs.last`: an optional each)
pub endWords = ["first", "last"]
pub argsWord = "args"   # the program's arguments, a value (`args.len`, `for a in args`)
# a result's error, by name: on the right of `??` after a value that can fail, and the error's
# arm of a `match` on a result
pub errorWord = "error"
pub stepWord = "step"   # `lo..hi step s`: a range's step, after its end
# `from json import parse`: an import of names
pub fromWord = "from"
pub asWord = "as"   # `from m import name as local`: the name an imported one is read by
pub boundWord = "bound"   # `bound Show:` declares a bound (spec *Generics*)
pub loadedWord = "loaded"   # `extern loaded fn`: a function whose address is given while the program runs
pub circleWords = ["pi", "tau"]   # the constants of the language, floats of the type the place asks for

# `use name, name` as the first line of a file, a function or a block sets that scope's options,
# the closed set of names here (see spec *Options*)
pub useWord = "use"
# `arena:` opens a block whose allocations are freed at once at its end (spec *Arenas*)
pub arenaWord = "arena"
pub options = ["fusedMultiplyAdd", "noAllocation", "noLocks", "noStops"]

# whether the word after a test's name makes its body source the lexer does not read
pub fn keepsSource(word str) bool:
	word in sourceTestWords

# the words the parser reads in their places and that are names everywhere else
pub fn contextualWords() str[]:
	words = [
		fromWord,
		asWord,
		testWord,
		refusesWord,
		stopsWord,
		expectWord,
		printsWord,
		loadedWord,
		boundWord,
		passWord,
		lenWord,
		errorWord,
		stepWord,
		useWord,
		arenaWord
	]
	words.extend(circleWords)
	words

test "the table holds every keyword and says which keep the source after them":
	print("{keywords.len} {keepsSource("refuses")} {keepsSource("prints")}")
	prints "31 true false"

grammarFile = "tools/vscode-zap/syntaxes/zap.tmLanguage.json"

test "the editor's grammar colours every keyword":
	text = fs.readFile(grammarFile) ?? ""
	expect keywords.all(
		"({it}|" in text or "|{it}|" in text or "|{it})" in text or "({it})" in text
	)
