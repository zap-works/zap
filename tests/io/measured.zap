# zap test's measured kinds: size, bench and shots, each run by zapPath() test on a small
# repository of its own made in the test's dir (a dir holding .git, which keeps the
# baselines and the pictures). Only what does not vary from run to run is printed: the exit code
# and the state and key of each measure's line.

import fs

# a repository of its own holding the files (path, text): its root
fn repository(name str, files (str, str)[]):
	root = "{testDir()}{name}"
	_ = fs.createDir("{root}/.git")
	for (path, text) in files:
		_ = fs.writeFile("{root}/{path}", text)
	root

# the measures of the processor's counts, which a bench has only where the processor counts
# (Linux): left out, so that the lines are the same everywhere
processorCounts = ["instructions", "cachemisses", "branchmisses"]

# zap test with the arguments (gpu in ZAP_RUN set to gpu unless it is ""), its bench measured here: its
# exit code, and of each line whose first word is one of the words, that many words
fn zapTest(arguments str, gpu str, words str[], count i64):
	vars = [hereBench]
	if gpu != "":
		vars.push(runAssignment("gpu={gpu}"))
	tested = Process.output("{zapPath()} test --jobs 1 {arguments}", vars = vars)
	said = ["exit {tested.code}"]
	for line in tested.out.lines():
		w = line.trimmed().split(" ").filter(it != "")
		if not w.isEmpty and w[0] in words and (w.len < 3 or w[2] not in processorCounts):
			said.push(w[..count.min(len)].join(" "))
	said.join("\n")

# the bench measured on this machine, whatever the caller's environment names
hereBench = "ZAP_SETUP="

# a baseline's lines that are not the size of a section (those the compiler may add or rename)
fn baselineKeys(path str):
	(fs.readFile(path) ?? "")
		.lines()
		.filter(it != "" and " ." not in it)
		.map(.split(" ")[0..2].join(" "))
		.join(", ")

test "size measures a program's build against size.baseline, which only gets better":
	root = repository("size", [("hello.zap", "# zap test --only size\nprint(\"hello\")\n")])
	_ = fs.deleteFile("{root}/baselines/size.baseline")
	print(
		zapTest("{root} --only size", "", ["new"], 3)
			.lines()
			.filter("build" in it or "functions" in it or "exit" in it)
			.join("\n")
	)
	print(zapTest("{root} --only size --update", "", ["WORSE"], 3))
	print(baselineKeys("{root}/baselines/size.baseline"))
	# a baseline that the build beats by far but whose functions it exceeds
	kept = (fs.readFile("{root}/baselines/size.baseline") ?? "")
		.lines()
		.map(
			"hello.zap functions 1" if .startsWith("hello.zap functions")
			else "hello.zap build 100.00" if .startsWith("hello.zap build")
			else .copy()
		)
		.join("\n")
	_ = fs.writeFile("{root}/baselines/size.baseline", kept)
	print(zapTest("{root} --only size", "", ["WORSE"], 3))
	print(
		zapTest(
			"{root} --only size --update \"one more for the test\"",
			"",
			["slower", "WORSE"],
			3
		)
	)
	line = (fs.readFile("{root}/baselines/size.baseline") ?? "")
		.lines()
		.filter(.startsWith("hello.zap functions"))
		.join("")
	print("{line.split(" ")[0..2].join(" ")}, {line.split("  # ")[1]}")
	prints """
		exit 0
		new hello.zap build
		new hello.zap functions
		exit 0
		hello.zap build, hello.zap exe, hello.zap functions, hello.zap peak
		exit 1
		WORSE hello.zap functions
		exit 0
		slower hello.zap functions
		hello.zap functions, slower: one more for the test
		"""

# a size entry that writes the program measured in its place (out/w.zap, made under its root)
writer = "# zap test --only size\n# writes: out/w.zap (the program measured)\nimport fs\n\n_ = fs.createDir(fs.dirOf(args[0]))\n_ = fs.writeFile(args[0], \"print(2)\\n\")\n"

test "size measures the program an entry's `writes:` line names, after running the entry":
	root = repository("writes", [("w.zap", writer)])
	_ = fs.deleteFile("{root}/baselines/size.baseline")
	said = zapTest("{root} --only size", "", ["new"], 3)
	print(said.lines().filter("functions" in it or "exit" in it).join("\n"))
	print(fs.exists("{root}/out/w.zap"))
	prints """
		exit 0
		new w.zap functions
		true
		"""

# a suite that prints a `bench` line of its time per ratio in ratios.txt (its rival stubbed: 100
# cycles), of its tokens with --tokens
benchSuite = "# zap test --only bench\nimport fs\n\nprint(\"a table line\")\nmeasure = \"tokens\" if \"--tokens\" in args else \"time\"\nfor i, r in (fs.readFile(\"ratios.txt\") ?? \"\").trimmed().split(\" \"):\n\tprint(\"bench\\tcase\{i}\\t\{measure}\\t\{r}\\t100\\tc\\tcase.zap\\t1\\t\")\n"

test "bench keeps each case's ratio in bench.baseline: better is locked, worse fails or is accepted with a reason":
	root = repository("bench", [("suite.zap", benchSuite), ("ratios.txt", "150 300")])
	_ = fs.deleteFile("{root}/baselines/bench.baseline")
	states = ["a", "new", "ok", "better", "WORSE", "slower", "above"]
	print(zapTest("{root} --only bench", "", states, 5))
	prints """
		exit 0
		a table line
		new case0 time quick 1.50
		new case1 time quick 3.00
		"""
	print(zapTest("{root} --only bench --update", "", ["WORSE"], 5))
	print((fs.readFile("{root}/baselines/bench.baseline") ?? "").trimmedEnd())
	prints """
		exit 0
		case0 time quick 1.50
		case1 time quick 3.00
		"""
	_ = fs.writeFile(
		"{root}/baselines/bench.baseline",
		"target 2.00\n{fs.readFile("{root}/baselines/bench.baseline") ?? ""}"
	)
	_ = fs.writeFile("{root}/ratios.txt", "170 290")
	print(zapTest("{root} --only bench", "", states, 5))
	prints """
		exit 0
		a table line
		ok case0 time quick 1.70
		better case1 time quick 2.90
		above the target 2.00, worst
		"""
	_ = fs.writeFile("{root}/ratios.txt", "200 290")
	print(zapTest("{root} --only bench", "", states, 5))
	prints """
		exit 1
		a table line
		WORSE case0 time quick 2.00
		better case1 time quick 2.90
		above the target 2.00, worst
		"""
	print(zapTest("{root} --only bench --update \"a reason\"", "", states, 5))
	print((fs.readFile("{root}/baselines/bench.baseline") ?? "").trimmedEnd())
	prints """
		exit 0
		a table line
		slower case0 time quick 2.00
		better case1 time quick 2.90
		above the target 2.00, worst
		target 2.00
		case0 time quick 2.00  # slower: a reason
		case1 time quick 2.90
		"""
	print(zapTest("{root} --only bench --full", "", ["new"], 5))
	prints """
		exit 0
		new case0 time full 2.00
		new case1 time full 2.90
		"""

test "tokens keeps each case's tokens ratio in bench.baseline beside the bench's own":
	root = repository("tokens", [("suite.zap", benchSuite), ("ratios.txt", "150 300")])
	_ = fs.deleteFile("{root}/baselines/bench.baseline")
	print(zapTest("{root} --only tokens --update", "", ["new"], 4))
	_ = fs.writeFile("{root}/ratios.txt", "140 310")
	print(zapTest("{root} --only tokens", "", ["better", "WORSE"], 4))
	print(zapTest("{root} --only bench", "", ["new"], 5))
	prints """
		exit 0
		new case0 tokens 1.50
		new case1 tokens 3.00
		exit 1
		better case0 tokens 1.40
		WORSE case1 tokens 3.10
		exit 0
		new case0 time quick 1.40
		new case1 time quick 3.10
		"""

# a repository with a suite racing tiny.zap against the rivals (file names, texts)
fn tinySuite(name str, rivals (str, str)[]):
	names = []
	for (file, _) in rivals:
		names.push("\"{file}\"")
	suite = "# zap test --only bench\nimport compare\n\ncompare.suite([compare.Problem(name = \"tiny\", zap = \"tiny.zap\", others = [{names.join(", ")}], arg = \"300\", quickArg = \"200\", smallArg = \"100\", stdin = false, flags = \"\")], mode: \"\", args)\n"
	files = [("suite.zap", suite), ("tiny.zap", "n = i64.parse(args[0]) ?? 0\nprint(n * n)\n")]
	files.extend(rivals.copy())
	repository(name, files)

test "a suite of std/compare races a Zap program against its C rival":
	cSource = "#include <stdio.h>\n#include <stdlib.h>\n#ifdef _WIN32\n#include <fcntl.h>\n#include <io.h>\n#endif\nint main(int c, char **v) \{ long n = atol(v[1]);\n#ifdef _WIN32\n_setmode(_fileno(stdout), _O_BINARY);\n#endif\nprintf(\"%ld\\n\", n * n); return 0; }\n"
	root = tinySuite("race", [("tiny.c", cSource)])
	_ = fs.deleteFile("{root}/baselines/bench.baseline")
	print(zapTest("{root} --only bench", "", ["new"], 3))
	print(zapTest("{root} --only tokens", "", ["new"], 3))
	prints """
		exit 0
		new tiny time
		new tiny memory
		new tiny exe
		exit 0
		new tiny tokens
		"""

test "a rival past the memory of ZAP_SETUP is out of memory and the suite goes on to the next language":
	hog = "#include <stdlib.h>\n#include <string.h>\nint main(int c, char **v) \{ for (;;) \{ char *p = malloc(1 << 20); if (!p) return 1; memset(p, 1, 1 << 20); } }\n"
	python = "import sys\nn = int(sys.argv[1])\nsys.stdout.buffer.write(str(n * n).encode() + b\"\\n\")\n"
	root = tinySuite("oom", [("tiny.c", hog), ("tiny.py", python)])
	_ = fs.deleteFile("{root}/baselines/bench.baseline")
	tested = Process.output(
		"{zapPath()} test --jobs 1 {root} --only bench",
		vars = ["ZAP_SETUP=memory=64"]
	)
	print("exit {tested.code}")
	for line in tested.out.lines():
		if line.startsWith("tiny "):
			print("{"out of memory" in line} {line.trimmedEnd().endsWith("ok")}")
	prints """
		exit 0
		true true
		"""

test "an A/B races on the ssh machine by the processor's counts, or is skipped, said":
	root = tinySuite("remoteab", [])
	base = "{currentDir()}/{zapPath()}"
	tested = Process.output(
		"{zapPath()} test --jobs 1 {root} --only bench",
		vars = [runAssignment("ab={base}")]
	)
	said = tested.out
	print(tested.code == 0 and ("instructions" in said or "does not answer" in said))
	prints "true"

# a program whose --shot picture is gray at the level in level.txt
shotProgram = "# A picture of one gray.\n#\n#   zap run app.zap --shot gray.png    (its level from level.txt)\nimport fs\nimport image\n\nlevel = u8(i64.parse((fs.readFile(\"level.txt\") ?? \"\").trimmed()) ?? 0)\nmut pixels u8[] = []\nloop 64:\n\tpixels.extend([level, level, level, 255])\n_ = image.fromBytes(8, 8, pixels).savePng(args.option(\"--shot\") ?? \"\")\n"

test "shots runs each scripted run and compares its picture with the run before":
	root = repository("shots", [("app.zap", shotProgram), ("level.txt", "10")])
	for gpu in ["vulkan", "d3d12"]:
		_ = fs.deleteFile("{root}/build/shots/app/gray.{gpu}.kept.png")
	states = ["first", "same", "DIFFERS", "kept", "shots:", "FAILED"]
	print(zapTest("{root} --only shots", "", states, 5))
	print(zapTest("{root} --only shots", "vulkan", states, 5))
	prints """
		exit 0
		first app.zap --shot gray.png (vulkan):
		first app.zap --shot gray.png (d3d12):
		shots: 2 pictures
		exit 0
		same app.zap --shot gray.png (vulkan)
		shots: 1 pictures
		"""
	_ = fs.writeFile("{root}/level.txt", "200")
	print(zapTest("{root} --only shots", "vulkan", states, 5))
	print(fs.exists("{root}/build/shots/app/gray.vulkan.diff.png"))
	print(zapTest("{root} --only shots --update", "vulkan", states, 5))
	print(zapTest("{root} --only shots", "vulkan", states, 5))
	prints """
		exit 1
		DIFFERS app.zap --shot gray.png (vulkan):
		shots: 1 pictures
		true
		exit 0
		kept new app.zap --shot gray.png
		shots: 1 pictures
		exit 0
		same app.zap --shot gray.png (vulkan)
		shots: 1 pictures
		"""

# a program that saves one picture a scene beside its --shot path (gray-one.png, gray-two.png)
sceneProgram = "# A picture a scene.\n#\n#   zap run app.zap --shot gray.png\nimport image\n\npath = args.option(\"--shot\") ?? \"\"\nfor (scene, level) in [(\"one\", u8(10)), (\"two\", u8(200))]:\n\tpixels u8[] = []\n\tloop 64:\n\t\tpixels.extend([level, level, level, 255])\n\t_ = image.fromBytes(8, 8, pixels).savePng(\"\{path[..path.len - 4]}-\{scene}.png\")\n"

test "shots keeps each picture of a run that saves one a scene":
	root = repository("scenes", [("app.zap", sceneProgram)])
	for gpu in ["vulkan", "d3d12"]:
		_ = fs.deleteFile("{root}/build/shots/app/gray.{gpu}-one.kept.png")
	states = ["first", "same", "DIFFERS", "shots:", "FAILED"]
	print(zapTest("{root} --only shots", "vulkan", states, 7))
	print(zapTest("{root} --only shots", "vulkan", states, 7))
	prints """
		exit 0
		first app.zap --shot gray.png (vulkan) gray.vulkan-one.png: kept
		first app.zap --shot gray.png (vulkan) gray.vulkan-two.png: kept
		shots: 1 pictures
		exit 0
		same app.zap --shot gray.png (vulkan) gray.vulkan-one.png
		same app.zap --shot gray.png (vulkan) gray.vulkan-two.png
		shots: 1 pictures
		"""

test "shots skips a file whose header needs a path that is missing":
	root = repository(
		"needs",
		[("app.zap", "# A picture.\n#\n#   needs: game/disc.iso, level.txt (the user's own)\n#   zap run app.zap --shot gray.png\n"), ("level.txt", "10")]
	)
	print(zapTest("{root} --only shots", "vulkan", ["skipped", "shots:", "FAILED"], 5))
	prints """
		exit 0
		skipped app.zap: needs game/disc.iso, which
		shots: 0 pictures
		"""
