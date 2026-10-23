# Sets Mario's ticks in the rewrite (--trace) beside the port's (BENCH_TRACE) and reports where
# they first part. The test runs both for a walk of 160 ticks and needs the cartridge dump
# (projects/mario/rom/sm64.us.z64) and the PC port built (projects/mario/README.md); without them it says so
# and passes. From the repository's root: zap test projects/mario/bench/trace.zap
# The port's tick 0 is Mario before his first input; the rewrite's tick 0 is after it.
# A line is "tick N" then named fields, each followed by its numbers (pos x y z, forward v, ...);
# every field both sides print is compared: angles and integers exactly, other numbers to 0.01.

import fs
import sm64ex

# a number of a field: an integer (decimal or 0x hexadecimal) or a float, with how it prints
type Number:
	isInt bool
	value f64   # the float, or the integer as a float
	whole i64   # the integer
	shown str

# a named field and its numbers, in the order the line gives them
type Field:
	name str
	numbers Number[]

angles = ["yaw", "camera", "pitch", "nextyaw"]

# an integer written in decimal or as 0x hexadecimal, with an optional sign (a decimal one with
# a leading zero is not an integer, as for Python's int(text, 0))
fn parseWhole(text str):
	digits = text[(1 if text.startsWith("-") or text.startsWith("+") else 0)..]
	hex = digits.startsWith("0x") or digits.startsWith("0X")
	if not hex and digits.len > 1 and digits[0] == '0' and
		digits[..].count('0') != digits.len:
		return none
	i64.parse(text)

# a float's text as Python prints it: no trailing zeros past the point but one
fn floatShown(text str):
	if "e" in text or "E" in text or "." not in text:
		plain = match f64.parse(text):
			v: str(v)
			none: text
		return plain if "." in plain or "e" in plain or "n" in plain else "{plain}.0"
	end = text.len
	while text[end - 1] == '0':
		end -= 1
	if text[end - 1] == '.':
		end += 1
	shown = text[..end].copy()
	if shown.startsWith("."):
		shown = "0{shown}"
	elif shown.startsWith("-."):
		shown = "-0{shown[1..]}"
	shown

# the number a word holds, or none when it is a field's name
fn number(word str, angle bool) Number?:
	if parseWhole(word) is w:
		v = w & 65_535 if angle else w
		return Number(isInt = true, value = v, whole = v, shown = "{v}")
	f = try f64.parse(word)
	Number(isInt = false, value = f, whole = 0, shown = floatShown(word))

# the index of a field by name, or none
fn fieldAt(fields Field[], name str) i64?:
	for i, f in fields:
		if f.name == name: return i
	none

# the fields of a line's words after "tick N"; a name given twice starts over in its place
fn fields(ws str[]):
	out Field[] = []
	current = -1
	for i in 2..ws.len:
		angle = current >= 0 and out[current].name in angles
		match number(ws[i], angle):
			n:
				if current >= 0:
					out[current].numbers.push(n)
			none:
				match fieldAt(out, ws[i]):
					k:
						out[k].numbers.clear()
						current = k
					none: current = out.push(Field(name = ws[i].copy(), numbers = []))
	out

# the ticks of a log by number (shifted), a later line of a tick replacing an earlier one
fn read(path str, shift i64):
	ticks {i64: Field[]} = {}
	text = fs.readFile(path) ?? fail("trace.zap: cannot read {path}")
	for line in text.lines():
		ws = line.words()
		if ws.len < 2 or ws[0] != "tick": continue
		t = i64.parse(ws[1]) ?? fail("trace.zap: bad tick in {line}")
		ticks[t + shift] = fields(ws)
	ticks

# whether two fields' numbers differ: integers exactly, floats to 0.01
fn differs(a Number[], b Number[]):
	if a.len != b.len: return true
	for i, x in a:
		y = b[i]
		if x.isInt and y.isInt:
			if x.whole != y.whole: return true
		elif (x.value - y.value).abs() > 0.01:
			return true
	false

# the named fields of a tick as "name v v v", in the order of the names
fn show(fields Field[], names str[]):
	parts = []
	for name in names:
		if fieldAt(fields, name) is k:
			parts.push("{name} {fields[k].numbers.map(.shown).join(" ")}")
	parts.join(" ")

# where the two logs first part, as the lines to show; none when every tick both have is alike
fn firstDifference(ours {i64: Field[]}, port {i64: Field[]}):
	common = ours.keys().filter(it in port).sorted()
	for at, t in common:
		mine = ours[t]
		theirs = port[t]
		off = []
		for f in theirs:
			if fieldAt(mine, f.name) is k:
				if differs(mine[k].numbers, f.numbers):
					off.push(f.name.copy())
		if not off.isEmpty:
			lines = ["tick {t} differs in {off.join(", ")}"]
			for k in (at - 2).max(0)..(at + 3).min(common.len):
				u = common[k]
				lines.push("  {u:>4} ours {show(ours[u], off)}")
				lines.push("  {u:>4} port {show(port[u], off)}")
			return lines
	[]

test "Mario's ticks are the port's":
	if not fs.exists("projects/mario/rom/sm64.us.z64") or not fs.exists(sm64ex.exe()):
		print("skipped: needs projects/mario/rom/sm64.us.z64 and the PC port built (projects/mario/README.md)")
	else:
		dir = testDir()
		oursFile = "{dir}ours.txt"
		portFile = "{dir}port.txt"
		ours = Process.output("zap run projects/mario/main.zap --frames 160 --walk --trace")
		expect ours.code == 0
		_ = fs.writeFile(oursFile, ours.out)
		env["BENCH_FRAMES"] = "100"
		env["BENCH_UNCAPPED"] = "1"
		env["BENCH_WALK"] = "1"
		env["BENCH_TRACE"] = "1"
		env["BENCH_OUT"] = portFile
		expect Process.output("{sm64ex.exe()} --skip-intro", dir = sm64ex.dir()).code == 0
		parted = firstDifference(read(oursFile, 1), read(portFile, 0))
		print(parted.join("\n"))
		expect parted.isEmpty
