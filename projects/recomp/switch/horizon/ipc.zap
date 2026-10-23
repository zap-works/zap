# IPC messages (switchbrew: IPC Marshalling), read from and written back to the caller's buffer
# (its thread-local page for svcSendSyncRequest). A CMIF request: a header (type, descriptor
# counts, raw size, receive-list flags), handles, X, A, B and W descriptors, raw data whose
# payload starts 16-aligned with "SFCI", the command id and the arguments, then C descriptors.
# A domain's request prefixes the payload with the object it is for. TIPC (type 16 and up) has
# the command in its type and the arguments raw. The answer: "SFCO", the result, the outputs.

import recomp.switch.cpu

pub typeClose = 2
pub typeRequest = 4
pub typeControl = 5
pub typeRequestWithContext = 6
pub typeControlWithContext = 7

pub type Buffer:
	at i64
	size i64

pub type Request:
	kind i64
	command i64 = 0
	data u8[] = []   # the arguments, past the command's header
	pid bool = false
	copied i64[] = []
	moved i64[] = []
	x Buffer[] = []   # pointers the caller sends
	a Buffer[] = []   # buffers the service reads
	b Buffer[] = []   # buffers the service writes
	c Buffer[] = []   # the caller's receive list, for what the service sends by pointer
	domainCommand i64 = 0   # a domain's: 1 a message, 2 the object closed
	domainObject i64 = 0
	domainInputs i64[] = []

	# a little-endian argument of `size` bytes at `at` of the data (bit for bit, for a u64)
	fn arg(at i64, size i64):
		v = u64(0)
		for k in 0..size:
			if at + k < data.len: v = v | (u64(data[at + k]) << (8 * k))
		i64(v)

	# the bytes of a buffer the caller sends (an A, or an X when none)
	fn sent(index i64):
		buf = Buffer(at = 0, size = 0)
		if index < a.len and a[index].size > 0: buf = a[index].copy()
		elif index < x.len: buf = x[index].copy()
		(0..buf.size).map(u8(cpu.memory.load(buf.at + it, 0)))

	# the place the answer's bytes go: a B buffer, else a C buffer
	fn receive(index i64):
		if index < b.len and b[index].size > 0: return b[index].copy()
		if index < c.len: return c[index].copy()
		Buffer(at = 0, size = 0)

pub type Response:
	result i64 = 0
	data u8[] = []
	copied i64[] = []
	moved i64[] = []
	objects i64[] = []   # new service objects: domain ids, or moved handles outside a domain

	fn u32(v i64):
		data.pushU32le(v & 0xFFFF_FFFF)

	fn u64(v i64):
		data.pushU64le(v)

	# the answer is the failure `code`, with no outputs
	fn fail(code i64):
		result = code
		data = []

	fn u8(v i64):
		data.push(v & 0xFF)

	fn bytes(b u8[]):
		data.extend(b)

	# zero padding until the data's length is a multiple of n (an output struct's alignment)
	fn align(n i64):
		while data.len % n != 0:
			data.push(0)

fn readWord(at i64) i64:
	i64(cpu.memory.load(at, 2))

# a 3-word A, B or W descriptor
fn bigBuffer(at i64):
	w0 = readWord(at)
	w1 = readWord(at + 4)
	w2 = readWord(at + 8)
	Buffer(
		at = w1 | ((w2 >> 28) & 0xF) << 32 | ((w2 >> 2) & 7) << 36,
		size = w0 | ((w2 >> 24) & 0xF) << 32
	)

# The request in the message at `at`; domain says whether the session is a domain's.
pub fn readRequest(at i64, domain bool) Request:
	h0 = readWord(at)
	h1 = readWord(at + 4)
	r = Request(kind = h0 & 0xFFFF)
	nx = (h0 >> 16) & 15
	na = (h0 >> 20) & 15
	nb = (h0 >> 24) & 15
	nw = (h0 >> 28) & 15
	raw = h1 & 0x3FF
	cFlags = (h1 >> 10) & 15
	p = at + 8
	if (h1 >> 31) & 1 != 0:
		hd = readWord(p)
		p += 4
		r.pid = hd & 1 != 0
		if r.pid: p += 8
		loop (hd >> 1) & 15:
			r.copied.push(readWord(p))
			p += 4
		loop (hd >> 5) & 15:
			r.moved.push(readWord(p))
			p += 4
	loop nx:
		w0 = readWord(p)
		r.x.push(
			Buffer(
				at = readWord(p + 4) | ((w0 >> 12) & 0xF) << 32 | ((w0 >> 6) & 7) << 36,
				size = (w0 >> 16) & 0xFFFF
			)
		)
		p += 8
	loop na:
		r.a.push(bigBuffer(p))
		p += 12
	loop nb:
		r.b.push(bigBuffer(p))
		p += 12
	p += nw * 12
	rawAt = p
	if r.kind >= 16:
		r.command = r.kind - 16
		r.data = (0..raw * 4).map(u8(cpu.memory.load(rawAt + it, 0)))
	else:
		payload = (rawAt + 15) & ~15
		if domain and (r.kind == typeRequest or r.kind == typeRequestWithContext):
			r.domainCommand = readWord(payload) & 0xFF
			inputs = (readWord(payload) >> 8) & 0xFF
			length = (readWord(payload) >> 16) & 0xFFFF
			r.domainObject = readWord(payload + 4)
			for k in 0..inputs:
				r.domainInputs.push(readWord(payload + 16 + length + k * 4))
			payload += 16
		r.command = readWord(payload + 8)
		end = rawAt + raw * 4
		r.data = (0..(end - payload - 16).max(0)).map(u8(cpu.memory.load(payload + 16 + it, 0)))
	cAt = rawAt + raw * 4
	count = 0 if cFlags < 2 else cFlags - 2
	if cFlags == 2: count = 1
	for k in 0..count:
		w0 = readWord(cAt + k * 8)
		w1 = readWord(cAt + k * 8 + 4)
		r.c.push(Buffer(at = w0 | (w1 & 0xFFFF) << 32, size = (w1 >> 16) & 0xFFFF))
	r

fn writeWord(at i64, v i64):
	cpu.memory.store(at, 2, v & 0xFFFF_FFFF)

# The response written over the message at `at`, as CMIF (with a domain's header when domain)
# or TIPC.
pub fn writeResponse(at i64, res Response, domain bool, tipc bool):
	handles = res.copied.len + res.moved.len
	movedHere i64[] = res.moved.copy()
	if not domain: movedHere.extend(res.objects)
	words = []
	if tipc:
		words.pushU32le(res.result)
		words.extend(res.data)
	else:
		if domain:
			words.pushU32le(res.objects.len)
			words.pushU32le(0)
			words.pushU64le(0)
		words.extend("SFCO".bytes())
		words.pushU32le(0)
		words.pushU32le(res.result)
		words.pushU32le(0)
		words.extend(res.data)
		if domain:
			for o in res.objects:
				words.pushU32le(o)
	while words.len % 4 != 0:
		words.push(0)
	handleCount = res.copied.len + movedHere.len
	headerWords = 2 + (1 + handleCount if handleCount > 0 else 0)
	p = at + headerWords * 4
	pad = 0 if tipc else ((p + 15) & ~15) - p
	rawWords = (pad + words.len) / 4 + (0 if tipc else 4)
	writeWord(at, 0)
	writeWord(at + 4, rawWords | ((1 << 31) if handleCount > 0 else 0))
	q = at + 8
	if handleCount > 0:
		writeWord(q, (res.copied.len << 1) | (movedHere.len << 5))
		q += 4
		for h in res.copied:
			writeWord(q, h)
			q += 4
		for h in movedHere:
			writeWord(q, h)
			q += 4
	q += pad
	for k, mut word in words:
		cpu.memory.store(q + k, 0, word)
	_ = handles
