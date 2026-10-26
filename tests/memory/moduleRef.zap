# A call is judged by what it changes: one that changes another module variable leaves a borrow
# of this one alone.
mut shelf str[] = ["a".repeat(3)]
mut journal str[] = []

fn note():
	journal.push("x")

test "a call that changes another module variable leaves the borrow alone":
	f = shelf.first ?? fail("empty")
	note()
	print("{f} {journal.len}")
	prints "aaa 1"

mut shelves str[] = ["s".repeat(3)]
mut log str[] = []

fn keepFirst(first ref str, f fn()):
	f()
	print(first)

test "a function value that changes another module variable leaves a lent part alone":
	keepFirst(shelves[0], (): log.push("x"))
	prints "sss"
