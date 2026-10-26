# The plan's board (board/README.md): the cards checked, the next one to take, cards taken by a
# branch, and the board served as a page that follows main's checkout and the branches'
# worktrees as they change.
#
#   zap run tools/board/board.zap check
#   zap run tools/board/board.zap next
#   zap run tools/board/board.zap take <id>... [--branch name] [--by session]
#   zap run tools/board/board.zap serve [--port 8765] [--host 127.0.0.1]

import cards
import fs
import page
import zapx
from cards import Board, Lane

args.options([
	ArgOption(name = "--branch", takesValue = true, help = "the branch that takes the cards (the first id's name)"),
	ArgOption(name = "--by", takesValue = true, help = "the agent's session id (Claude Code's own by default)"),
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
	texts {str: str} = {}
	board = cards.readBoard(here, texts)
	ready = board.placed.find(.lane == .Ready) ?? exit(1, "no card is ready")
	print("{ready.card.id}  {ready.card.title}  ({ready.card.size})  {ready.card.path}")
elif command == "take" and words.len > 1:
	by = args.option("--by") ?? (env.get("CLAUDE_CODE_SESSION_ID") ?? "")
	take(cards.mainCheckout(here), words[1..], args.option("--branch") ?? words[1], by)
elif command == "serve":
	serve(
		here,
		args.option("--host") ?? "127.0.0.1",
		i64.parse(args.option("--port") ?? "") ?? 8765
	)
else:
	exit(2, "usage: board.zap check | next | take <id>... [--branch name] [--by session] | serve [--port n] [--host h]\n{args.usage()}")

# the cards taken by the branch: its worktree made by `zap branch new` when it has none, each
# card's `branch:` and `by:` written there and committed alone as "Take <ids>"
fn take(main str, ids str[], branch str, by str):
	texts {str: str} = {}
	board = cards.readBoard(main, texts)
	for id in ids:
		p = board.placed.find(.card.id == id) ?? exit(1, "{id}: no such card")
		if p.lane == .Doing or p.lane == .Review:
			exit(1, "{id} is {p.lane} in branch {p.branch}")
	tree = "{main}-wt-{branch}"
	if not fs.exists(tree):
		made = Process.output(["{main}/build/zap.exe", "branch", "new", branch.copy()], dir = main)
		if made.code != 0: exit(1, made.out)
	commit = ["git", "-C", tree.copy(), "commit", "-m", "Take {ids.join(" ")}", "--"]
	for id in ids:
		path = (board.placed.find(.card.id == id) ?? continue).card.path
		text = fs.readFile("{tree}/{path}") ?? exit(1, "{tree}/{path}: {error}")
		taken = cards.withKey(text, "branch", branch)
		if by != "": taken = cards.withKey(taken, "by", by)
		fs.writeFile("{tree}/{path}", taken) ?? exit(1, "{path}: {error}")
		commit.push(path.copy())
	committed = Process.output(commit)
	if committed.code != 0: exit(1, committed.out)
	print("{ids.join(", ")} taken by {branch}: {tree}")

# serves the page live on a thread of its own: each viewer shown the board last read again when
# it changes or the viewer acts (only what changed is sent)
fn answer(move live zapx.LiveServer, boards Channel<Board>):
	feed = boards
	board = feed.receive() ?? return
	loop:
		changed = false
		while feed.tryReceive() is next:
			board = next
			changed = true
		events = live.poll()
		for v in live.viewers():
			if changed or events.any(.viewer == v.id):
				live.show(v.id, board.pageNode(v.path))
		if events.isEmpty: sleepMs(5)

# the page at http://host:port/: a job serves it from the board last read, while this thread reads
# the board again
fn serve(dir str, host str, port i64):
	root = cards.mainCheckout(dir)
	live = zapx.liveListen(port, host) ?? exit(1, "cannot listen on {host}:{port}: {error}")
	print("the board of {root} at http://{host}:{port}/")
	boards = Channel<Board>()
	server = background((): answer(live, boards))
	texts {str: str} = {}
	feed = boards
	while not server.isDone:
		feed.send(cards.readBoard(root, texts))
		sleepMs(1_500)
