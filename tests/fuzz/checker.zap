# Mutates the test programs at random and checks that the compiler never crashes on them: it
# must answer with a diagnostic (exit 1) or accept the program (exit 0), never die. The cases
# that crash it are kept in build/fuzz/.
#
# The suite runs a few rounds from a fixed seed; for a long hunt:
#
#   zap run tests/fuzz/checker.zap [rounds=200] [seed=1]

import fs

# the random numbers of the programs made, a sequence each run restarts from its seed
mut rng = Random(0)

tokens = [
	"(",
	")",
	"{", "}",
	"[",
	"]",
	",",
	"=",
	"==",
	"+",
	"-",
	"*",
	"/",
	"<",
	">",
	".",
	"?",
	"??",
	"=>", "..", "fn", "type", "mut", "move", "ref", "return", "if", "else", "match", "for", "in",
	"while", "break", "continue", "none", "true", "false", "self", "test", "expect", "0",
	"1", "\"", "\"\"\"", "x", "i32", "str"]

fn pick(xs str[]):
	xs[rng.next(0..=len - 1)].copy()

fn at(n i64) i64:
	rng.next(0..=n - 1)

# one random edit: a line dropped, doubled or swapped, a token put in or taken out, the text cut
fn mutate(text str):
	lines = text.lines()
	n = lines.len
	if n == 0: return text.copy()
	kind = rng.next(0..=6)
	if kind == 0 and n > 1:
		lines.remove(at(n))
	elif kind == 1:
		i = at(n)
		pos = rng.next(0..=lines[i].len)
		lines[i] = lines[i][0..pos] + pick(tokens) + lines[i][pos..lines[i].len]
	elif kind == 2:
		i = at(n)
		if not lines[i].isEmpty:
			pos = at(lines[i].len)
			lines[i] = lines[i][0..pos] + lines[i][pos + 1..lines[i].len]
	elif kind == 3 and n > 2:
		a = at(n)
		b = at(n)
		line = lines[a].copy()
		lines[a] = lines[b].copy()
		lines[b] = line
	elif kind == 4:
		return text[..random(0..=len)].copy()
	elif kind == 5:
		i = at(n)
		lines.insert(i, lines[i].copy())
	else:
		i = at(n)
		lines[i] = lines[i].replace(
			pick(["i32", "str", "mut ", "ref ", "return ", "none", "]", ")"]),
			pick(tokens)
		)
	lines.join("\n")

a = args
rounds = (i64.parse(a[0]) ?? 200) if not a.isEmpty else 200
crashes = fuzzChecker(rounds, (i64.parse(a[1]) ?? 1) if a.len > 1 else 1)
print("{rounds} rounds, {crashes} crashes")

test "the compiler answers every mangled program without crashing":
	print("12 rounds, {fuzzChecker(12, 7)} crashes")
	prints "12 rounds, 0 crashes"

# rounds of mangled test programs checked; how many crashed the compiler
fn fuzzChecker(rounds i64, seed i64):
	rng = Random(seed)
	files = fs.walk("tests", sources = true)
	crashes = 0
	loop rounds:
		src = pick(files)
		text = fs.readFile(src) ?? ""
		loop rng.next(1..=3):
			text = mutate(text)
		path = "{testDir()}case.zap"
		_ = fs.writeFile(path, text)
		checked = Process.output("{zapPath()} test --only check {path}")
		if checked.code != 0 and checked.code != 1:
			crashes += 1
			kept = "build/fuzz/crash{crashes}.zap"
			_ = fs.createDir("build/fuzz")
			_ = fs.writeFile(kept, text)
			said = checked.out.trimmed()
			eprint("CRASH exit={checked.code} from {src} -> {kept}\n  {said[..len.min(300)]}")
	crashes
