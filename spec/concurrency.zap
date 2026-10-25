# 9. Concurrency
#
# Work beside the program runs on system threads: a background job (`background(f)`, below), the
# steps of a parallel pipeline (`.parallel()`) and an `Atomic` they share; no green threads and no
# async/await, which colours every function on the call chain. A `Channel<T>` is the queue between
# a job and the thread that started it. `Channel<T>(n)` holds up to n values (`Channel<T>()` is
# unbounded): `send(v)` waits while it is full and gives false once it is closed; `receive()` waits
# while it is empty and gives `T?`, none once closed and drained; `tryReceive()` gives `T?` at once;
# `len` counts the queued values and `close()` closes it. The program ends when its top-level
# statements end.

import net

fn worker(id i64, ch Channel<str>, n i64):
	out = ch
	for i in 0..n:
		out.send("w{id}:{i}")
	n

test "a job and its starter share a channel":
	ch = Channel<str>(2)
	job = background((): worker(1, ch, 5))
	got = []
	loop 5:
		if ch.receive() is v:
			got.push(v)
	print(got)
	while not job.isDone:
		sleepMs(1)
	print(job.tryReceive() ?? 0)
	results = Channel<i64>()
	sends = results
	for k in 1..4:
		sends.send(k * k)
	sum = 0
	loop 3:
		sum += results.receive() ?? 0
	print(sum)
	done = Channel<bool>(1)
	flags = done
	print(flags.send(true))
	done.close()
	print("{done.receive() ?? false} {done.receive() == none} {done.send(true)} {ch.tryReceive() == none} {ch.len}")
	prints """
		["w1:0", "w1:1", "w1:2", "w1:3", "w1:4"]
		5
		14
		true
		true true false true 0
		"""

# What a channel carries goes to another thread, so it is a value of its own, never a reference.
test "a channel carries values, not references" refuses SharedHoldsReference:
	ch = Channel<ref str>()
	print(ch.len)

# A `receive` on an empty channel (or a `send` on a full one) with no background job alive to
# answer stops the program with `deadlock`.

test "a receive no job can answer" stops Failure("deadlock: receive on an empty channel with no job to send"):
	ch = Channel<i64>()
	print(ch.receive() ?? 0)

# Data parallelism: `.parallel()` is a pipeline step; what follows runs on every processor and
# gives what the sequential pipeline gives, in order. The source is a range or a list by its name
# or field; `map`, `filter`, `flatMap`, `sum`, `count`, `any`, `all`, `minBy`, `maxBy`, `sortedBy`
# and `for` follow it. A parallel `for` changes outer state only at an index made from its variable
# or a local computed from it (`out[i] = ...`), never a whole variable or a list's length.
#
# `for x in src.parallel().map(f)` reads the results in order as the threads make them, each `x`
# the result itself (owned); leaving the loop early gives the rest up. The body is the reader's own
# code: it may change anything, as any loop's body does.

type Mob:
	hp i64
	alive bool

type Pair:
	index i64
	square i64

fn churn(i i64):
	x = i
	loop 50:
		x = (x * 31 + 7) % 1_000_003
	x

test "parallel pipelines give what the serial ones give":
	ms = (0..100).map(Mob(hp = it, alive = it % 3 == 0))
	print("{ms.parallel().filter(.alive).sum(.hp)} {ms.parallel().count(.alive)} {ms.parallel().map(.hp).len} {ms.parallel().filter(.alive).map(.hp * 2).len}")
	print("{ms.parallel().any(.hp == 99)} {ms.parallel().all(.hp < 100)}")
	print((0..20000).parallel().map(churn).sum() == (0..20000).map(churn).sum())
	print((1..11).parallel().map(i: i * i))
	squares = zeros(1000)
	for i in (0..1000).parallel():
		squares[i] = i * i
	print(squares[999])
	prints """
	    1683 34 100 34
	    true true
	    true
	    [1, 4, 9, 16, 25, 36, 49, 64, 81, 100]
	    998001
	    """

test ".parallel().map gives the results in order; the closure reads what it captured":
	squares = (0..1000).parallel().map(i: i * i)
	sum = 0
	for s in squares:
		sum += s
	print("{squares.len} squares, sum {sum}")
	base = 7
	pairs = (0..16).parallel().map(i: Pair(index = i, square = (i + base) * (i + base)))
	print("{pairs[0].index} {pairs[0].square} {pairs[15].index} {pairs[15].square}")
	names = (0..5).parallel().map(i: "item {i}")
	print(names)
	counts = []
	for i in 0..50:
		counts.push(i)
	totals = (0..4).parallel().map(part:
		t = 0
		for c in counts:
			if c % 4 == part:
				t += c
		t
	)
	print(totals)
	empty = (0..0).parallel().map(i: i)
	print(empty.len)
	print(cpuCount() >= 1)
	prints """
	    1000 squares, sum 332833500
	    0 49 15 484
	    ["item 0", "item 1", "item 2", "item 3", "item 4"]
	    [312, 325, 288, 300]
	    0
	    true
	    """

test "a for over a parallel map reads the results in order as they are made":
	seen = []
	for s in (0..200).parallel().map(i: "{churn(i) % 10}"):
		seen.push(s)
	print("{seen.len} {seen == (0..200).map("{churn(it) % 10}")}")
	firsts = []
	for v in (0..1000).parallel().map(i: [i, i * i]):
		if v[0] == 5: break
		firsts.push(v[1])
	print(firsts)
	for _ in (0..0).parallel().map(i: i):
		print("none")
	prints """
		200 true
		[0, 1, 4, 9, 16]
		"""

test "a parallel loop writes at an index made from a local of its own variable":
	pairs = zeros(20)
	for i in (0..10).parallel():
		at = i * 2
		pairs[at] = i
		pairs[at + 1] = i * 2
	expect pairs[19] == 18

test "a parallel loop changes what is outside it only at its own index" refuses ParallelChange:
	mut total = 0
	for i in (0..10).parallel():
		total += i
	print(total)

test "a parallel loop cannot grow a list outside it" refuses ParallelChangeBy:
	mut out i64[] = []
	for i in (0..10).parallel():
		out.push(i)
	print(out)

test "a parallel loop cannot give a list outside it to a function that changes it" refuses ParallelMutArgument:
	fn mark(mut seen i64[], i i64):
		seen.push(i)
	mut seen i64[] = []
	for i in (0..10).parallel():
		mark(seen, i)
	print(seen)

test "a parallel loop writes elements only at its own index" refuses ParallelIndex:
	mut xs = zeros(10)
	for i in (0..10).parallel():
		xs[0] = i
	print(xs)

test "parallel() stands only at the start of a pipeline" refuses ParallelStartsPipeline:
	xs = [1, 2]
	p = xs.parallel()
	print(p)

test "only some steps run in parallel" refuses NotParallel:
	xs = [2, 1]
	print(xs.parallel().reduce(0, (a, x): a + x))

test "sortedBy, minBy and maxBy in parallel give what the serial ones give":
	n = 20_000
	ms = (0..n).map(Mob(hp = (it * 7919) % 1000, alive = it % 2 == 0))
	a = ms.sortedBy(.hp).map(.hp)
	b = ms.parallel().sortedBy(.hp).map(.hp)
	c = ms.parallel().filter(.alive).sortedBy(1000 - .hp).map(.hp)
	print("{a == b} {c == ms.filter(.alive).sortedBy(1000 - .hp).map(.hp)}")
	print(
		ms.parallel().minBy((.hp - 500).abs())?.hp == ms.minBy((.hp - 500).abs())?.hp
	)
	print("{c.len / 2} {ms.parallel().maxBy(.hp % 3)?.hp == ms.maxBy(.hp % 3)?.hp}")
	prints """
	    true true
	    true
	    5000 true
	    """

test "minBy runs in parallel over the list itself" refuses ParallelNeedsName:
	xs = [2, 1]
	print(xs.parallel().filter(x: x > 1).minBy(x: x) ?? 0)

test "a range bound that calls a function is read once" refuses ParallelRangeBounds:
	mut calls = 0
	fn top() i64:
		calls += 1
		10
	print((0..top()).parallel().map(i: i * 2))
	print(calls)

# The lambdas and the loop body run on several threads at once: they may read what they captured
# and build what they return, and read outside the program (a file, the clock), but not act outside
# it (print, write a file, send, draw) or change a module variable. Code another thread runs is
# checked through every function it calls or names, the runtime's included, and the error names the
# chain; the call of a function value it was given is not followed. An `Atomic` counts or flags
# across threads.

test "a parallel lambda is checked through the functions it calls" refuses ParallelEffect("parallel() runs this on several threads at once: it cannot act outside the program (print, write, send) (note -> print)"):
	fn note(x i64) i64:
		print(x)
		x
	print((0..10).parallel().map(i: note(i)).len)

fn readsTheClock(i i64):
	i if clockMs() >= 0 else 0

test "a parallel lambda may read outside the program and call pure functions":
	expect (0..100).parallel().map(readsTheClock(churn(it))).sum() == (0..100).map(churn).sum()

# Background work: `background(f)` starts `f`, a closure owning its captures, on a system thread
# and gives a `Background<T>`: `job.isDone` says whether the result is in without waiting, and
# `job.tryReceive()` hands it over once (`T?`). A frame loop starts the work it will need and
# collects what is done each frame. Jobs run on threads of their own (one per processor less one).
# A job's closure runs once, so its body may give away what it captured (`background(():
# serve(conn))` with `fn serve(move c TcpConn)`).

test "a job takes what it carries" refuses UseAfterCapture:
	fn count(xs i64[]) i64:
		xs.len
	mut xs = [1, 2]
	mut job = background((): count(xs))
	xs.push(3)
	print(job.isDone)

fn slowSum(n i64):
	s = 0
	for i in 0..n:
		s += i % 7
	s

test "jobs run on other threads and are taken once each":
	jobs = []
	for k in 0..8:
		jobs.push(background((): (k, slowSum(1_000_000 + k))))
	order = []
	sums i64[8]
	while order.len < jobs.len:
		for mut job in jobs:
			if job.tryReceive() is (k, sum):
				order.push(k)
				sums[k] = sum
	print(order.sortedBy(it))
	print("{sums[0]} {sums[7]}")
	name = "chunk"
	b = background((): "{name} {slowSum(3)}")
	while not b.isDone:
		sleepMs(1)
	print(b.tryReceive() ?? "none")
	print(b.tryReceive() ?? "taken")
	prints """
	    [0, 1, 2, 3, 4, 5, 6, 7]
	    2999997 3000018
	    chunk 3
	    taken
	    """

# A job runs beside the thread that started it, which goes on changing what it likes, so the job
# neither changes nor reads a module variable that can change and prints nothing (the console is the
# starting thread's), checked as a parallel lambda is; it may act outside the program (a device, a
# file). What it needs is captured when it starts, and what it makes goes back as its result or
# through a `Channel` between the job and the thread that started it: a job's `receive` waits for
# the other thread, and a `send` on a channel without a capacity never waits, so a job that must
# keep time (a sound card's) sends what it reports and takes its orders with `tryReceive()`. The
# job is a lambda or a function's name, so that what it does is seen.

fn mixer(orders Channel<i64>, reports Channel<str>):
	total = 0
	ins = orders
	outs = reports
	loop:
		order = ins.receive() ?? break
		total += order
		outs.send("mixed {order}")
	total

test "a job and the thread that started it talk through channels":
	orders = Channel<i64>()
	reports = Channel<str>()
	job = background((): mixer(orders, reports))
	send = orders
	for k in 1..4:
		send.send(k * 10)
	got = []
	back = reports
	while got.len < 3:
		got.push(back.receive() ?? "")
	send.close()
	while not job.isDone:
		sleepMs(1)
	expect got == ["mixed 10", "mixed 20", "mixed 30"]
	expect (job.tryReceive() ?? 0) == 60

test "a job does not read a module variable that can change" refuses JobEffect("it cannot read a module variable that can change (capture what it needs) (queued -> 'pending')"):
	mut pending i64[] = []
	fn queued() i64:
		pending.len
	mut job = background((): queued())
	pending.push(1)
	print(job.isDone)

test "a job is a lambda or a function's name" refuses JobBodyUnseen:
	f = (): 1
	mut job = background(f)
	print(job.isDone)

# Networking (`import net`, IPv4): TCP and UDP sockets, what fails a `net.Error` (`zap doc net`).
# `net.tcpListen(port)` listens on the loopback interface, which no firewall asks about, unless a
# `host` is given; port 0 asks the system for a free one. Sockets never block the process: a server
# of many connections polls from one loop (`poll()` gives what has arrived or none, never waiting).
# A socket closes when it goes (one is never copied, so it closes once).

# the client's side, whether it connected
fn client(port i64):
	conn = net.tcpConnect("127.0.0.1", port) ?? return false
	_ = conn.sendLine("hello")
	_ = conn.sendLine("3 + 4")
	if conn.receiveLine() is reply:
		_ = conn.sendLine("got {reply}")
	_ = conn.sendFrame("framed".bytes())
	_ = conn.sendLine("bye")
	conn.close()
	true

# the server's side: what its one client said
fn served(listener net.TcpListener) str[]:
	conn = listener.accept() ?? return []
	conn.serve()

fn serve(mut conn net.TcpConn):
	said = []
	loop:
		line = conn.receiveLine() ?? break
		said.push(line.copy())
		if line == "3 + 4":
			_ = conn.sendLine("7")
		elif line == "got 7":
			frame = conn.receiveFrame() ?? break
			said.push(str(move frame))
		elif line == "bye": break
	conn.close()
	said

test "a server and a client, the server a background job":
	listener = net.tcpListen(0) ?? fail("cannot listen")
	port = listener.port()
	job = background((): listener.served())
	print(client(port))
	while not job.isDone:
		sleepMs(1)
	print(job.tryReceive() ?? [])
	prints """
		true
		["hello", "3 + 4", "got 7", "framed", "bye"]
		"""

# the next connection, polled for
fn accepted(listener net.TcpListener):
	loop:
		if listener.poll() is conn: return conn
		sleepMs(1)

test "one loop polls a listener and its connections":
	listener = net.tcpListen(0) ?? fail("cannot listen")
	print(listener.poll() == none)
	conn = net.tcpConnect("127.0.0.1", listener.port()) ?? fail("cannot connect")
	peer = listener.accepted()
	print((peer.pollFrame() ?? none) == none)
	_ = conn.sendFrame("one".bytes())
	_ = conn.sendFrame("two".bytes())
	got = []
	while got.len < 2:
		match peer.pollFrame():
			frame:
				if frame is bytes: got.push(str(bytes))
				else: sleepMs(1)
			error: break
	print(got)
	conn.close()
	closed = false
	loop 1000:
		if peer.poll(16) is error:
			closed = error == .Closed
			break
		sleepMs(1)
	print(closed)
	prints """
		true
		true
		["one", "two"]
		true
		"""

# UDP: `net.udpBind(host, port)` gives a `UdpSocket` that sends and receives `Datagram`s.

type Msg:
	Hello(name str)
	Move(id i64, x f64, y f64)
	Welcome(id i64)
	Bye

# the exchange as the lines it prints; none when a socket or a datagram is missing
fn exchange() str[]?:
	server = net.udpBind("127.0.0.1", 0) ?? return none
	client = net.udpBind("127.0.0.1", 0) ?? return none
	log = []
	to = net.endpoint("127.0.0.1", server.port())
	_ = client.sendTo(to, Msg.Hello("ana").toBytes())
	d = server.receiveFrom() ?? return none
	log.push(
		"server got {try Msg.fromBytes(d.bytes)} from port {d.sender.port() == client.port()}"
	)
	_ = server.sendTo(d.sender, Msg.Welcome(7).toBytes())
	reply = client.receiveFrom() ?? return none
	log.push("client got {try Msg.fromBytes(reply.bytes)}")
	_ = client.sendTo(to, Msg.Move(7, 1.5, -2.0).toBytes())
	_ = client.sendTo(to, Msg.Bye.toBytes())
	loop 2:
		m = server.receiveFrom() ?? return none
		log.push("server got {try Msg.fromBytes(m.bytes)}")
	log.push("nothing more: {server.poll() == none}")
	client.close()
	server.close()
	log

test "datagrams carry typed messages both ways":
	for line in exchange() ?? ["the exchange failed"]:
		print(line)
	prints """
	    server got Hello("ana") from port true
	    client got Welcome(7)
	    server got Move(7, 1.5, -2)
	    server got Bye
	    nothing more: true
	    """

# An `Atomic` at a module's top is one value every thread shares (2.4), so a background job
# reaches it without capturing it.

jobFlag = Atomic(0)

test "a background job changes a module's atomic":
	job = background(():
		jobFlag.store(9)
		jobFlag.compareSwap(9, 10)
	)
	while not job.isDone:
		sleepMs(1)
	expect job.tryReceive() ?? false
	expect jobFlag.load() == 10
