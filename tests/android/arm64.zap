# `zap build --target linux-arm64`: AArch64 code in a static ELF for Linux on arm64, run on the arm64
# machine arm64 in ZAP_SETUP names over ssh, the program handed to it on stdin and
# taken away after the run. Skipped, with a line on stderr, where no such machine answers.

import fs

armHost = benchHost()

# why the tests are skipped when they are
fn armSkipped():
	if armHost == "": return "skipped: no arm64 machine (arm64 in ZAP_SETUP names none)"
	"skipped: no arm64 machine answers over ssh at {armHost}"

armRuns = armHost != "" and
	Process.output("ssh -o BatchMode=yes -o ConnectTimeout=10 {armHost} true").code == 0

# the program built for linux-arm64 and run on arm64 Linux: what it wrote, both streams, then its
# exit code
fn onArm(stem str, program str):
	src = "{testDir()}{stem}.zap"
	_ = fs.writeFile(src, program)
	built = Process.output("{zapPath()} build --target linux-arm64 {src}")
	if built.code != 0: return "not built: {built.out}"
	p = "zap-a64/{stem}"
	run = "mkdir -p zap-a64 && cat > {p} && chmod +x {p} && nice -n 19 timeout -s KILL 60 ./{p}; c=$?; rm -f {p}; exit $c"
	ran = Process.output(
		"ssh -o BatchMode=yes {armHost} \"{run}\"",
		input = fs.readFile("{buildsDir()}{stem}") ?? ""
	)
	said = withoutDir(ran.out.replace("\r\n", "\n"), testDir())
	"{said}exit {ran.code}"

test "integers, calls and loops":
	if not armRuns:
		eprint(armSkipped())
		return
	program = r"""
		fn fib(n i64) i64:
			if n < 2: return n
			fib(n - 1) + fib(n - 2)

		fn gcd(a i64, b i64) i64:
			if b == 0: return a
			gcd(b, a % b)

		fn weigh(a i64, b i64, c i64, d i64, e i64, f i64, g i64) i64:
			a + 2 * b + 3 * c + 4 * d + 5 * e + 6 * f + 7 * g

		fn steps(n0 i64) i64:
			n = n0
			count = 0
			while n != 1:
				n = n / 2 if n % 2 == 0 else 3 * n + 1
				count += 1
			count

		mut primes = 0
		for n in 2..10_000:
			d = 2
			prime = true
			while d * d <= n:
				if n % d == 0:
					prime = false
					break
				d += 1
			if prime: primes += 1
		print("{fib(25)} {gcd(1071, 462)} {weigh(1, 2, 3, 4, 5, 6, 7)} {steps(27)} {primes}")
		print("{-7 / 2} {-7 % 2} {7 / -2} {1 << 40} {-1024 >> 3} {0xF0 | 0x0F} {0xFF ^ 0x0F} {6 & 3}")
		x u8 = 250
		y i32 = -2_000_000_000
		big = 9_223_372_036_854_775_807
		print("{x + 5} {y - 147_483_648} {big} {-big / 3} {big % 1000}")
		exit(7)
		"""
	print(onArm("arm64calls", program))
	prints """
		75025 21 140 111 1229
		-3 -1 -3 1099511627776 -128 255 240 2
		255 -2147483648 9223372036854775807 -3074457345618258602 807
		exit 7
		"""

test "structs and lists":
	if not armRuns:
		eprint(armSkipped())
		return
	program = r"""
		type Point:
			x i64
			y i64

		type Path:
			name str
			points Point[]

		fn length(p Path) i64:
			total = 0
			for i in 1..p.points.len:
				total += (p.points[i].x - p.points[i - 1].x).abs() + (p.points[i].y - p.points[i - 1].y).abs()
			total

		fn flipped(move p Point) Point:
			Point(x = p.y, y = p.x)

		mut path = Path(name = "walk", points = [])
		for i in 0..5:
			path.points.push(Point(x = i * i, y = 10 - i))
		print("{path.name} {path.points.len} {length(path)} {flipped(path.points[2])}")
		mut grid i64[,] = []
		for r in 0..3:
			grid.push((0..4).map(r * 10 + it))
		print(grid)
		mut words = ["pear", "fig", "apple"]
		words.push("kiwi")
		print("{words.sorted()} {words.map(.len)} {words.filter(.len > 3).join("+")}")
		nums = (0..1000).map(it * 7 % 101)
		print("{nums.sum()} {nums.max()} {nums.filter(it > 95).len} {nums[999]}")
		"""
	print(onArm("arm64lists", program))
	prints """
		walk 5 20 Point(x = 8, y = 4)
		[[0, 1, 2, 3], [10, 11, 12, 13], [20, 21, 22, 23]]
		["apple", "fig", "kiwi", "pear"] [4, 3, 5, 4] pear+apple+kiwi
		49875 some(100) 50 24
		exit 0
		"""

test "a check that fails stops the program at its place":
	if not armRuns:
		eprint(armSkipped())
		return
	program = r"""
		xs = [1, 2, 3]
		mut i = 0
		while i < 5:
			print(xs[i])
			i += 1
		"""
	print(onArm("arm64check", program))
	prints """
		1
		2
		3
		zap: error[index-out-of-bounds]: index out of bounds
		  at main (arm64check.zap:4:2)
		exit 3
		"""

# a recompiler's shape: one function of 15,000 labels in a loop over a match, each arm a few checked
# reads, so the function passes 1 MB and its conditional branches must reach its far end
fn farProgram():
	arms = (0..15_000).map(
		k: "\t\t\t{k}:\n\t\t\t\ttotal = (total * 31 + xs[{k % 7}] + {k}) % 1_000_003\n\t\t\t\txs[{(k + 3) % 7}] = total % 1000\n\t\t\t\tlabel = {k + 1}"
	)
	lines = [
		"fn far(mut xs i64[]) i64:",
		"\ttotal = 0",
		"\tlabel = 0",
		"\twhile true:",
		"\t\tmatch label:",
		arms.join("\n"),
		"\t\t\t_: return total",
		"",
		"fn near(mut xs i64[]) i64:",
		"\ttotal = 0",
		"\tfor k in 0..15_000:",
		"\t\ttotal = (total * 31 + xs[k % 7] + k) % 1_000_003",
		"\t\txs[(k + 3) % 7] = total % 1000",
		"\ttotal",
		"",
		"a = [1, 2, 3, 4, 5, 6, 7]",
		"b = [1, 2, 3, 4, 5, 6, 7]",
		"print(far(a) == near(b))"
	]
	lines.join("\n")

test "a function past 1 MB branches to its far end":
	if not armRuns:
		eprint(armSkipped())
		return
	expect onArm("far", farProgram()) == "true\nexit 0"
