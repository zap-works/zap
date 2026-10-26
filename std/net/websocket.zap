# WebSocket (RFC 6455) over a TcpConn: the upgrade out of an HTTP request, and the frames after
# it. A server answers `isUpgrade(request)` with `appendUpgradeResponse` and then reads
# `conn.nextMessage()`; a client sends `appendUpgradeRequest`, checks the answer's key with
# `acceptKey`, and masks every frame it queues (a client's frames must be masked, a server's
# must not be). Messages are assembled from fragments, a ping is answered by a pong and a close
# by a close, as the protocol asks.

import digest

# what a frame is
pub type Opcode:
	Continuation
	Text
	Binary
	Close
	Ping
	Pong

	fn code():
		match self:
			Continuation: 0
			Text: 1
			Binary: 2
			Close: 8
			Ping: 9
			Pong: 10

	fn isControl():
		self.code() >= 8

# one frame: its payload unmasked
pub type Frame:
	fin bool = true
	opcode Opcode = .Continuation
	payload u8[] = []

# a whole message: text (UTF-8) or binary
pub type Message:
	text bool
	bytes u8[]

# the GUID the protocol appends to a client's key
handshakeGuid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
frameLimit = 67_108_864   # the largest payload read, 64 MiB

fn opcodeOf(code i64) Opcode?:
	match code:
		0: .Continuation
		1: .Text
		2: .Binary
		8: .Close
		9: .Ping
		10: .Pong
		_: none

alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

# the bytes in base 64 with padding
fn base64(bytes u8[]) str:
	table = alphabet.bytes()
	out = []
	i = 0
	while i < bytes.len:
		left = bytes.len - i
		b0 = i64(bytes[i])
		b1 = i64(bytes[i + 1]) if left > 1 else 0
		b2 = i64(bytes[i + 2]) if left > 2 else 0
		out.push(table[b0 >> 2])
		out.push(table[((b0 & 3) << 4) | (b1 >> 4)])
		out.push(table[((b1 & 15) << 2) | (b2 >> 6)] if left > 1 else '=')
		out.push(table[b2 & 63] if left > 2 else '=')
		i += 3
	str(move out)

# The Sec-WebSocket-Accept a server answers to the client's Sec-WebSocket-Key.
pub fn acceptKey(clientKey str) str:
	hex = digest.sha1("{clientKey}{handshakeGuid}".bytes())
	raw = []
	hexDigits = hex.bytes()
	for i in 0..hexDigits.len / 2:
		raw.push(u8(rt.hexValue(hexDigits[2 * i]) * 16 + rt.hexValue(hexDigits[2 * i + 1])))
	base64(raw)

# Whether the request asks to upgrade to a WebSocket (version 13, a key given).
pub fn isUpgrade(request Request) bool:
	upgrade = (request.header("upgrade") ?? "").lower()
	connection = (request.header("connection") ?? "").lower()
	version = request.header("sec-websocket-version") ?? ""
	upgrade == "websocket" and connection.indexOf("upgrade") != none and version == "13" and
		request.header("sec-websocket-key") != none

# Appends the 101 answer to an upgrade request with this key.
pub fn appendUpgradeResponse(mut out u8[], clientKey str):
	appendHead(
		out,
		"HTTP/1.1 101 Switching Protocols",
		[
			Header(name = "Upgrade", value = "websocket"),
			Header(name = "Connection", value = "Upgrade"),
			Header(name = "Sec-WebSocket-Accept", value = acceptKey(clientKey))
		],
		-1
	)

# Appends a request to upgrade, with the client's key (16 random bytes in base 64).
pub fn appendUpgradeRequest(mut out u8[], target str, host str, clientKey str):
	appendHead(
		out,
		"GET {target} HTTP/1.1",
		[
			Header(name = "Host", value = host.copy()),
			Header(name = "Upgrade", value = "websocket"),
			Header(name = "Connection", value = "Upgrade"),
			Header(name = "Sec-WebSocket-Key", value = clientKey.copy()),
			Header(name = "Sec-WebSocket-Version", value = "13")
		],
		-1
	)

# Appends a frame. A client's frames carry a 32-bit mask key (`mask`, 0 to 2^32 - 1) and a
# server's none (-1).
pub fn appendFrame(mut out u8[], opcode Opcode, payload u8[], mask i64 = -1, fin bool = true):
	out.push(u8((128 if fin else 0) | opcode.code()))
	maskBit = 0 if mask < 0 else 128
	n = payload.len
	if n < 126:
		out.push(u8(maskBit | n))
	elif n < 65_536:
		out.push(u8(maskBit | 126))
		out.pushU16be(n)
	else:
		out.push(u8(maskBit | 127))
		out.pushU64be(n)
	if mask < 0:
		out.extend(payload)
		return
	out.pushU32be(mask)
	for i in 0..n:
		out.push(payload[i] ^ u8((mask >> (24 - 8 * (i & 3))) & 255))

# The payload of a close frame: the status code (1000 is a normal close) and a reason.
pub fn closePayload(status i64, reason str) u8[]:
	payload = []
	payload.pushU16be(status)
	payload.extend(reason.bytes())
	payload

# Reads one frame from buf[start..stop] into `frame`: the bytes it takes, 0 while it is
# incomplete, -1 when it breaks the protocol (reserved bits or opcode, a control frame split or
# over 125 bytes, a payload over 64 MiB).
pub fn parseFrame(buf u8[], start i64, stop i64, mut frame Frame) i64:
	if stop - start < 2: return 0
	first = i64(buf[start])
	second = i64(buf[start + 1])
	if first & 112 != 0: return -1
	frame.opcode = opcodeOf(first & 15) ?? return -1
	frame.fin = first & 128 != 0
	masked = second & 128 != 0
	n = second & 127
	at = start + 2
	if n == 126:
		if stop - at < 2: return 0
		n = buf.u16be(at)
		at += 2
	elif n == 127:
		if stop - at < 8: return 0
		n = i64(buf.u64be(at))
		at += 8
		if n < 0 or n > frameLimit: return -1
	if frame.opcode.isControl() and (n > 125 or not frame.fin): return -1
	if n > frameLimit: return -1
	mask = 0
	if masked:
		if stop - at < 4: return 0
		mask = buf.u32be(at)
		at += 4
	if stop - at < n: return 0
	payload = buf[at..at + n].copy()
	if masked:
		for i in 0..n:
			payload[i] ^= u8((mask >> (24 - 8 * (i & 3))) & 255)
	frame.payload = move payload
	at + n - start

# The next frame, waiting for it; Closed when the peer closed the connection first.
pub fn nextFrame(mut tcpConn TcpConn) Frame ? Error:
	frame = Frame()
	loop:
		if tcpConn.stop > tcpConn.start:
			used = parseFrame(tcpConn.buf, tcpConn.start, tcpConn.stop, frame)
			if used < 0: return Error.Malformed
			if used > 0:
				tcpConn.start += used
				return frame
		try tcpConn.fill()

# Queues a frame, sent when the connection next waits for input or at flush(); `mask` as
# appendFrame says.
pub fn queueFrame(mut tcpConn TcpConn, opcode Opcode, payload u8[], mask i64 = -1):
	appendFrame(tcpConn.out, opcode, payload, mask)

# The next whole message: fragments are joined, a ping is answered with a pong (masked with
# `mask`, as queueFrame), a close with a close and then Closed. Malformed when a continuation
# has nothing to continue, a data frame interrupts a message, or a text message is not UTF-8.
pub fn nextMessage(mut tcpConn TcpConn, mask i64 = -1) Message ? Error:
	text = false
	bytes = []
	open = false
	loop:
		frame = try tcpConn.nextFrame()
		match frame.opcode:
			Ping:
				tcpConn.queueFrame(.Pong, frame.payload, mask)
			Pong: pass
			Close:
				tcpConn.queueFrame(.Close, frame.payload[..len.min(2)].copy(), mask)
				_ = tcpConn.flush()
				return Error.Closed
			Continuation:
				if not open: return Error.Malformed
				bytes.extend(frame.payload)
				if frame.fin: break
			_:
				if open: return Error.Malformed
				text = frame.opcode == .Text
				bytes = frame.payload.copy()
				if frame.fin: break
				open = true
	if text and not isUtf8(bytes): return Error.Malformed
	Message(text, bytes)

# The next whole message if it has arrived, without waiting: none while it has not; else as
# nextMessage (a server that polls its connections in one loop).
pub fn pollMessage(mut tcpConn TcpConn, mask i64 = -1) (Message?) ? Error:
	if not messageHeld(tcpConn.buf, tcpConn.start, tcpConn.stop):
		try tcpConn.fill(false)
		if not messageHeld(tcpConn.buf, tcpConn.start, tcpConn.stop): return none
	try tcpConn.nextMessage(mask)

# whether buf[start..stop] holds what nextMessage reads without waiting: a message's last frame, a
# close, or a frame that breaks the protocol
fn messageHeld(buf u8[], start i64, stop i64):
	frame = Frame()
	at = start
	loop:
		used = parseFrame(buf, at, stop, frame)
		if used < 0: return true
		if used == 0: return false
		at += used
		if frame.opcode == .Close or (frame.fin and not frame.opcode.isControl()): return true

# whether the bytes are well-formed UTF-8 (shortest forms, no surrogates, nothing over U+10FFFF)
fn isUtf8(bytes u8[]):
	i = 0
	while i < bytes.len:
		b = i64(bytes[i])
		extra = 0
		least = 0
		if b < 128:
			i += 1
			continue
		elif b >= 194 and b < 224:
			extra = 1
			least = 128
		elif b >= 224 and b < 240:
			extra = 2
			least = 2048
		elif b >= 240 and b < 245:
			extra = 3
			least = 65_536
		else:
			return false
		if i + extra >= bytes.len: return false
		point = b & (63 >> extra)
		for k in 1..=extra:
			c = i64(bytes[i + k])
			if c & 192 != 128: return false
			point = (point << 6) | (c & 63)
		if point < least or point > 1_114_111 or (point >= 55_296 and point < 57_344): return false
		i += extra + 1
	true
