# Libraries loaded while a program runs, from several threads at once, and a Zap function the
# library calls back (the C library's qsort with a Zap comparator), the comparator itself calling
# the library.
# host: linux (the libraries are Linux's)

extern "libc.so.6" fn qsort(base i64[], count i64, size i64, compare fn(i64, i64) i64)
extern "libc.so.6" fn strlen(text str) i64
extern "libc.so.6" fn memcpy(into i64[], from i64, size i64) i64

# the word at an address the library gave the comparator
fn wordAt(address i64):
	one i64[] = [0]
	memcpy(one, address, 8)
	one[0]

fn ascending(a i64, b i64):
	-1 if wordAt(a) < wordAt(b) else 1 if wordAt(a) > wordAt(b) else 0

# the library called from inside the library's call
fn ascendingByLength(a i64, b i64):
	strlen("inside the callback\0")
	ascending(a, b)

fn pseudoRandom(n i64, seed i64):
	values = []
	x = seed
	loop n:
		x = (x * 1_103_515_245 + 12_345) % 2_147_483_648
		values.push(x)
	values

fn isSorted(values i64[]):
	for i in 1..values.len:
		if values[i - 1] > values[i]: return false
	true

# the sum of 3000 words sorted by qsort (-1 when they are not): the comparator calls strlen too
# when calling is set
fn sortedSum(seed i64, calling bool):
	values = pseudoRandom(3000, seed)
	total = values.sum(it)
	if calling:
		qsort(values, values.len, 8, ascendingByLength)
	else:
		qsort(values, values.len, 8, ascending)
	total if isSorted(values) and values.sum(it) == total else -1

test "the library calls a Zap function: qsort with a Zap comparator":
	values = pseudoRandom(1000, 7)
	total = values.sum(it)
	qsort(values, values.len, 8, ascending)
	expect isSorted(values)
	expect values.sum(it) == total

test "a callback calls the library again":
	expect sortedSum(11, true) > 0

test "threads are in a library at once, each with callbacks":
	jobs = []
	for k in 0..8:
		jobs.push(background((): sortedSum(100 + k, k % 2 == 0)))
	for job in 0..jobs.len:
		loop:
			match jobs[job].tryReceive():
				sum:
					expect sum > 0
					break
				none:
					sleepMs(1)
