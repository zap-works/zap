# 8. Modules and dependencies
#
# A dir is a module: its `.zap` files (and `.zapx` ones, 7.11) share it, with no `package` line;
# so is a file alone beside the program, `tiny.zap` where there is no dir `tiny/`, but a program
# (a nested `a.tiny`, a dir above, a dependency and std are dirs). `parts` adds files and dirs to
# a module (*Parts*).
# `pub` exports; import cycles are rejected. `import json` reads the module's names through it
# (`json.parse`): where a name comes from is seen at each use and found by one search. A prefix
# nothing of the file binds is the module of that name as if the file imported it: the one an
# `import` of it finds, else the one module whose dir has that name under the program's root, the
# libraries or std (`esm.openEsm` reads skyrim.esm). zap fmt writes each file's import lines so,
# and takes out one the file never names; a prefix no module has is an error naming the modules
# that come close.
# `from fs import stem, fileName as nameOf` brings those public names into the file, read bare
# (`stem(path)`, `nameOf(path)`; in parentheses over several lines), to save the prefix where a
# file uses a module's names on every line (a .zapx file has zapx's so, 7.11); the module itself
# is not named by it. A name the module does not declare, or one the file's module declares or
# another from-import of the file brings, is an error at the import.

import fs
import json
from fs import stem, fileName as nameOf

test "a module's names are read through it":
	doc = json.parse("\{\"n\": 2}") ?? fail
	expect (doc.number(doc.root, "n") ?? 0.0) == 2
	expect fs.fileName("a/b.txt") == "b.txt"
	expect fs.stem("a/b.txt") == "b"
	expect fs.extension("a/b.txt") == ".txt"
	expect fs.dirOf("a/b.txt") == "a"

test "a from-import's names are read bare, a renamed one by its new name":
	expect stem("a/b.txt") == "b"
	expect nameOf("a/b.txt") == "b.txt"
	expect fs.stem("c.d") == "c"

test "a prefix the file does not import is its module" for (source, shown) in [
	("print(fs.dirOf(\"a/b\"))\n", "a"),
	("print(json.intAt(\"[42]\", 1) ?? 0)\n", "42")
]:
	expect besideApp("prefix", "unused", "pub fn unused() i64:\n\t1\n", source) == shown

test "a prefix no module has" refuses UnknownModule:
	print(jsno.parse("1") != none)

test "a from-import of a name the file has" refuses AmbiguousImport:
	from fs import stem
	fn stem(s str) str:
		s.copy()
	print(stem("a"))

test "a from-import of a private name" refuses PrivateName:
	from fs import ignoredDirs
	print(ignoredDirs("."))

# `import a.b` loads the dir `a/b/`, used by its last segment (`b.thing`), found in this order:
# under the program's root (the entry file's dir; import paths are relative to it, never to the
# importing file); beside the standard library, at the root of the compiler's repository (the
# libraries `engine/` and `rhi/`, so a program anywhere imports them); in the standard library,
# `std/`; in a dir above the root, so programs side by side share a library beside them. A
# program needs no repository: a script in any dir runs the same.
# (tests/programs and tests/errors hold programs of several modules: methods, privfn, samenames,
# parts, parttwice.)
# what a program in the dir `app` of a scratch dir prints, the module `lib` beside `app` holding
# source (outside every repository, as a script anywhere)
fn besideApp(name str, lib str, source str, main str):
	base = "{env.get("TEMP") ?? env.get("TMPDIR") ?? "/tmp"}/zap-spec-{name}"
	_ = fs.createDir("{base}/{lib}")
	_ = fs.createDir("{base}/app")
	_ = fs.writeFile("{base}/{lib}/{lib}.zap", source)
	_ = fs.writeFile("{base}/app/main.zap", main)
	ran = Process.output("{zapPath()} run {base}/app/main.zap")
	_ = fs.deleteTree(base)
	ran.out.trimmed().copy()

test "a standard module is found before a dir of its name above the program":
	main = "import fs\n\nprint(fs.dirOf(\"a/b\"))\n"
	print(besideApp("stray", "fs", "pub fn stray() i64:\n\t1\n", main))
	prints "a"

test "a script in any dir imports a library beside its dir":
	main = "import shapes\n\nprint(shapes.sides())\n"
	print(besideApp("beside", "shapes", "pub fn sides() i64:\n\t4\n", main))
	prints "4"

# Parts. `parts lex, check`, a top-level line, makes the file `lex.zap` and the dir `check/` beside
# the file that names them part of its module, the entry file's (the program) or a module's: the
# dir's every source, its subfolders' too. A part's names are the module's, seen bare with no
# `pub` or import, as one dir's files see each other; its imports and its own `parts` lines are the
# module's too. A name that is both a file and a dir beside it is an error (PartTwice). A subfolder of a
# module's dir that no `parts` line names is a module nested in it.

# The prelude: the runtime (`runtime/`, module `rt`) is in every program without an import: the core
# types and their methods, printing and formatting, processes, encoding, threads and channels, and
# the tests. `rt.name` names the runtime's even where a declaration of the module hides it. The
# standard library is what reaches outside the process (`fs`, `net`, `win`, `gpu`), the formats
# (`json`, `image`, `deflate`, `zapx`), `math`, `tensor`, `digest`, `regex` and `compare`; a new library
# goes to `std/` when a program names it to use it, to the runtime when it is a type or a method
# nearly every program may meet (its names are seen everywhere, so `args.flag` rather than a bare
# `flag`).
# A module of the standard library reaches the runtime's private functions too (`rt.openForRead`):
# the runtime keeps the system calls, std the API over them. A type's own functions are the
# runtime's named after it (14.1), and `zap doc runtime` lists what a program may call: the
# runtime's helpers for the code the compiler derives and for std are private.
fn clockMs():
	-1

test "rt names the runtime's own where a declaration hides it":
	expect clockMs() == -1
	expect rt.clockMs() >= 0

test "the working directory and the executable":
	expect currentDir().len > 0
	expect exePath().endsWith(exeSuffix()) and (exeSuffix() == ".exe") == onWindows()

# `args` is the command-line arguments after the program's name, a `str[]` read in place (a value,
# not a call). `arg(i, default)` is the i-th argument read as the default's type, an integer, a
# float or text: the default only when the argument is missing, while one given that does not
# parse stops the program with a runtime error naming it. The default is evaluated first, always.
# `args`' methods read options, switches and the positional words (`zap doc runtime`). A program
# declares its options once, `args.options([ArgOption(name, takesValue, help)])`: `args.positional()`
# skips the word after each option that takes a value, and `args.usage()` is one line a declared
# option. Without a declaration no option takes a value.
test "options, switches and numbers":
	args.set(
		[
			"--port",
			"7000",
			"--uncapped",
			"--scale",
			"4.5",
			"--bad",
			"x",
			"--hex",
			"0x10",
			"--at",
			"1.5,?,-2"
		]
	)
	print("{args.option("--port") ?? "-"} {args.option("--missing")} {args.hasFlag("--uncapped")} {args.hasFlag("--port7000")}")
	print("{i64.parse(args.option("--frames") ?? "") ?? 60} {f64.parse(args.option("--scale") ?? "") ?? 1.0} {i64.parse(args.option("--bad") ?? "") ?? -1} {i64.parse(args.option("--hex") ?? "") ?? 0}")
	print(args.optionNumbers("--at"))
	prints """
		7000 none true false
		60 4.5 -1 16
		[1.5, 0, -2]
		"""

test "arg reads an argument as the default's type":
	args.set(["7", "2.5", "word", "300"])
	n = arg(0, 100)
	size i32 = arg(0, 100)
	scale = arg(1, 1.0)
	name = arg(2, "none")
	print("{n} {size} {scale} {name} {arg(4, 5)} {arg(5, "none")} {arg(6, 0.5)}")
	small u16 = arg(3, 9)
	print(small)
	prints """
		7 7 2.5 word 5 none 0.5
		300
		"""

test "a given argument that is no number stops the program" stops Failure("argument 1 is not a number: word"):
	args.set(["3", "word"])
	print(arg(0, 1) + arg(1, 2))

test "positional words skip the options and the values they take":
	args.set(["--iso", "disc.iso", "recipe", "--verbose", "wheel"])
	args.options(
		[ArgOption("--iso", true, "the disc image"), ArgOption("--verbose", false, "say more")]
	)
	expect args.positional() == ["recipe", "wheel"]

test "an undeclared option takes no value":
	args.set(["--iso", "disc.iso", "recipe"])
	expect args.positional() == ["disc.iso", "recipe"]

test "a switch declared without a value leaves the next word positional":
	args.set(["--verbose", "wheel"])
	args.options([ArgOption("--verbose", false, "say more")])
	expect args.positional() == ["wheel"]

test "usage lists the declared options":
	args.options(
		[ArgOption("--iso", true, "the disc image"), ArgOption("--verbose", false, "say more")]
	)
	expect args.usage() == "  --iso value  the disc image\n  --verbose  say more"

test "args is a value" refuses ArgsIsValue:
	print(args().len)

# `env` is the environment variables as a map: an index stops when the variable is not set, and a
# write holds for this process and the ones it starts.
test "the environment is a map":
	env["ZAP_SPEC_MODULES"] = "set"
	expect env["ZAP_SPEC_MODULES"] == "set"
	expect env.get("ZAP_SPEC_MODULES_NONE") == none

test "an absent environment variable read by index stops the program" stops Failure("the environment variable ZAP_SPEC_MODULES_NONE is not set"):
	print(env["ZAP_SPEC_MODULES_NONE"])

# `Process.start(cmd)` starts a `Process` from a command line: `p.wait()` gives its exit code, kept
# in `p.code`, and `p.isDone` tells whether it ended. `Process.run(cmd)` starts one and waits for it,
# giving its exit code (-1 when it cannot start). `Process.output(cmd)` runs a program to its end
# with no shell between, the same on every system: the line split into words by Windows' rules
# (spaces part them, double quotes group, `\"` is a quote), the program found on the PATH. What
# it writes to stdout and stderr, one stream in the order written, is kept in `p.out`, its exit
# code in `p.code` (-1 when it cannot start); `input = text` is its stdin (empty otherwise),
# `vars = ["NAME=value"]` are set for it alone and `dir = path` is where it runs (the program still
# named from here). What a shell's redirections did is done with `p.out` itself; `shellLine(line)`
# is the line the system's shell runs (cmd, or sh), for what only a shell does (a pipeline).
# `exit(code)` ends the program, the answer to its caller, and `exit(code, message)` writes the
# line to stderr first; `fail(message)` stops the program on a bug (*Runtime errors*).
if not args.isEmpty and args[0] == "quit":
	exit(3, "quit: asked to")
if not args.isEmpty and args[0] == "code":
	exit(i64.parse(args[1]) ?? 1)
if not args.isEmpty and args[0] == "where":
	print(currentDir().replace("\\", "/"))
	exit(0)
if not args.isEmpty and args[0] == "echo":
	print(args[1..].join("|"))
	eprint("stderr {env.get("ZAP_SPEC_OUTPUT") ?? "unset"}")
	print("stdin {stdin.all()}")
	exit(5)

test "a process is a value":
	p = Process.start("\"{exePath()}\" code 4")
	expect p.wait() == 4
	expect p.code == 4
	expect p.isDone
	expect Process.run("\"{exePath()}\" code 0") == 0

test "Process.output keeps what a program writes":
	p = Process.output(
		"\"{exePath()}\" echo \"a b\" c\\\"d",
		input = "given",
		vars = ["ZAP_SPEC_OUTPUT=set"]
	)
	print("{p.code} {p.out.trimmed()}")
	print(Process.output("zap-spec-no-such-program").code)
	there = Process.output("\"{exePath()}\" where", dir = testDir()).out.trimmed()
	expect "{there}/" == testDir()
	prints """
		5 a b|c"d
		stderr set
		stdin given
		-1
		"""

test "exit gives its code and writes its line to stderr first":
	p = Process.output("\"{exePath()}\" quit")
	print("{p.code} {p.out.trimmed()}")
	prints "3 quit: asked to"

# `clockMs()` and `clockSeconds()` count from one fixed point, by the processor's counter.
test "the clocks count forward from one fixed point":
	s0 = clockSeconds()
	m0 = rt.clockMs()   # this file's clockMs hides the runtime's
	sleepMs(20)
	expect clockSeconds() - s0 >= 0.015 and rt.clockMs() - m0 >= 15

# `random(range)` draws a number of the range's type from the program's sequence; a `Random(seed)`
# is a sequence of its own, the same for its seed.
test "random numbers take a range; a sequence of its own repeats for its seed":
	a = Random(7)
	b = Random(7)
	xs = (0..5).map(_: a.next(0..100))
	ys = (0..5).map(_: b.next(0..100))
	expect xs == ys and xs.all(it >= 0 and it < 100)
	expect (0..100).all(_: random(1..=6) in [1, 2, 3, 4, 5, 6])
	f = random(0.0..0.5)
	expect f >= 0.0 and f < 0.5
	small i32 = random(1..=3)
	expect small >= 1 and small <= 3

test "random from an empty range stops the program" stops Failure("random from an empty range 5..5"):
	print(random(5..5))

test "random takes a range with both ends" refuses RandomRange:
	print(random(5))

# `sleepMs(n)` gives the processor to the other threads for n milliseconds. `allocations()`,
# `memoryCommitted()`, `peakMemory()` and `processorCycles()` measure the process.
test "processors and memory":
	expect cpuCount() >= 1
	before = allocations()
	xs = [1, 2, 3].map(it * 2)
	expect allocations() > before and xs.len == 3
	expect peakMemory() > 0 and memoryCommitted() > 0 and processorCycles() > 0 and
		processorSeconds() >= 0.0

# `Heap<T Ord>()` is a priority queue, `pop()` giving the smallest first.
test "a heap gives its values smallest first":
	h = Heap<i64>()
	for v in [5, 3, 8, 1, 2]:
		h.push(v)
	print("{h.len - 2} {h.first} {h.isEmpty}")
	out = []
	while h.pop() is v:
		out.push(v)
	print("{out} {h.pop()}")
	words = Heap<str>()
	for w in ["c", "a", "b"]:
		words.push(w)
	print([words.pop() ?? "", words.pop() ?? "", words.pop() ?? ""])
	pairs = Heap<(i64, str)>()
	pairs.push((2, "a"))
	pairs.push((1, "z"))
	print("{pairs.pop() ?? (0, "")} {pairs.pop() ?? (0, "")}")
	prints """
		3 some(1) false
		[1, 2, 3, 5, 8] none
		["a", "b", "c"]
		(1, "z") (2, "a")
		"""

# Raw bytes are methods of a `u8[]` (and the readers and writers a `u8[N]`'s): numbers at an offset
# in the width and byte order the name says (`u32le`, `setI16be`, `pushF64be`), each one load or
# store. Bytes past the end stop the program.
test "numbers written in place, in a list and in a fixed array":
	d u8[] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
	d.setU32le(0, 0xAABB_CCDD)
	d.setU16be(4, 0x1234)
	d.setU64be(2, 0x0102_0304_0506_0708)
	print(d)
	a u8[16]
	a.setU32be(3, 0xDEAD_BEEF)
	print("{a.u32le(3):x} {a.u16be(3):x} {a.u64le(0):x}")
	prints """
		[221, 204, 1, 2, 3, 4, 5, 6, 7, 8]
		efbeadde dead efbeadde000000
		"""

test "a read past the end stops the program" stops IndexOutOfBounds:
	d u8[] = [1, 2, 3, 4, 5]
	print(d.u32le(args.len + 2))

test "numbers read from bytes and written to them":
	out = []
	out.extend("RIFF".bytes())
	out.pushU32le(0x0102_0304)
	out.pushI16be(-2)
	out.pushF64be(1.5)
	out.extend("ok\0".bytes())
	print("{out.u32le(4)} {out.u32be(4)} {out.i16be(8)} {out.f64be(10)}")
	print("{out.startsWith("RIFF")} {out.matchesAt(1, "RIFF")} {out.cStringAt(18)}")
	dna = "GATTACA".bytes().copy()
	dna.translate("ACGT".translationTable("TGCA"))
	print(str(move dna))
	half u8[] = [0x00, 0x3C, 0xC0, 0x00]
	print("{half.f16le(0)} {half.f16be(2)}")
	prints """
		16909060 67305985 -2 1.5
		true false ok
		CTAATGT
		1 -2
		"""

# `PackedParts.pack(magic, version, head, body)` and `d.unpack(magic, version)` (none for another
# magic or version) frame a file. `Reader` is a cursor over bytes and `BitReader` over bits, a
# byte's lowest first or (`high`) its highest: a read past the end gives 0 and sets `short`, and
# `recordCount(bytesEach)` gives 0 when that many records would pass the bytes left, so a loop or
# a `reserve` by it never goes beyond the data.
test "a packed file and a cursor over bytes":
	packed = PackedParts.pack("ZNRK", 3, [1, 2], [9])
	if packed.unpack("ZNRK", 3) is p:
		print("{p.headAt} {p.bodyAt} {p.end} {packed[p.bodyAt]}")
	print(packed.unpack("ZNRK", 4) == none)
	data = []
	data.pushU32le(7)
	data.pushVarint(-300)
	data.extend("ab".bytes())
	r = Reader(d = data)
	print("{r.u32()} {r.varint()} {str(r.cStringBytes(2))} {r.short}")
	r.u8()
	print(r.short)
	header = []
	header.pushU32le(2)
	header.pushU32le(1_000_000)
	header.extend([1, 2, 3, 4, 5, 6, 7, 8])
	h = Reader(d = header)
	print("{h.recordCount(4)} {h.short} {h.recordCount(4)} {h.short} {header.matchesAt(14, "abc")}")
	prints """
		16 18 19 9
		true
		7 -300 ab false
		true
		2 false 0 true false
		"""

# A `Reader` reads the window [at, end) (`end` defaults to the bytes' end): a read past `end`
# is short like one past the bytes. `skip(n)` passes n bytes, `vec2()`, `vec3()` and `vec4()` read
# f32 vectors and `sized()` a text of a u32 length.
test "a cursor over a window, vectors and sized text":
	data = []
	data.pushU32le(2)
	data.extend("hi".bytes())
	for v in [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]:
		data.pushF32le(f32(v))
	data.extend([7, 0, 8, 0, 9, 0])
	r = Reader(d = data)
	print("{r.sized()} {r.vec2()} {r.vec4().w}")
	print("{r.numbers(2, u16(0))} {r.short}")
	w = Reader(d = data, at = 6, end = 14)
	print("{w.vec2()} {w.short} {w.u8()} {w.short} {w.at}")
	s = Reader(d = data)
	s.skip(6)
	print("{s.vec3().z} {s.skip(100)} {s.short}")
	cut = Reader(d = data)
	print("{cut.numbers(100, u16(0))} {cut.short}")
	prints """
		hi Vec2(x = 1, y = 2) 6
		[7, 8] false
		Vec2(x = 1, y = 2) false 0 true 14
		3 18 true
		[] true
		"""

test "a cursor over bits, in either order":
	d u8[] = [0b1010_0110, 0b0000_0001]
	low = BitReader(d)
	print("{low.take(3)} {low.take(5)} {low.take(1)} {low.short}")
	high = BitReader(d, high = true)
	print("{high.peek(4)} {high.take(3)} {high.take(13)} {high.short}")
	four u8[] = [1, 2, 3, 4]
	aligned = BitReader(d = four)
	aligned.take(3)
	print("{aligned.byteAligned()} {aligned.take(8)} {aligned.take(16)} {aligned.take(8)} {aligned.short}")
	prints """
		6 20 1 false
		10 5 1537 false
		1 2 1027 0 true
		"""

# `zap doc <module>` lists each standard module's declarations, and each module's own tests check
# them.
