# HTTP/1.1 messages of std/net: parsed from bytes, written, and carried over a connection with
# keep-alive and pipelining, the connection split into a reader and a writer.

import net

# a connection that holds the bytes and nothing more to read
fn holding(text str):
	net.TcpConn(sock = -1, owns = false, buf = text.bytes(), start = 0, stop = text.len, out = [])

test "a request is parsed with its headers and body, and the next one is left":
	conn = holding("POST /a/b?x=1 HTTP/1.1\r\nHost: h\r\nContent-Length: 3\r\nConnection:  close \r\n\r\nabcGET / HTTP/1.1\r\n")
	request = conn.nextRequest() ?? return
	print(
		"{request.size} {request.method} {request.path()} {request.query()} {request.header("host") ?? "-"}"
	)
	print("{str(request.body)} {request.keepAlive()} {conn.stop - conn.start}")
	prints """
		78 POST /a/b x=1 h
		abc false 16
		"""

# what the next request or response of a connection is: whole, or the error that stopped it
fn requestTold(mut conn net.TcpConn):
	match conn.nextRequest():
		request: "request {request.size}"
		error: "malformed" if error == .Malformed else "waiting"

fn responseTold(mut conn net.TcpConn):
	match conn.nextResponse():
		response: "response {response.size}"
		error: "malformed" if error == .Malformed else "waiting"

test "an incomplete or malformed message is told apart":
	partial = holding("GET / HTTP/1.1\r\nHost: h\r\n")
	chunked = holding("POST / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n")
	short = holding("GET / HTTP/1.1\r\nContent-Length: 5\r\n\r\nab")
	shortResponse = holding("HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nab")
	whole = holding("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nab")
	print(
		"{partial.requestTold()} {chunked.requestTold()} {short.requestTold()} {shortResponse.responseTold()} {whole.responseTold()}"
	)
	prints "waiting malformed waiting waiting response 40"

test "a response is written and read back":
	out = []
	net.appendResponse(out, 404, "text/plain", "gone".bytes())
	print(str(out).replace("\r\n", "|"))
	conn = holding(str(out))
	response = conn.nextResponse() ?? return
	print("{response.size == out.len} {response.status} {response.reason} {str(response.body)} {response.header("content-length") ?? "-"}")
	prints """
		HTTP/1.1 404 Not Found|Content-Type: text/plain|Content-Length: 4||gone
		true 404 Not Found gone 4
		"""

# the client: five requests pipelined in one send, then the five responses read
fn pipelined(port i64):
	conn = net.tcpConnect("127.0.0.1", port) ?? return "cannot connect"
	for i in 0..5:
		conn.queueRequest("GET", "/n/{i}", "localhost")
	conn.queueRequest("POST", "/echo", "localhost", "ping".bytes())
	_ = conn.flush()
	seen = []
	loop 6:
		match conn.nextResponse():
			response: seen.push("{response.status}:{str(response.body)}")
			error: seen.push("closed")
	conn.close()
	seen.join(" ")

# the server: answers each request until the client closes, its replies sent in batches
fn answer(listener net.TcpListener):
	conn = listener.accept() ?? return "cannot accept"
	served = 0
	loop:
		request = conn.nextRequest() ?? break
		served += 1
		if request.method == "POST":
			conn.queueResponse(200, "text/plain", request.body)
		elif request.path().startsWith("/n/"):
			path = request.path()
			conn.queueResponse(200, "text/plain", path[3..].bytes())
		else:
			conn.queueResponse(404, "text/plain", [])
	conn.close()
	"served {served}"

test "keep-alive and pipelining over a connection":
	listener = net.tcpListen(0) ?? fail("cannot listen")
	port = listener.port()
	job = background((): listener.answer())
	print(pipelined(port))
	while not job.isDone:
		sleepMs(1)
	print(job.tryReceive() ?? "?")
	prints """
		200:0 200:1 200:2 200:3 200:4 200:ping
		served 6
		"""

# a reader job takes each line and passes it on; the writer job sends the replies
fn readLines(move c net.TcpConn, lines Channel<str>):
	conn = c
	out = lines
	count = 0
	loop:
		line = conn.receiveLine() ?? break
		out.send(line)
		count += 1
	out.close()
	count

fn writeReplies(move c net.TcpConn, lines Channel<str>):
	conn = c
	count = 0
	loop:
		line = lines.receive() ?? break
		_ = conn.sendLine("reply {line}")
		count += 1
	conn.close()
	count

fn clientOfSplit(port i64):
	conn = net.tcpConnect("127.0.0.1", port) ?? return "cannot connect"
	for i in 0..3:
		_ = conn.sendLine("line {i}")
	replies = []
	loop 3:
		replies.push(conn.receiveLine() ?? "closed")
	conn.close()
	replies.join(", ")

test "a connection split into a reader job and a writer job":
	listener = net.tcpListen(0) ?? fail("cannot listen")
	port = listener.port()
	client = background((): clientOfSplit(port))
	conn = listener.accept() ?? fail("no client")
	sender = conn.writer()
	lines = Channel<str>()
	reading = background((): readLines(conn, lines))
	writing = background((): writeReplies(sender, lines))
	while not client.isDone or not reading.isDone or not writing.isDone:
		sleepMs(1)
	expect (client.tryReceive() ?? "?") == "reply line 0, reply line 1, reply line 2"
	expect (reading.tryReceive() ?? -1) == 3
	expect (writing.tryReceive() ?? -1) == 3
