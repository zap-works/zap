# Counts lines, words and characters from stdin, then prints each word's count in the order the
# words first appear.

mut lines = 0
mut words = 0
mut chars = 0
mut freq {str: i64} = {}
mut order = []   # the words in the order they first appear
mut line = stdin.line()
while line != none:
	text = line ?? ""
	lines += 1
	chars += text.len
	for w in text.split(" "):
		if w.isEmpty: continue
		words += 1
		key = w.lower()
		if key not in freq:
			order.push(key.copy())
		freq.add(key, 1)
	line = stdin.line()
print("lines={lines} words={words} chars={chars}")
mut entries = []
for k in order:
	entries.push("{k}={freq[k]}")
print(entries.join(", "))

test "lines, words and characters from stdin are counted, the words in their first order":
	stdin.feed("""
		the quick brown fox
		jumps over the lazy dog
		the end

		""")
	main()
	prints """
	    lines=3 words=11 chars=49
	    the=3, quick=1, brown=1, fox=1, jumps=1, over=1, lazy=1, dog=1, end=1
	    """
