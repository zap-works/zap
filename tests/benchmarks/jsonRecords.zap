# jsonRecords: n generated records written as {"records": [...]} and parsed back; prints the
# JSON's size and byte sum, sums over the parsed records and whether they equal the originals.
import problems

type Record:
	id i64
	name str
	email str
	score i64
	active bool
	tags str[]

type Batch:
	records Record[]

tagNames = ["red", "green", "blue", "admin", "guest", "beta"]

type Generator:
	state u64

	# the next number, 31 bits
	fn next() i64:
		state = state * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407
		state >> 33

fn generate(n i64):
	random = Generator(state = 7)
	records = []
	for i in 0..n:
		letters = []
		loop 5 + random.next() % 8:
			letters.push('a' + u8(random.next() % 26))
		word = str(move letters)
		score = random.next() % 100_000 - 50_000
		active = random.next() % 3 != 0
		tags = []
		loop random.next() % 4:
			tags.push(tagNames[random.next() % 6].copy())
		name = "{word} \"jr\"" if i % 10 == 0 else word
		records.push(Record(id = i, name, email = "{word}{i}@mail.test", score, active, tags))
	records

# the records written as JSON and read back; the text is gone by the end
fn roundTrip(batch Batch):
	text = batch.toJson()
	print("json {text.len} bytes, checksum {text.bytes().sum(c: i64(c))}")
	(Batch.fromJson(text) ?? Batch(records = [])).records

n = arg(0, 100)
batch = Batch(records = generate(n))
back = batch.roundTrip()
scores = back.sum(.score)
active = back.count(.active)
tags = back.sum(.tags.len)
print("read {back.len} records: scores {scores}, active {active}, tags {tags}, {"same" if back == batch.records else "DIFFERENT"}")

test "records written as JSON parse back equal to themselves":
	main()
	prints """
		json 10933 bytes, checksum 899949
		read 100 records: scores -357675, active 63, tags 146, same
		"""

test "the C, Rust and Python programs print the same bytes":
	expect problems.agree("jsonRecords")
