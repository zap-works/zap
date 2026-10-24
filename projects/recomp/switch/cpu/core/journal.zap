# The journal of the stores (cpu's lockstep check): while journaling, memory's store notes each byte
# it is about to change and its value before, so the stores can be compared and undone.

# while journaling, each byte a store is about to change and its value before, in order (a byte
# stored twice is there twice): lists, which clear at once however long the last run made them
pub mut journaling = false
mut journalAt i64[] = []
mut journalWas u8[] = []

fn noteBytes(at i64, n i64):
	for a in at..at + n:
		journalAt.push(a)
		journalWas.push(window.load8(a))

pub fn clearJournal():
	journalAt.clear()
	journalWas.clear()

# each byte the journal names with its value now, and with its value before the journal began
pub fn journalBytes() ({i64: u8}, {i64: u8}):
	now {i64: u8} = {}
	was {i64: u8} = {}
	for k in journalAt.len - 1..-1 step -1:
		now[journalAt[k]] = window.load8(journalAt[k])
		was[journalAt[k]] = journalWas[k]
	(now, was)

# memory put back as it was before the journal began
pub fn undoJournal():
	for k in journalAt.len - 1..-1 step -1:
		window.store8(journalAt[k], journalWas[k])

# the byte at a as memory holds it now
pub fn byteAt(a i64) u8:
	window.load8(a)
