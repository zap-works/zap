# The daemon driven over loopback by clients as a phone and the PC would be: a session opened by
# one is listed and attached by the other, both see its output, a wrong token is refused.
# host: windows (its one terminal is Windows PowerShell)

import fs
import link
import net
import server

# the daemon on a background job, its state in the test's dir and the port the system picked
# stored in listening (no Windows Terminal there, so its one terminal is Windows PowerShell)
fn startDaemon(running Atomic, listening Atomic):
	state = testDir()
	_ = fs.createDir(fs.join(state, "zaplink"))
	env.set("LOCALAPPDATA", state)
	config = server.Config(host = "127.0.0.1", port = 0, agents = [], dirs = [currentDir()])
	_ = fs.writeFile(fs.join(state, "zaplink/config.json"), config.toJson())
	_ = fs.deleteFile(link.tokenPath())
	background(():
		hub = server.startHub()
		listener = hub.listen() ?? return 1
		listening.store(listener.port())
		hub.serve(listener, running)
		0
	)

# the port the daemon listens on, once it does
fn daemonPort(listening Atomic):
	loop 2000:
		if listening.load() != 0: return listening.load()
		sleepMs(5)
	fail("zaplinkd never listened")
	0

# a client that gave the token, once the daemon listens
fn joined(port i64, token str):
	loop 2000:
		if net.tcpConnect("127.0.0.1", port) is c:
			_ = c.sendFrame(link.Message.Hello(token.copy(), "test").toBytes())
			return c
		sleepMs(5)
	fail("zaplinkd never listened")
	net.tcpConnect("127.0.0.1", port) ?? fail("")

fn tokenOfDaemon():
	loop 2000:
		if fs.readFile(link.tokenPath()) is token: return token
		sleepMs(5)
	fail("zaplinkd wrote no token")
	""

fn kindOf(m link.Message):
	match m:
		Welcome(profiles, agents, dirs): "Welcome"
		Sessions(list): "Sessions"
		Attached(id): "Attached"
		Ended(id, code): "Ended"
		Refused(reason): "Refused"
		_: "other"

fn sessionId(m link.Message):
	match m:
		Attached(id): id
		_: -1

# the first message of that kind to arrive within ten seconds
fn waitFor(mut conn net.TcpConn, kind str) link.Message?:
	start = clockMs()
	while clockMs() - start < 10_000:
		match conn.pollFrame():
			frame:
				if frame is bytes:
					message = link.Message.fromBytes(bytes) ?? continue
					if message.kindOf() == kind: return message
				else:
					sleepMs(2)
			error: return none
	none

# the session's output to this client until it holds text
fn sawOutput(mut conn net.TcpConn, text str):
	seen = []
	start = clockMs()
	while clockMs() - start < 15_000:
		match conn.pollFrame():
			frame:
				if frame is bytes:
					if link.Message.fromBytes(bytes) is Output(out):
						seen.extend(out)
						if str(seen).indexOf(text) != none: return true
				else:
					sleepMs(2)
			error: return false
	false

test "a session opened by one client is shared with another":
	running = Atomic(1)
	listening = Atomic(0)
	job = startDaemon(running, listening)
	port = daemonPort(listening)
	token = tokenOfDaemon()
	pc = joined(port, token)
	welcome = pc.waitFor("Welcome") ?? fail("no welcome")
	match welcome:
		Welcome(profiles, agents, dirs): print(profiles)
		_: print("no welcome")
	pc.sendFrame(link.Message.Create("Windows PowerShell", "", currentDir(), 100, 30).toBytes()) ??
		fail("send")
	attached = pc.waitFor("Attached") ?? fail("not attached")
	id = attached.sessionId()
	phone = joined(port, token)
	listed = false
	loop 20:
		m = phone.waitFor("Sessions") ?? break
		if m is Sessions(list):
			if list.len == 1:
				listed = list[0].id == id and list[0].clients == 1
				break
	print(listed)
	phone.sendFrame(link.Message.Attach(id, 60, 20).toBytes()) ?? fail("send")
	print(phone.waitFor("Attached") != none)
	pc.sendFrame(link.Message.Input("echo (\"zl-\" + 6*7)\r".bytes()).toBytes()) ?? fail("send")
	print("{pc.sawOutput("zl-42")} {phone.sawOutput("zl-42")}")
	stranger = joined(port, "not the token")
	print(stranger.waitFor("Refused") != none)
	phone.sendFrame(link.Message.CloseSession(id).toBytes()) ?? fail("send")
	print("{pc.waitFor("Ended") != none} {phone.waitFor("Ended") != none}")
	running.store(0)
	while not job.isDone:
		sleepMs(1)
	job.tryReceive()
	prints """
		["Windows PowerShell"]
		true
		true
		true true
		true
		true true
		"""
