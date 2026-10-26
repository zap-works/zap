# httpJson: TechEmpower's plaintext and JSON tests in one run. An HTTP/1.1 server over std/net
# answers 16 clients on the loopback, each with its own connection kept alive: every client writes
# its n requests in pipelined batches of 16 (a plaintext request, then a JSON one, alternating) and
# reads the responses; each JSON response is serialized anew. Prints the requests the clients
# made and the server served, the response bytes read, and the sum of the bodies' bytes.
import net
import problems

type Reply:
	id i64
	message str
	square i64

# what a client read: responses, their bytes in all, and the sum of the body bytes
type Totals:
	responses i64
	bytes i64
	checksum i64

clients = 16
depth = 16
hello = "Hello, World!"

# the id in a query "id=123"
fn idOf(query str):
	i64.parse(query[3..]) ?? 0

fn answer(mut conn net.TcpConn, request net.Request):
	path = request.path()
	if path == "/plaintext":
		conn.queueResponse(200, "text/plain", hello.bytes())
	elif path == "/json":
		id = idOf(request.query())
		reply = Reply(id, message = hello, square = id * id)
		conn.queueResponse(200, "application/json", reply.toJson().bytes())
	else:
		conn.queueResponse(404, "text/plain", [])

# the requests of one connection, answered until the client closes
fn serve(move c net.TcpConn):
	conn = c
	served = 0
	loop:
		request = conn.nextRequest() ?? break
		conn.answer(request)
		served += 1
	conn.close()
	served

# one client: request j of client c is plaintext when j is even, else JSON for id c * n + j
fn client(port i64, c i64, n i64):
	totals = Totals(responses = 0, bytes = 0, checksum = 0)
	conn = net.tcpConnect("127.0.0.1", port) ?? return totals
	j = 0
	while j < n:
		batch = depth.min(n - j)
		for k in j..j + batch:
			if k % 2 == 0:
				conn.queueRequest("GET", "/plaintext", "localhost")
			else:
				conn.queueRequest("GET", "/json?id={c * n + k}", "localhost")
		loop batch:
			response = conn.nextResponse() ?? return totals
			totals.responses += 1
			totals.bytes += response.size
			totals.checksum += response.body.sum(b: i64(b))
		j += batch
	conn.close()
	totals

n = arg(0, 64)
listener = net.tcpListen(0) ?? fail("cannot listen")
port = listener.port()
mut jobs = []
for c in 0..clients:
	jobs.push(background((): client(port, c, n)))
mut servers = []
loop clients:
	connection = listener.accept() ?? fail("cannot accept")
	servers.push(background((): serve(connection)))
mut total = Totals(responses = 0, bytes = 0, checksum = 0)
for mut job in jobs:
	while not job.isDone:
		sleepMs(1)
	if job.tryReceive() is t:
		total.responses += t.responses
		total.bytes += t.bytes
		total.checksum += t.checksum
mut served = 0
for mut server in servers:
	while not server.isDone:
		sleepMs(1)
	served += server.tryReceive() ?? 0
print("requests {total.responses}")
print("served {served}")
print("bytes {total.bytes}")
print("checksum {total.checksum}")

test "the server answers every pipelined plaintext and JSON request":
	main()
	prints """
		requests 1024
		served 1024
		bytes 102650
		checksum 2604922
		"""

test "the C, C++, Rust and Python programs print the same bytes":
	expect problems.agree("httpJson")
