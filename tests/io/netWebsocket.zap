# WebSocket (RFC 6455) of std/net: the handshake key, the frames of the RFC's examples, and a
# server and a client over a connection with a ping, a fragmented message and a close.

import net

test "the handshake key of the RFC":
	print(net.acceptKey("dGhlIHNhbXBsZSBub25jZQ=="))
	prints """
		s3pPLMBiTxaQ9kYGzzhZRbK+xOo=
		"""

fn hex(bytes u8[]):
	bytes.map("{it:02x}").join("")

test "frames are written as the RFC shows them":
	out = []
	net.appendFrame(out, .Text, "Hello".bytes())
	net.appendFrame(out, .Text, "Hello".bytes(), 0x37fa_213d)
	net.appendFrame(out, .Ping, "Hello".bytes())
	net.appendFrame(out, .Text, "Hel".bytes(), fin = false)
	net.appendFrame(out, .Continuation, "lo".bytes())
	print(hex(out))
	big = []
	net.appendFrame(big, .Binary, zeros(256))
	net.appendFrame(big, .Binary, zeros(65_536))
	print("{hex(big[..4])} {hex(big[260..270])} {big.len}")
	prints """
		810548656c6c6f818537fa213d7f9f4d5158890548656c6c6f010348656c80026c6f
		827e0100 827f0000000000010000 65806
		"""

test "frames are read, masked or not, and the broken ones refused":
	buf = []
	net.appendFrame(buf, .Text, "Hello".bytes(), 0x37fa_213d)
	net.appendFrame(buf, .Close, net.closePayload(1000, "bye"))
	frame = net.Frame()
	first = net.parseFrame(buf, 0, buf.len, frame)
	print("{first} {frame.opcode} {frame.fin} {str(frame.payload)}")
	second = net.parseFrame(buf, first, buf.len, frame)
	print("{second} {frame.opcode} {hex(frame.payload[..2])} {str(frame.payload[2..5])}")
	print(net.parseFrame(buf, 0, 1, frame))
	print(net.parseFrame(buf, 0, 8, frame))
	reserved u8[] = [0xc1, 0x00]
	splitPing u8[] = [0x09, 0x00]
	longPing u8[] = [0x89, 0x7e, 0x00, 0x7e]
	print("{net.parseFrame(reserved, 0, 2, frame)} {net.parseFrame(splitPing, 0, 2, frame)} {net.parseFrame(longPing, 0, 4, frame)}")
	prints """
		11 Text true Hello
		7 Close 03e8 bye
		0
		0
		-1 -1 -1
		"""

# the server: upgrades, then echoes each message in upper case until the client closes
fn serveSocket(listener net.TcpListener):
	conn = listener.accept() ?? return "cannot accept"
	request = conn.nextRequest() ?? return "no request"
	if not request.isUpgrade(): return "not an upgrade"
	answer = []
	net.appendUpgradeResponse(answer, request.header("sec-websocket-key") ?? "")
	conn.send(answer) ?? return "cannot answer"
	seen = 0
	loop:
		message = conn.nextMessage() ?? break
		seen += 1
		reply = str(message.bytes).upper()
		conn.queueFrame(.Text if message.text else .Binary, reply.bytes())
	conn.close()
	"served {seen}"

fn clientSocket(port i64):
	conn = net.tcpConnect("127.0.0.1", port) ?? return "cannot connect"
	key = "dGhlIHNhbXBsZSBub25jZQ=="
	ask = []
	net.appendUpgradeRequest(ask, "/chat", "localhost", key)
	_ = conn.send(ask)
	response = conn.nextResponse() ?? return "no answer"
	if response.status != 101 or
		(response.header("sec-websocket-accept") ?? "") != net.acceptKey(key):
		return "refused"
	mask = 0x1234_5678
	conn.queueFrame(.Text, "hello".bytes(), mask)
	conn.queueFrame(.Ping, "p".bytes(), mask)
	net.appendFrame(conn.out, .Text, "frag".bytes(), mask, false)
	net.appendFrame(conn.out, .Continuation, "mented".bytes(), mask)
	_ = conn.flush()
	seen = []
	loop 2:
		match conn.nextMessage(mask):
			message: seen.push(str(message.bytes))
			error: seen.push("closed")
	conn.queueFrame(.Close, net.closePayload(1000, ""), mask)
	_ = conn.flush()
	conn.close()
	seen.join(" ")

test "a WebSocket session: upgrade, echo, ping, fragments, close":
	listener = net.tcpListen(0) ?? fail("cannot listen")
	port = listener.port()
	job = background((): listener.serveSocket())
	print(clientSocket(port))
	while not job.isDone:
		sleepMs(1)
	print(job.tryReceive() ?? "?")
	prints """
		HELLO FRAGMENTED
		served 2
		"""
