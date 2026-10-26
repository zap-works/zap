# Division and remainder by a constant, which the backend makes a multiply by its reciprocal and
# shifts, against the same division by a variable: each program takes one width (i32, i64, u32,
# u64) and one divisor, famous or random, of either sign where the width has one, and divides
# 0, the extremes, multiples of the divisor and their neighbours and pseudo-random values both
# ways; `x % k == 0` as a condition jumps straight from the comparison, so it is checked too. A
# program prints how many results differed, which must be 0 (fuzzRun): a failure is kept in
# build/fuzz/.
#
# The suite runs a few programs from a fixed seed; for a long hunt:
#
#   zap run tests/fuzz/divisions.zap [count] [seed]

import fuzzRun
import fs

mut rng = Random(0)

# a width: its name, its extremes as literals, whether it has a sign, its magnitude's bits
type Width:
	name str
	least str
	most str
	signed bool
	bits i64

widths = [
	Width("i32", "-2_147_483_647 - 1", "2_147_483_647", true, 31),
	Width("i64", "-9_223_372_036_854_775_807 - 1", "9_223_372_036_854_775_807", true, 63),
	Width("u32", "0", "4_294_967_295", false, 32),
	Width("u64", "0", "18_446_744_073_709_551_615", false, 64)
]

# divisors the backend once got wrong or that sit on an edge of its forms
famous = [3, 5, 6, 7, 9, 10, 12, 25, 60, 641, 1000, 3600, 65_537, 86_400, 139_968, 1_000_000_007,
	2_147_483_647]

# a divisor that fits w, neither 0 nor -1 (the least value divided by -1 overflows), as a literal
fn divisor(w Width):
	random = rng.next(2..(1 << rng.next(2..w.bits.min(62))))
	magnitude = famous[rng.next(0..len)] if rng.next(0..2) == 0 else random
	if w.signed and rng.next(0..2) == 0: return "-{magnitude}"
	"{magnitude}"

# the program dividing values of w by the divisor k both ways, the xorshift's start from seed
fn program(w Width, k str, seed i64):
	t = w.name
	lines = [
		fuzzRun.testHeader(),
		"\tds {t}[] = [{k}]",
		"\td = ds[0]",
		"\txs {t}[] = [0, 1, 2, {w.most}, {w.most} - 1, {w.least}, {w.least} + 1]",
		"\ts u64 = {seed * 2_654_435_761 + 88_172_645_463_325_252}",
		"\tloop 3000:",
		"\t\ts ^= s << 13",
		"\t\ts ^= s >> 7",
		"\t\ts ^= s << 17",
		"\t\tx = s >> (s % 64)" if t == "u64" else "\t\tx = {t}.wrap(s >> (s % 64))",
		"\t\tm = x - x % d",
		"\t\txs.push(x)",
		"\t\txs.push(m)",
		"\t\tif m < {w.most}: xs.push(m + 1)",
		"\t\tif m > {w.least}: xs.push(m - 1)",
		"\tbad = 0",
		"\tfor x in xs:",
		"\t\tif x / {k} != x / d or x % {k} != x % d: bad += 1",
		"\t\tif x % {k} == 0:",
		"\t\t\tif x % d != 0: bad += 1",
		"\t\telif x % d == 0:",
		"\t\t\tbad += 1",
		"\tprint(bad)",
		fuzzRun.testCheck("0\n")
	]
	"{lines.join("\n")}\n"

a = args
count = i64.parse(a.first ?? "100") ?? 100
seed = (i64.parse(a[1]) ?? 1) if a.len > 1 else 1
failed = fuzzDivisions(count, seed)
print("{count - failed} of {count} programs right")

test "a division by a constant gives what the division by a variable does":
	print("{3 - fuzzDivisions(3, 1)} of 3 programs right")
	prints "3 of 3 programs right"

# count random programs from seed built, run and compared; how many failed
fn fuzzDivisions(count i64, seed i64):
	failed = 0
	for n in 0..count:
		rng = Random(seed + n)
		w = widths[rng.next(0..len)]
		_ = fs.writeFile("{testDir()}dv.zap", w.program(w.divisor(), seed + n))
		if not fuzzRun.passes("{testDir()}dv.zap", seed + n):
			failed += 1
	failed
