# The plan's board (board/README.md): the cards checked, the next one to take, cards taken by a
# branch, and the board served as a page that follows main's checkout and the branches'
# worktrees as they change.
#
#   zap run tools/board/board.zap check
#   zap run tools/board/board.zap next
#   zap run tools/board/board.zap take <id>... [--branch name]
#   zap run tools/board/board.zap serve [--port 8765] [--host 127.0.0.1]

import cards
import net
import page
from cards import Lane

args.options([
	ArgOption(name = "--branch", takesValue = true, help = "the branch that takes the cards (the first id's name)"),
	ArgOption(name = "--port", takesValue = true, help = "the port the page is served on"),
	ArgOption(name = "--host", takesValue = true, help = "the address the page is served on")
])
words = args.positional()
command = words[0] if not words.isEmpty else ""
here = currentDir().replace("\\", "/")
if command == "check":
	problems = cards.checkCards(here)
	for line in problems:
		print(line)
	if not problems.isEmpty: exit(1, "{problems.len} problems")
	found, _ = cards.loadCards(here)
	print("{found.len} cards, well formed")
elif command == "next":
	board = cards.readBoard(here)
	ready = board.placed.find(.lane == Lane.Ready) ?? exit(1, "no card is ready")
	print("{ready.card.id}  {ready.card.title}  ({ready.card.size})  {ready.card.path}")
elif command == "take" and words.len > 1:
	take(cards.mainCheckout(here), words[1..], args.option("--branch") ?? words[1])
elif command == "serve":
	serve(
		here,
		args.option("--host") ?? "127.0.0.1",
		i64.parse(args.option("--port") ?? "") ?? 8765
	)
else:
	exit(2, "usage: board.zap check | next | take <id>... [--branch name] | serve [--port n] [--host h]\n{args.usage()}")

# the cards taken by the branch: its worktree made by `zap branch new` when it has none, each
# card's `branch:` written there and committed as "Take <ids>"
fn take(main str, ids str[], branch str):
	board = cards.readBoard(main)
	for id in ids:
		p = board.placed.find(.card.id == id) ?? exit(1, "{id}: no such card")
		if p.lane == Lane.Doing or p.lane == Lane.Review:
			exit(1, "{id} is {p.lane} in branch {p.branch}")
	tree = "{main}-wt-{branch}"
	if not fs.exists(tree):
		made = Process.output(["{main}/build/zap.exe", "branch", "new", branch.copy()], dir = main)
		if made.code != 0: exit(1, made.out)
	for id in ids:
		path = (board.placed.find(.card.id == id) ?? continue).card.path
		text = fs.readFile("{tree}/{path}") ?? exit(1, "{tree}/{path}: {error}")
		fs.writeFile("{tree}/{path}", cards.withKey(text, "branch", branch)) ??
			exit(1, "{path}: {error}")
		_ = Process.output(["git", "-C", tree.copy(), "add", path.copy()])
	committed = Process.output(["git", "-C", tree.copy(), "commit", "-m", "Take {ids.join(" ")}"])
	if committed.code != 0: exit(1, committed.out)
	print("{ids.join(", ")} taken by {branch}: {tree}")

# whether the connection is still open once what arrived is read
fn received(mut conn net.TcpConn) bool:
	conn.fill(wait = false) ?? return false
	true

# whether a whole request's head has arrived (a GET has no body)
fn holdsRequest(conn net.TcpConn) bool:
	conn.stop > conn.start and str(conn.buf[conn.start..conn.stop]).indexOf("\r\n\r\n") != none

# the area a query picks (`area=skyrim`), "" for every area
fn pickedArea(query str) str:
	for part in query.split("&"):
		if part.startsWith("area="): return part[5..].copy()
	""

# the page and its board at http://host:port/, the board read again at most every second
fn serve(dir str, host str, port i64):
	root = cards.mainCheckout(dir)
	listener = net.tcpListen(port, host) ?? exit(1, "cannot listen on {host}:{port}: {error}")
	print("the board of {root} at http://{host}:{port}/")
	conns = []
	board = cards.readBoard(root)
	readAt = clockMs()
	loop:
		busy = false
		if listener.poll() is conn:
			conns.push(conn)
			busy = true
		k = 0
		while k < conns.len:
			if not received(conns[k]):
				conns.remove(k)
				continue
			if holdsRequest(conns[k]):
				request = conns[k].nextRequest() ?? return
				path = request.path().copy()
				picked = pickedArea(request.query())
				if clockMs() - readAt > 1_000:
					board = cards.readBoard(root)
					readAt = clockMs()
				if path == "/":
					conns[k].queueResponse(
						200,
						"text/html; charset=utf-8",
						page.pageText(board, picked).bytes()
					)
				elif path == "/board":
					conns[k].queueResponse(
						200,
						"text/html; charset=utf-8",
						page.boardText(board, picked).bytes()
					)
				else:
					conns[k].queueResponse(404, "text/plain", "no such page".bytes())
				_ = conns[k].flush()
				busy = true
			k += 1
		if not busy: sleepMs(10)
