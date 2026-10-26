# `xs.sortedBy(f).slice(0, k)` keeps only the k first keys as they come: the same elements in the
# same order as the whole sort, ties in their order, owning keys dropped
words = ["pear", "fig", "apple", "kiwi", "date", "fig", "plum", "lime"]
print(words.sortedBy(.len, "{it}!")[..3])
print(words.sortedBy(.len)[..5])
print(words.sortedBy(0 - .len)[..8])

test "first k of a sort":
	main()
	prints """
		["fig", "fig", "date"]
		["fig", "fig", "pear", "kiwi", "date"]
		["apple", "pear", "kiwi", "date", "plum", "lime", "fig", "fig"]
		"""

test "first k of a filter's sort: the kept elements' places, not their source's":
	words = ["pear", "fig", "apple", "kiwi", "date", "fig", "plum", "lime"]
	print(words.filter(.len > 3).sortedBy(it)[..2])
	counts {str: i64} = {}
	for w in words:
		counts.add(w, 1)
	print(counts.keys().filter(.len == 4).sortedBy(it)[..3])
	prints """
		["apple", "date"]
		["date", "kiwi", "lime"]
		"""
