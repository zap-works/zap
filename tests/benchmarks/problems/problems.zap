# The benchmark problems: each Zap program of tests/benchmarks/ against the same problem in
# other languages (others/<name>.c, .cpp, .rs, .py). `zap test --only bench` races them
# (tests/benchmarks/bench.zap, std/compare's suite); each benchmark file's test checks that every
# language prints the same bytes (agree). The sizes: the argument at full size, a smaller one for a quick look, the
# smallest for the check of the outputs; kNucleotide, revComp and regexRedux read fasta's output.
# The Zap benchmarks game: above each problem, its rule, which every language's program keeps to;
# the first eight, pidigits and regexRedux are the Benchmarks Game's (benchmarksgame-team.pages.debian.net/benchmarksgame/
# description/<name>.html), the others ours in its manner. As there, the output is the same bytes,
# threads and vector instructions are allowed, and the work is the rule's: not skipped, not cached.
# One implementer writes every language's program as well as the language allows. Zap's compiler,
# runtime and std may change for a problem only by what serves programs in general (a rule of code,
# not one program's shape), and the change shows where else it applies.
import compare
import fs

pub fn problems() compare.Problem[]:
	[
		# the same simple symplectic integrator as the Java program
		problem("nbody", "50000000", "5000000", "1000", false, ""),
		# the power method on the infinite matrix A, in 4 separate functions as the Java program
		problem("spectralNorm", "5500", "2000", "100", false, "-fopenmp"),
		# every permutation flipped until its first is 1; checksum +flips at even indexes, -flips at odd; the most flips
		problem("fannkuchRedux", "12", "10", "7", false, "-pthread -fopenmp"),
		# every node allocated, by default GC, per node or a library pool; no custom arena, memory pool or free list
		problem("binaryTrees", "21", "16", "6", false, "-pthread"),
		# the letter of each random number by its cumulative probabilities, a search or a table of them (as the
		# game's published entries do); the naive LCG drawn in order, no jump ahead, its sequence not cached
		problem("fasta", "25000000", "2500000", "1000", false, ""),
		# [-1.5-i, 0.5+i] on an N by N bitmap, written byte by byte as PBM
		problem("mandelbrot", "16000", "4000", "200", false, "-ffp-contract=off -fno-finite-math-only -fopenmp -pthread"),
		# stdin line by line; the built-in or a library hash table grown from a small size, no custom one (2-bit codes allowed)
		problem("kNucleotide", "0", "0", "0", true, "-fopenmp -pthread -Itests/benchmarks/others"),
		# stdin line by line into a buffer grown buffer by buffer, not one allocation of its size; the IUPAC complements
		problem("revComp", "0", "0", "0", true, "-pthread"),
		# a sieve of one bit per number, every prime's multiples marked; no primes known beforehand
		problem("nsieve", "13", "10", "4", false, ""),
		# the plain triple loop in i, k, j order over f64, each element summed in k order; no BLAS, no other algorithm
		problem("matMul", "1200", "300", "20", false, ""),
		# the standard alphabet with padding, encoded and decoded by the program (tables allowed); no library codec
		problem("base64", "100000000", "10000000", "10000", false, ""),
		# the words counted in the built-in or a library hash table keyed by the words; no custom hash table
		problem("wordFreq", "10000000", "1000000", "10000", false, "-Itests/benchmarks/others"),
		# the whole JSON text made and parsed back into records (built-in, library or written codec); no step skipped
		problem("jsonRecords", "500000", "50000", "500", false, ""),
		# Dijkstra over a binary heap (the language's or a library's; C, which has none, writes its own), stale
		# entries skipped when taken; no other algorithm
		problem("dijkstra", "4000", "1000", "50", false, ""),
		# one ray per pixel tested against every sphere, a shadow ray when lit; no acceleration structure
		problem("raytrace", "1200", "400", "40", false, "-ffp-contract=off"),
		# every line parsed by recursive descent into a tree of nodes allocated as binaryTrees' are, then walked
		problem("exprTree", "10000", "1000", "50", false, ""),
		# the strings themselves sorted by the built-in or a library comparison sort; no radix sort, no derived keys
		problem("strSort", "3000000", "300000", "1000", false, ""),
		# the spigot step by step (next term, the digit's two extractions, its elimination) over arbitrary
		# integers: the language's, a library's, or GMP's where the published entries call it
		problem("pidigits", "10000", "2000", "27", false, "-lgmpxx -lgmp"),
		# mandel.b interpreted over a tape of bytes (runs folded, jump targets precomputed, a list of operations
		# or a switch loop); no compiling to native code; n is the lines of output after which it stops
		problem("brainfudge", "20", "8", "1", false, ""),
		# Havlak's loop finder (union-find over the depth-first numbers) over a synthetic graph of nested and sequential
		# loops, run n times; the graph in arrays, the algorithm the paper's; no skipped runs
		problem("havlak", "200", "20", "1", false, ""),
		# an LRU cache through n puts and gets of two LCGs' keys (arguments: size n); a library hash map from key to
		# slot (khash in C) and a doubly linked list or the language's ordered map; no other eviction scheme
		problem("lru", "100000 5000000", "100000 500000", "100 10000", false, "-Itests/benchmarks/others"),
		# the first n primes by a chain of tasks joined by channels (coro-prime-sieve): a generator sends 2, 3, 4...,
		# each task holds consecutive filters (a prime and its multiples out), the primes of the tasks one after
		# the other, as many tasks as the processors less two; bounded channels of 64; no sieve array
		problem("coroPrimeSieve", "40000", "10000", "100", false, "-pthread"),
		# plb2's sudoku: 20 hard grids solved n times over by exact cover with backtracking (the 729x324 constraint
		# matrix kept as sparse arrays, the column of fewest choices taken); prints every solution
		problem("sudoku", "50", "10", "1", false, ""),
		# fasta's output on stdin; the headers and newlines taken out by a regular expression, nine variants of one
		# pattern counted and five substitutions made in turn, all by the language's regex library (PCRE2 for C and C++,
		# the regex crate, re) or std/regex; no hand-written matcher for these patterns
		problem("regexRedux", "0", "0", "0", true, "-fopenmp -pthread{" -lpcre2-8" if not onWindows() else ""}"),
		# TechEmpower's plaintext and JSON tests: a server over the language's sockets (a thread a connection) and 16
		# clients on the loopback in the same run, HTTP/1.1 kept alive and pipelined 16 requests deep, requests parsed
		# and responses framed by the programs (no HTTP library, no framework), each JSON response serialized anew
		problem(
			"httpJson",
			"250000",
			"25000",
			"64",
			false,
			"-pthread{" -lws2_32" if onWindows() else ""}"
		)
	]

# a problem with the sources that exist for it
fn problem(name str, arg str, quickArg str, smallArg str, stdin bool, flags str):
	others = ["c", "cpp", "rs", "py"]
		.map("tests/benchmarks/others/{name}.{it}")
		.filter(src: fs.exists(src))
	compare.Problem(
		name = name.copy(),
		zap = "tests/benchmarks/{name}.zap",
		others,
		arg = arg.copy(),
		quickArg = quickArg.copy(),
		smallArg = smallArg.copy(),
		stdin,
		flags = flags.copy()
	)

# the fasta output the stdin problems read at a mode's size ("full", "quick", else the small
# one), made once by the C fasta program
pub fn inputFor(mode str) str:
	size = "25000000" if mode == "full" else "2500000" if mode == "quick" else "1000"
	path = "build/benchmarks/input{size}.txt"
	if fs.exists(path): return path
	_ = fs.createDir("build/benchmarks")
	exe = compare.build("tests/benchmarks/others/fasta.c", "")
	if exe == "" or compare.runMeasured("{exe} {size}", "", path, 0).code != 0:
		exit(1, "cannot make the fasta input")
	path

# the rest of the test reads fasta's output as its stdin, as a stdin problem's programs do
pub fn feedFasta():
	stdin.feed(fs.readFile("tests/benchmarks/fasta.expected") ?? "")

# what the problem's program prints for fasta's output, in the file beside it
pub fn expectedOf(name str) str:
	fs.readFile("tests/benchmarks/{name}.expected") ?? ""

# whether the problem's programs in every language print the same bytes at the small size, the
# Zap program the test's own (its main run given the arguments: no build of its own)
pub fn agree(name str) bool:
	if not compare.hasZap():
		eprint("skipped: no zap where the tests run, to build the Zap program (the bench compares them)")
		return true
	all = problems()
	i = all.findIndex(.name == name) ?? return false
	all[i].agree(inputFor("small") if all[i].stdin else "", exePath())
