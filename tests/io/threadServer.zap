# A server with one background job per connection: three clients connect at once, each sends
# lines and gets them echoed with a count; each job's result is its connection's summary.

import net

fn client(id i64, port i64):
	match net.tcpConnect("127.0.0.1", port):
		c:
			conn = move c
			echoed = 0
			for i in 0..50:
				_ = conn.sendLine("client {id} line {i}")
				if conn.receiveLine() is reply:
					if reply == "echo {i}: client {id} line {i}":
						echoed += 1
			_ = conn.sendLine("bye")
			conn.close()
			if echoed != 50:
				eprint("client {id}: only {echoed} echoes")
		error: eprint("client {id}: cannot connect")

fn serve(move c net.TcpConn):
	conn = c
	lines = 0
	who = ""
	going = true
	while going:
		match conn.receiveLine():
			line:
				if line == "bye":
					going = false
				else:
					if who == "":
						who = line.split(" ")[1]
					_ = conn.sendLine("echo {lines}: {line}")
					lines += 1
			error: going = false
	conn.close()
	"client {who}: {lines} lines"

# how long the server waits for a client: one that never comes fails the test instead of hanging it
waitMs = 60_000

if args.len > 2 and args[0] == "client":
	client(i64.parse(args[1]) ?? 1, i64.parse(args[2]) ?? 0)
	return
# a free port from the system: runs side by side never share one
match net.tcpListen(0):
	listener:
		jobs = []
		children = []
		for id in 1..4:
			children.push(Process.start("\"{exePath()}\" client {id} {listener.port()}"))
		loop 3:
			match listener.accept(within = waitMs):
				c: jobs.push(background((): serve(c)))
				error: print("accept failed")
		summaries = []
		since = clockMs()
		for mut job in jobs:
			while not job.isDone and clockMs() - since < waitMs:
				sleepMs(1)
			summaries.push(job.tryReceive() ?? "?")
		for s in summaries.sorted():
			print(s)
		for i in 0..children.len:
			if children[i].waitWithin(waitMs) == none: print("client {i + 1} still runs")
	error: print("cannot listen")

test "each connection's job echoes its lines with a count":
	main()
	prints """
	    client 1: 50 lines
	    client 2: 50 lines
	    client 3: 50 lines
	    """
