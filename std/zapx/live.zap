# A live page, the LiveView way: the program keeps the state and renders its view, the browser shows
# it and sends back what the viewer does. A page's first request is answered with the whole page,
# client.zap's script in it; the script opens a WebSocket, and each later `show` sends only the
# patches from what that browser holds to the new view (diff.zap), nothing when it did not change.
# The program drives it from its own loop and shows its viewers again whenever its state changes,
# by an action of theirs or by its own work (a timer, a file, an agent's new step):
#
#   live = try zapx.liveListen(8080)
#   loop:
#       events = live.poll()
#       for e in events: (the state changed by e.action)
#       for v in live.viewers(): live.show(v.id, view(state, v.path))
#       if events.isEmpty and nothing else happened: sleepMs(10)

import net

# a form's field as submitted
pub type Field:
	name str
	value str

# what a viewer did
pub type Action:
	Open(path str)   # asked for the page at the path and query: a request, a link followed, the back button
	Click(name str, value str)   # clicked an element with `event="name:value"`
	Submit(name str, fields Field[])   # submitted a form with `event="name"`
	Key(name str, key str, value str)   # a key (the DOM's name) in an element with `keys="name"`, and its value
	Close   # went: closed the page, or never opened its socket

# what a viewer did, by its id
pub type LiveEvent:
	viewer i64
	action Action

# a page open in a browser: its viewer's id and the path and query it shows
pub type Viewer:
	id i64
	path str

type Client:
	id i64
	token str   # the secret in the page that its socket gives to join it
	path str
	shown Node[]   # the page the browser holds, laid out as `flat` does it
	waiting Node[]   # a page shown before the socket joined, sent when it does; empty for none
	sentAt i64   # when the page was sent (clockMs), 0 once its socket joined

# a connection that belongs to a viewer: its page's request, or its socket
type ViewerConn:
	viewer i64
	conn net.TcpConn

# what a request asks: its target, and the WebSocket key of an upgrade ("" for a page)
type Asked:
	target str
	socketKey str

# what a socket the server does not know is sent: the page loaded again
reloadPatch = "[[\"l\"]]"
joinPath = "/zapx-live?s="
unjoinedMs = 60_000

# The pages of a program served live: see the top of this file.
pub type LiveServer:
	listener net.TcpListener
	rng Random
	fresh net.TcpConn[] = []   # connections waiting for a request
	pages ViewerConn[] = []   # page requests waiting for their show
	sockets ViewerConn[] = []
	clients Client[] = []
	nextId i64 = 1

	# The port it listens on.
	fn port() i64:
		listener.port()

	# The viewers with a page open, to show again when the state changes.
	fn viewers() Viewer[]:
		clients.map(c: Viewer(id = c.id, path = c.path.copy()))

	# What the viewers did since the last poll, without waiting: a page asked for is an Open, which
	# waits for its show. Connections are taken, requests and messages read, and a page whose
	# socket never came within a minute is dropped (a Close).
	mut fn poll() LiveEvent[]:
		events LiveEvent[] = []
		while listener.poll() is conn:
			fresh.push(conn)
		self.readRequests(events)
		self.readSockets(events)
		self.dropUnjoined(events)
		events

	# Shows the viewer this view, a page (an `html` element) or what a page's body holds: the whole
	# page to its waiting request, else the patches from what its browser holds over its socket
	# (none when the view did not change), kept until the socket joins when it has none yet.
	mut fn show(viewer i64, view Node):
		c = self.clientAt(viewer) ?? return
		page = livePage(view, clients[c].token)
		match self.requestAt(viewer):
			r:
				request = pages.remove(r)
				conn = move request.conn
				conn.queueResponse(200, "text/html; charset=utf-8", page[0].render().bytes())
				_ = conn.flush()
				fresh.push(conn)
				clients[c].shown = page
				clients[c].sentAt = clockMs()
			none:
				if clients[c].sentAt > 0:
					clients[c].waiting = page
				else:
					self.patch(c, page)

	# the patches from what the client's browser holds to the page, sent on its socket
	mut fn patch(c i64, move page Node[]):
		patches = clients[c].shown.diff(page)
		clients[c].shown = page
		if patches.isEmpty: return
		s = self.socketAt(clients[c].id) ?? return
		sockets[s].conn.queueFrame(.Text, patches.encoded().bytes())
		_ = sockets[s].conn.flush()   # a socket that failed is dropped by the next poll

	mut fn readRequests(mut events LiveEvent[]):
		k = 0
		while k < fresh.len:
			match fresh[k].asked():
				held:
					if held is ask:
						self.answer(fresh.remove(k), ask, events)
					else:
						k += 1
				error:
					_ = fresh.remove(k)

	mut fn answer(move conn net.TcpConn, ask Asked, mut events LiveEvent[]):
		if ask.socketKey != "":
			self.join(conn, ask)
			return
		if ask.target == "/favicon.ico":
			conn.queueResponse(404, "text/plain", [])
			_ = conn.flush()
			fresh.push(conn)
			return
		id = nextId
		nextId += 1
		clients.push(
			Client(
				id,
				token = "{rng.nextBits():x}{rng.nextBits():x}",
				path = ask.target.copy(),
				shown = [],
				waiting = [],
				sentAt = 0
			)
		)
		pages.push(ViewerConn(viewer = id, conn))
		events.push(LiveEvent(viewer = id, action = .Open(ask.target.copy())))

	# the socket upgraded and joined to the page that carries its token, which is sent what was
	# shown meanwhile; one the server does not know is told to load the page again
	mut fn join(move conn net.TcpConn, ask Asked):
		net.appendUpgradeResponse(conn.out, ask.socketKey)
		token = ask.target[joinPath.len..] if ask.target.startsWith(joinPath) else ""
		match self.unjoined(token):
			c:
				clients[c].sentAt = 0
				sockets.push(ViewerConn(viewer = clients[c].id, conn))
				if not clients[c].waiting.isEmpty:
					page = move clients[c].waiting
					clients[c].waiting = []
					self.patch(c, page)
				else:
					_ = sockets[sockets.len - 1].conn.flush()
			none:
				conn.queueFrame(.Text, reloadPatch.bytes())
				_ = conn.flush()

	mut fn readSockets(mut events LiveEvent[]):
		k = 0
		while k < sockets.len:
			match sockets[k].conn.pollMessage():
				held:
					if held is message and message.text:
						if actionOf(str(message.bytes)) is action:
							self.act(sockets[k].viewer, action.copy(), events)
					k += 1
				error:
					viewer = sockets.remove(k).viewer
					self.forget(viewer, events)

	mut fn act(viewer i64, move action Action, mut events LiveEvent[]):
		if action is Open(path) and self.clientAt(viewer) is c:
			clients[c].path = path.copy()
		events.push(LiveEvent(viewer, action))

	mut fn dropUnjoined(mut events LiveEvent[]):
		now = clockMs()
		gone = clients.filter(c: c.sentAt > 0 and now - c.sentAt > unjoinedMs).map(.id)
		for viewer in gone:
			self.forget(viewer, events)

	mut fn forget(viewer i64, mut events LiveEvent[]):
		c = self.clientAt(viewer) ?? return
		_ = clients.remove(c)
		if self.requestAt(viewer) is r: _ = pages.remove(r)
		if self.socketAt(viewer) is s: _ = sockets.remove(s)
		events.push(LiveEvent(viewer, action = .Close))

	fn clientAt(viewer i64) i64?:
		for c, client in clients:
			if client.id == viewer: return c
		none

	# the client whose page carries the token and whose socket has not joined
	fn unjoined(token str) i64?:
		for c, client in clients:
			if client.sentAt > 0 and client.token == token: return c
		none

	fn requestAt(viewer i64) i64?:
		for r, page in pages:
			if page.viewer == viewer: return r
		none

	fn socketAt(viewer i64) i64?:
		for s, socket in sockets:
			if socket.viewer == viewer: return s
		none

# A live page server on a port of one interface, as net.tcpListen (the loopback one unless host
# says another; port 0 for a free one, which `port()` says).
pub fn liveListen(port i64, host str = "127.0.0.1") LiveServer ? net.Error:
	listener = try net.tcpListen(port, host)
	LiveServer(listener, rng = Random(clockMs() ^ processorCycles()))

# the request on the connection if it has arrived whole
fn asked(mut conn net.TcpConn) (Asked?) ? net.Error:
	held = try conn.pollRequest()
	request = held ?? return none
	key = ""
	if request.isUpgrade(): key = (request.header("sec-websocket-key") ?? "").copy()
	Asked(target = request.target.copy(), socketKey = key)

# the view as the page sent, laid out as `flat` does it: a page gets the client's script at the end
# of its body; anything else is a page's body
fn livePage(view Node, token str) Node[]:
	script = element("script", [attr("data-zapx", token)], [text(clientScript)])
	page = view.flat()
	if page.len == 1 and page[0] is Element(tag, _, mut kids) and tag == "html":
		last = kids.len - 1
		if last >= 0 and kids[last] is Element(name, _, mut inner) and name == "body":
			inner.push(script)
		else:
			kids.push(element("body", [], [script]))
		return page
	head = element(
		"head",
		[],
		[
			element("meta", [attr("charset", "utf-8")], []),
			element(
				"meta",
				[attr("name", "viewport"), attr("content", "width=device-width, initial-scale=1")],
				[]
			)
		]
	)
	element("html", [], [head, element("body", [], [fragment(page), script])]).flat()

# the action a client's message tells (a JSON list of strings, client.zap's), none for another
fn actionOf(message str) Action?:
	words = str[].fromJson(message) ?? return none
	if words.isEmpty: return none
	kind = words[0]
	if kind == "click": return .Click(word(words, 1), word(words, 2))
	if kind == "nav": return .Open(word(words, 1))
	if kind == "key": return .Key(word(words, 1), word(words, 2), word(words, 3))
	if kind != "submit": return none
	fields = []
	i = 2
	while i + 1 < words.len:
		fields.push(Field(name = words[i].copy(), value = words[i + 1].copy()))
		i += 2
	.Submit(word(words, 1), fields)

fn word(words str[], i i64) str:
	words[i].copy() if i < words.len else ""
