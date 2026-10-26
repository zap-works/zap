# strSort: n generated strings of 1 to 40 letters, each from an alphabet of 2 to 26 letters (long
# shared prefixes among the small ones) sorted by bytes; prints how many are distinct, a hash of
# the sorted sequence and the first and last.
import problems

type Generator:
	state u64

	# the next number, 31 bits
	fn next():
		state = state * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407
		state >> 33

# the word a place names: its start in the text (of at most 64 MB) times 64, plus its length
fn word(text str, place u32) ref str:
	at = i64(place >> 6)
	text[at..at + (place & 63)]

n = arg(0, 1000)
mut random = Generator(state = 1)
# every word in one block, and each one's place
mut letters u8[] = []
letters.reserve(n * 41)
mut places u32[] = []
places.reserve(n)
loop n:
	length = 1 + random.next() % 40
	alphabet = 2 + random.next() % 25
	places.push(u32(letters.len) << 6 | u32(length))
	loop length:
		letters.push('a' + u8(random.next() % alphabet))
text = str(move letters)
places.sortBy(word(text, it))
basis u64 = 14_695_981_039_346_656_037   # FNV-1a's offset basis
mut hash = basis
mut distinct = 0
for i in 0..n:
	w = word(text, places[i])
	if i == 0 or w != word(text, places[i - 1]): distinct += 1
	hash = (w.bytes().reduce(hash, (h, c): (h ^ c) * 1_099_511_628_211) ^ '\n') *
		1_099_511_628_211
print("{n} strings, {distinct} distinct, hash {hash:x}\n{str(word(text, places[0]))}\n{str(word(text, places[n - 1]))}")

test "generated strings sort by their bytes":
	main()
	prints """
		1000 strings, 983 distinct, hash f0a29e5fcc84034d
		a
		zqooisqrllvybefvkbmwrqzdvwayortowog
		"""

test "the C, Rust and Python programs print the same bytes":
	expect problems.agree("strSort")
