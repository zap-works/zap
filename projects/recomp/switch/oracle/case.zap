# A case the arm64 machine ran for the interpreter to run the same: one instruction word at pc,
# the registers before and after, and the words of the scratch memory a store changed. The
# scratch is 2 KB at `mem` holding a fixed pattern before each case; an access's base register
# points into its middle. A case is a line of a vectors file:
#
#   <word> <pc> <mem> <state before> | <state after> | <offset>=<word> ...
#
# every number hexadecimal.

pub scratchSize = 2048
pub scratchMiddle = 1024

# a state's places: x0-x30, sp, nzcv, pc, the 32 vector registers as low and high words, fpcr, fpsr
pub atSp = 31
pub atNzcv = 32
pub atPc = 33
pub atQ = 34
pub atFpcr = 98
pub atFpsr = 99
pub stateSize = 100

# a scratch word a store changed
pub type Stored:
	at i64   # from the scratch's start
	value u64

pub type Case:
	word i64
	pc i64
	mem i64
	before u64[] = []   # a state (atSp...)
	after u64[] = []
	stores Stored[] = []

# the scratch's byte at offset i before a case
pub fn patternByte(i i64) u8:
	(i * 29 + 0x5A) & 0xFF

# The scratch's bytes before a case.
pub fn pattern() u8[]:
	(0..scratchSize).map(patternByte(it))

fn hexWords(ws u64[]):
	ws.map("{it:x}").join(" ")

# the case as its line
pub fn format(c Case) str:
	stores = c.stores.map("{.at:x}={.value:x}").join(" ")
	"{c.word:x} {c.pc:x} {c.mem:x} {hexWords(c.before)} | {hexWords(c.after)} | {stores}"

fn parseHex(s str):
	v = u64(0)
	for ch in s.bytes():
		d = ch.hexValue()
		if d < 0: return v
		v = v << 4 | u64(d)
	v

fn numbers(s str):
	s.replace("	", " ").split(" ").filter(it != "").map(parseHex(it))

# A vectors file's line as its case, none for a blank or a comment.
pub fn parse(line str) Case?:
	if line.trimmed() == "" or line.startsWith("#"): return none
	parts = line.split(" | ")
	if parts.len != 3: return none
	head = numbers(parts[0])
	stores = []
	for pair in parts[2].split(" ").filter("=" in it):
		at = pair.indexOf("=") ?? continue
		stores.push(Stored(at = i64(parseHex(pair[..at])), value = parseHex(pair[at + 1..])))
	Case(
		word = i64(head[0]),
		pc = i64(head[1]),
		mem = i64(head[2]),
		before = head[3..].copy(),
		after = numbers(parts[1]),
		stores
	)

test "a case's line reads back as the case":
	c = Case(
		word = 0x8B02_0020,
		pc = 0x1000,
		mem = 0x2000,
		before = [1, 2, 3],
		after = [4, 5],
		stores = [Stored(at = 8, value = 0xFF)]
	)
	back = parse(c.format()) ?? Case(word = 0, pc = 0, mem = 0)
	expect back.word == c.word and back.before == c.before and back.after == c.after
	expect back.stores.len == 1 and back.stores[0].value == 0xFF
