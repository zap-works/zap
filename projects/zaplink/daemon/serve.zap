# The daemon's web server: a job answers the browser at once from the pages last made, while the
# daemon's own loop makes them again as the board and the agents change.

import cards
import net
import web

# whether the connection is still open once what arrived is read
fn received(mut conn net.TcpConn):
	conn.fill(wait = false) ?? return false
	true

# whether a whole request's head has arrived (a GET has no body)
fn holdsRequest(conn net.TcpConn):
	conn.stop > conn.start and str(conn.buf[conn.start..conn.stop]).indexOf("\r\n\r\n") != none

# the board's HTML as the server answers it, and its version, which grows when the HTML changes
type Shown:
	html str
	version i64

# answers the page's requests on a thread of its own, from the board last sent through shown
fn answer(move listener net.TcpListener, shown Channel<Shown>):
	feed = shown
	current = feed.receive() ?? return
	conns = []
	loop:
		busy = false
		while feed.tryReceive() is next:
			current = next
		if listener.poll() is conn:
			conns.push(conn)
			busy = true
		k = 0
		while k < conns.len:
			if not conns[k].received():
				conns.remove(k)
				continue
			if conns[k].holdsRequest():
				request = conns[k].nextRequest() ?? return
				path = request.path()
				if path == "/":
					conns[k].queueResponse(
						200,
						"text/html; charset=utf-8",
						web.pageText(current.html, current.version).bytes()
					)
				elif path == "/board":
					conns[k].queueResponse(200, "text/html; charset=utf-8", current.html.bytes())
				elif path == "/version":
					conns[k].queueResponse(200, "text/plain", "{current.version}".bytes())
				else:
					conns[k].queueResponse(404, "text/plain", "no such page".bytes())
				_ = conns[k].flush()
				busy = true
			k += 1
		if not busy: sleepMs(5)

# the page at http://host:port/: a job answers requests at once from the board last read, while
# this thread reads the board again; /version tells the page when to fetch /board
pub fn serve(root str, host str, port i64):
	listener = net.tcpListen(port, host) ?? exit(1, "cannot listen on {host}:{port}: {error}")
	print("the board of {root} at http://{host}:{port}/")
	shown = Channel<Shown>()
	server = background((): answer(listener, shown))
	texts {str: str} = {}
	last = ""
	version = 0
	feed = shown
	while not server.isDone:
		html = cards.readBoard(root, texts).boardText()
		if html != last:
			version += 1
			last = html.copy()
			feed.send(Shown(html, version))
		sleepMs(1_500)
