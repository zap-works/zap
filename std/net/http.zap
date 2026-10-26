# HTTP/1.1 (RFC 9112) over a TcpConn, for servers and clients: requests and responses parsed from
# the connection's buffer and written into its queue. A server loops on `conn.nextRequest()` and
# `conn.queueResponse(...)`; the queue is sent when the loop waits for the next request, so
# requests pipelined in one read are answered in one send. A message's body is framed by its
# Content-Length; a chunked body, or a head over 64 KiB, is Malformed. A parsed message is a view:
# its text and body are windows into the bytes it was read from (the connection's buffer), so
# nothing is copied, and the connection reads no more while the message is used.

# a header: the name as sent (compare it without case), the value without the spaces around it
pub type Header:
	name str
	value str

pub type Request:
	method ref str
	target ref str   # the path and the query as sent
	minor i64   # HTTP/1.minor
	fields ref str   # the header lines as sent, each ended by CR LF; header() reads them
	body ref u8[]
	size i64   # the bytes it took on the wire

	# The value of the header (named in any case), a window into the message.
	fn header(name str) ref str?:
		headerValue(fields, name)

	# The path of the target, without its query.
	fn path() ref str:
		q = target.indexOf("?") ?? target.len
		target[..q]

	# The query of the target, without the ?.
	fn query() ref str:
		q = target.indexOf("?") ?? return ""
		target[q + 1..]

	# Whether the connection stays open after this request: HTTP/1.1 unless it says close, 1.0 only
	# if it says keep-alive.
	fn keepAlive():
		connection = (self.header("connection") ?? "").lower()
		if minor >= 1: return connection.indexOf("close") == none
		connection.indexOf("keep-alive") != none

pub type Response:
	status i64
	reason ref str
	fields ref str   # the header lines as sent, each ended by CR LF
	body ref u8[]
	size i64

	fn header(name str) ref str?:
		headerValue(fields, name)

# a message's start line as the ends of its three words (the first begins at `start`, the third
# ends at `lineEnd`), where its header lines lie (from `fieldsFrom`, ended by CR LF, to
# `fieldsTo`), and the Content-Length
type Head:
	start i64 = 0
	space i64 = 0
	space2 i64 = 0
	lineEnd i64 = 0
	fieldsFrom i64 = 0
	fieldsTo i64 = 0
	length i64 = 0

headLimit = 65_536
bodyLimit = 1_073_741_824

# the value of the header called name in the header lines: without the spaces around it, a window
# into them
fn headerValue(fields str, name str) ref str?:
	at = 0
	while at < fields.len:
		lineEnd = textIndex(fields, at, fields.len, 13)
		colon = textIndex(fields, at, lineEnd, 58)
		if colon < lineEnd and sameNameAt(fields, at, colon, name):
			from = colon + 1
			to = lineEnd
			while from < to and (fields[from] == 32 or fields[from] == 9):
				from += 1
			while to > from and (fields[to - 1] == 32 or fields[to - 1] == 9):
				to -= 1
			return fields[from..to]
		at = lineEnd + 2
	none

# the index of the byte in text[from..to], or `to`
fn textIndex(text str, from i64, to i64, byte u8):
	i = from
	while i < to and text[i] != byte:
		i += 1
	i

# whether buf[from..to] is the name without regard to the case of ASCII letters
fn sameNameAt(buf str, from i64, to i64, name str):
	if to - from != name.len: return false
	i = 0
	while i < name.len:
		if lowerByte(buf[from + i]) != lowerByte(name[i]): return false
		i += 1
	true

# whether buf[from..to] is the lower-case name, without regard to the case of ASCII letters
fn sameNameIn(buf u8[], from i64, to i64, name str):
	if to - from != name.len: return false
	i = 0
	while i < name.len:
		if lowerByte(buf[from + i]) != name[i]: return false
		i += 1
	true

fn lowerByte(c u8):
	c + 32 if c >= 65 and c <= 90 else c

# whether buf[from..to] starts with the text
fn startsAt(buf u8[], from i64, to i64, text str):
	if to - from < text.len: return false
	i = 0
	while i < text.len:
		if buf[from + i] != text[i]: return false
		i += 1
	true

# the index of the byte in buf[from..to], or `to`
fn byteIndex(buf u8[], from i64, to i64, byte u8):
	i = from
	while i < to and buf[i] != byte:
		i += 1
	i

# the index after the blank line that ends the head at buf[start..stop], 0 while it has not
# arrived
fn headEnd(buf u8[], start i64, stop i64):
	i = start
	while i + 3 < stop:
		c = buf[i + 3]
		if c != 10 and c != 13:
			i += 4   # no blank line can end at i + 3 or begin within the next three bytes
		elif c == 10 and buf[i + 2] == 13 and buf[i + 1] == 10 and buf[i] == 13:
			return i + 4
		else:
			i += 1
	0

# Reads the head (start line and headers) at buf[start..stop] into `head`: the bytes it takes,
# 0 while the blank line has not arrived, -1 when the head is not HTTP/1.x or is too big.
fn parseHead(buf u8[], start i64, stop i64, mut head Head):
	end = headEnd(buf, start, stop.min(start + headLimit))
	if end == 0: return -1 if stop - start >= headLimit else 0
	lineEnd = byteIndex(buf, start, end, 13)
	space = byteIndex(buf, start, lineEnd, 32)
	space2 = byteIndex(buf, space + 1, lineEnd, 32)
	if space2 >= lineEnd: return -1
	head.start = start
	head.space = space
	head.space2 = space2
	head.lineEnd = lineEnd
	head.fieldsFrom = lineEnd + 2
	head.fieldsTo = end - 2
	at = lineEnd + 2
	while at < end - 2:
		lineEnd = byteIndex(buf, at, end, 13)
		colon = byteIndex(buf, at, lineEnd, 58)
		if colon >= lineEnd: return -1
		from = colon + 1
		while from < lineEnd and (buf[from] == 32 or buf[from] == 9):
			from += 1
		to = lineEnd
		while to > from and (buf[to - 1] == 32 or buf[to - 1] == 9):
			to -= 1
		if sameNameIn(buf, at, colon, "content-length"):
			head.length = i64.parse(str(buf[from..to])) ?? return -1
			if head.length < 0 or head.length > bodyLimit: return -1
		elif sameNameIn(buf, at, colon, "transfer-encoding"):
			return -1
		at = lineEnd + 2
	end - start

# The head of a message in buf[start..stop] whose version (the start line's first word for a
# response, its third for a request) is HTTP/1.x: its bytes, 0 while the message is incomplete, -1
# when it is not one.
fn messageHead(buf u8[], start i64, stop i64, mut head Head, versionFirst bool):
	used = parseHead(buf, start, stop, head)
	if used <= 0: return used
	versionAt = head.start if versionFirst else head.space2 + 1
	if not startsAt(buf, versionAt, head.lineEnd, "HTTP/1."): return -1
	if stop - start < used + head.length: return 0
	used

# The request whose head lies at buf[start..], measured in `head` (messageHead's `used` bytes of
# head): a view of those bytes
fn requestIn(buf u8[], start i64, used i64, head Head):
	Request(
		method = buf[start..head.space].text(),
		target = buf[head.space + 1..head.space2].text(),
		minor = 1 if head.lineEnd - head.space2 == 9 and
			startsAt(buf, head.space2 + 1, head.lineEnd, "HTTP/1.1")
		else 0,
		fields = buf[head.fieldsFrom..head.fieldsTo].text(),
		body = buf[start + used..start + used + head.length],
		size = used + head.length
	)

# the response whose head lies at buf[start..], as requestIn is; Malformed for a status that is
# not a number
fn responseIn(buf u8[], start i64, used i64, head Head) Response ? Error:
	Response(
		status = i64.parse(buf[head.space + 1..head.space2].text()) ?? return Error.Malformed,
		reason = buf[head.space2 + 1..head.lineEnd].text(),
		fields = buf[head.fieldsFrom..head.fieldsTo].text(),
		body = buf[start + used..start + used + head.length],
		size = used + head.length
	)

# The reason phrase of a status code.
fn reasonOf(status i64):
	match status:
		101: "Switching Protocols"
		200: "OK"
		201: "Created"
		204: "No Content"
		400: "Bad Request"
		404: "Not Found"
		405: "Method Not Allowed"
		500: "Internal Server Error"
		_: "Status"

# a start line, the headers, and Content-Length (none for a negative length), ended by the blank
# line
fn appendHead(mut out u8[], startLine str, headers Header[], length i64):
	text = "{startLine}\r\n"
	for h in headers:
		text += "{h.name}: {h.value}\r\n"
	if length >= 0:
		text += "Content-Length: {length}\r\n"
	text += "\r\n"
	out.extend(text.bytes())

# the digits of a non-negative number
fn appendDecimal(mut out u8[], n i64):
	if n >= 10: appendDecimal(out, n / 10)
	out.push(48 + n % 10)

# Appends a response to `out`, with Content-Length and the content type.
pub fn appendResponse(mut out u8[], status i64, contentType str, body u8[]):
	out.extend("HTTP/1.1 ".bytes())
	appendDecimal(out, status)
	out.push(32)
	out.extend(reasonOf(status).bytes())
	out.extend("\r\nContent-Type: ".bytes())
	out.extend(contentType.bytes())
	out.extend("\r\nContent-Length: ".bytes())
	appendDecimal(out, body.len)
	out.extend("\r\n\r\n".bytes())
	out.extend(body)

# Appends a request to `out`; a body brings its Content-Length.
pub fn appendRequest(mut out u8[], method str, target str, host str, body u8[]):
	if body.isEmpty:
		out.extend("{method} {target} HTTP/1.1\r\nHost: {host}\r\n\r\n".bytes())
		return
	appendHead(
		out,
		"{method} {target} HTTP/1.1",
		[Header(name = "Host", value = host.copy())],
		body.len if not body.isEmpty else -1
	)
	out.extend(body)

# The next request, waiting for it; Closed when the peer closed first. Bytes after it stay for the
# next call (pipelining). It is a view of the connection's buffer: the connection reads again only
# once the request is no longer used.
pub fn nextRequest(mut tcpConn TcpConn) Request ? Error:
	loop:
		held = try tcpConn.heldRequest()
		if held is request: return request
		try tcpConn.fill()

# The next request if it has arrived whole, without waiting: none while it has not (a server that
# polls its connections in one loop, as nextRequest's view).
pub fn pollRequest(mut tcpConn TcpConn) (Request?) ? Error:
	if tcpConn.stop == tcpConn.start or not tcpConn.holdsMessage(false):
		try tcpConn.fill(false)
	tcpConn.heldRequest()

# whether a whole message's head and body are held
fn holdsMessage(tcpConn TcpConn, versionFirst bool):
	head = Head()
	messageHead(tcpConn.buf, tcpConn.start, tcpConn.stop, head, versionFirst) != 0

# the request held whole in the connection's buffer, taken off it; none while it has not all
# arrived
fn heldRequest(mut tcpConn TcpConn) (Request?) ? Error:
	if tcpConn.stop <= tcpConn.start: return none
	head = Head()
	used = messageHead(tcpConn.buf, tcpConn.start, tcpConn.stop, head, false)
	if used < 0: return Error.Malformed
	if used == 0: return none
	at = tcpConn.start
	tcpConn.start += used + head.length
	requestIn(tcpConn.buf, at, used, head)

# The next response, as nextRequest is.
pub fn nextResponse(mut tcpConn TcpConn) Response ? Error:
	head = Head()
	loop:
		if tcpConn.stop > tcpConn.start:
			used = messageHead(tcpConn.buf, tcpConn.start, tcpConn.stop, head, true)
			if used < 0: return Error.Malformed
			if used > 0:
				at = tcpConn.start
				tcpConn.start += used + head.length
				return try responseIn(tcpConn.buf, at, used, head)
		try tcpConn.fill()

# Queues a response, sent when the connection next waits for input or at flush().
pub fn queueResponse(mut tcpConn TcpConn, status i64, contentType str, body u8[]):
	appendResponse(tcpConn.out, status, contentType, body)

# Queues a request.
pub fn queueRequest(mut tcpConn TcpConn, method str, target str, host str, body u8[] = []):
	appendRequest(tcpConn.out, method, target, host, body)
