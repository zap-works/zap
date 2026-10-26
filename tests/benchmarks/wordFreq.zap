# wordFreq: n generated words counted in a hash map keyed by the words; prints the distinct
# count and the ten most frequent.
import problems

fn generate(n i64) str:
	text = []
	state u64 = 1
	for i in 0..n:
		state = state * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407
		k = (state >> 44) % ((state >> 24 & 1_048_575) + 1)
		text.push('a' + u8(k % 26))
		k /= 26
		while k > 0:
			text.push('a' + u8(k % 26))
			k /= 26
		text.push('\n' if i % 20 == 19 or i == n - 1 else ' ')
	str(move text)

n = arg(0, 1000)
text = generate(n)
mut counts {ref str: i64} = {}
for line in text.lines():
	for word in line.split(" "):
		counts.add(word, 1)
print("{n} words, {counts.len} distinct")
for word in counts.keys().sortedBy(-counts[it], it)[..10]: print("{counts[word]:>8} {word}")

test "the generated words' distinct count and ten most frequent are the known ones":
	main()
	prints """
		1000 words, 999 distinct
		       2 woec
		       1 aabb
		       1 aatc
		       1 aay
		       1 aboc
		       1 abzfb
		       1 adhu
		       1 adle
		       1 ady
		       1 aerb
		"""

test "the C, Rust and Python programs print the same bytes":
	expect problems.agree("wordFreq")
