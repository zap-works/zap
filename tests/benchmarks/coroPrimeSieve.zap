# coroPrimeSieve: the first n primes by a chain of tasks joined by channels (the programming-language-benchmarks
# suite's coro-prime-sieve): a generator sends 2, 3, 4... and each prime found is a filter that takes the
# multiples of that prime out of what its predecessor sends. A task here is a background job, which a
# processor runs to its end, so a chain of a task per prime would wait on its tasks beyond the processors:
# a task is a run of consecutive filters, as many tasks as processors less two (a number meets the same primes in the
# same order). Prints the primes, one a line.
import problems

capacity = 64

# the numbers 2, 3, 4... until the channel is closed
fn generate(out Channel<i32>) i32:
	o = out
	n = 2
	loop:
		if not o.send(n): break
		n += 1
	0

# the filters of `room` consecutive primes: a number that no prime of theirs divides is the next of
# them while there is room (sent to found), else goes on to the next task; a last task ends when full
fn filters(inp Channel<i32>, out Channel<i32>, found Channel<i32>, room i64, last bool) i32:
	i = inp
	o = out
	f = found
	primes i32[] = []
	primes.reserve(room)
	loop:
		v = i.receive() ?? break
		if primes.any(v % it == 0): continue
		if primes.len < room:
			primes.push(v)
			f.send(v)
			if last and primes.len == room: break
		elif not o.send(v): break
	i.close()
	o.close()
	0

n = arg(0, 10)
wanted = (cpuCount() - 2).clamp(1, n)
share = (n + wanted - 1) / wanted
tasks = (n + share - 1) / share
first = Channel<i32>(capacity)
found = Channel<i32>()
mut jobs = []
mut head = first
jobs.push(background((): generate(first)))
for k in 0..tasks:
	room = share.min(n - k * share)
	src = head
	next = Channel<i32>(capacity)
	last = k == tasks - 1
	jobs.push(background((): filters(src, next, found, room, last)))
	head = next
loop n:
	print(found.receive() ?? 0)

test "a chain of filters joined by channels gives the first primes":
	main()
	prints """
		2
		3
		5
		7
		11
		13
		17
		19
		23
		29
		"""

test "the C, C++, Rust and Python programs print the same bytes":
	expect problems.agree("coroPrimeSieve")
