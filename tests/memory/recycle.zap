# A list a loop's turn makes and drops goes back to the loop, emptied, and the same binding takes
# it the next turn, its room the largest turn's; the loop frees it once, as it ends (TODO.md 54).

fn rows(n i64):
	total = 0
	for i in 0..n:
		row = []
		for j in 0..(i % 50):
			row.push(j * i)
		doubled = row.map(it * 2)
		total += row.len + doubled.sum()
	total

fn kept(n i64):
	out = []
	for i in 0..n:
		parts = ["part number {i} of the list", "and the next part {i}"]
		if i % 3 == 0:
			out.push(parts.join("/"))
		if i % 7 == 0: continue
		parts.push("one more")
		if i == 50: break
	out

fn firstLong(words str[]) str?:
	i = 0
	while i < words.len:
		letters = []
		for c in words[i].bytes():
			letters.push(c)
		if letters.len > 3: return str(move letters)
		i += 1
	none

test "a list made each turn takes the block of the turn before":
	before = allocations()
	total = rows(1000)
	made = allocations() - before
	live = liveBlocks()
	print("{total} {made < 20} {liveBlocks() == live}")
	prints "401628500 true true"

test "a turn that gives its list away, continues, breaks or returns":
	ks = kept(100)
	print("{ks.len} {ks[1]}")
	print(firstLong(["ab", "abc", "abcde", "x"]) ?? "none")
	prints """
		17 part number 3 of the list/and the next part 3
		abcde
		"""
