# Where each card stands, read from git: main's checkout holds the open cards, a branch's
# worktree the cards it took (their `branch:` line) and the ones it finished (deleted, waiting
# for the land), main's history the ones landed (deleted) and when `take` took them.

import fs

pub type Lane:
	Ready   # its needs are landed
	Doing   # a branch took it
	Review   # its branch deleted it: done there, waiting for the land
	Blocked   # its front matter says why it waits
	Backlog   # a card it needs is still open

pub lanes = [Lane.Ready, Lane.Doing, Lane.Review, Lane.Blocked, Lane.Backlog]

pub type Placed:
	card Card
	lane Lane
	branch str   # the branch working on it or that finished it, "" for none
	lastCommit i64   # unix seconds of that branch's last commit, 0 for none
	dirty i64   # files that branch's worktree changed and did not commit
	took i64   # unix seconds of its `take`, 0 when unknown
	agent str   # the session that took it: its name, and "(ended)" when it is gone

pub type Board:
	placed Placed[]
	problems str[]
	ratio f64   # hours taken over hours estimated, on the landed cards whose take is known
	made i64   # unix seconds
	areas Area[]

	# the hours the open cards of the area (every area for "") are expected to take
	fn hoursLeft(area str):
		sum = 0.0
		for p in placed:
			if area == "" or p.card.area == area:
				sum += sizeHours(p.card.size) * ratio
		sum

type Worktree:
	path str
	branch str

# a git command's output in the dir; "" when it fails
fn git(dir str, words str[]):
	argv = ["git", "-C", dir.copy()]
	argv.extend(words.copy())
	ran = Process.output(argv)
	ran.out.copy() if ran.code == 0 else ""

# the checkouts of the repository, main's first
fn worktrees(root str):
	out = []
	path = ""
	for line in git(root, ["worktree", "list", "--porcelain"]).lines():
		if line.startsWith("worktree "):
			path = line[9..].copy()
		elif line.startsWith("branch refs/heads/"):
			out.push(Worktree(path = path.copy(), branch = line[18..].copy()))
	out

# the main checkout of the repository the dir is in
pub fn mainCheckout(dir str) str:
	trees = worktrees(dir)
	trees[0].path.copy() if not trees.isEmpty else dir.copy()

# the unix seconds of each card's latest `take` (commits "Take <id>...", on any branch)
fn takes(root str):
	out {str: i64} = {}
	for line in git(root, ["log", "--all", "--format=%ct %s", "--grep=^Take "]).lines():
		words = line.split(" ")
		if words.len < 3: continue
		at = i64.parse(words[0]) ?? continue
		for id in words[2..]:
			if id not in out or out[id] < at: out[id.copy()] = at
	out

# a card deleted in main's history: the commit and its time
type Deletion:
	commit str
	at i64
	path str

# the card files deleted in the history of rev (newest first), at most `most` of them
fn deletions(root str, rev str, most i64):
	out = []
	commit = ""
	at = 0
	for line in git(
		root,
		["log", rev.copy(), "--diff-filter=D", "--name-only", "--format=@%H %ct", "--", "board/"]
	).lines():
		if line.startsWith("@"):
			words = line[1..].split(" ")
			commit = words[0].copy()
			at = i64.parse(words[1]) ?? 0
		elif idOfPath(line) != "" and out.len < most:
			out.push(Deletion(commit = commit.copy(), at, path = line.copy()))
	out

# the ids of every card ever deleted in main's history: the needs a check accepts besides the open cards
pub fn landedIds(root str) str[]:
	deletions(root, "HEAD", 1_000_000).map(idOfPath(.path))

# a landed card, its text kept in texts by commit and path (a commit's files never change)
fn landedCard(root str, d Deletion, mut texts {str: str}) Card?:
	key = "{d.commit}:{d.path}"
	if key not in texts:
		texts[key.copy()] = git(root, ["show", "{d.commit}^:{d.path}"])
	parseCard(d.path, texts[key]) ?? none

# a Claude Code session running on this machine, as its file in ~/.claude/sessions says
type Session:
	sessionId str
	name str = ""
	status str = ""

fn sessionsRunning():
	dir = "{fs.userDir()}/.claude/sessions"
	out = []
	for name in fs.list(dir) ?? []:
		if not name.endsWith(".json"): continue
		text = fs.readFile("{dir}/{name}") ?? continue
		out.push(Session.fromJson(text) ?? continue)
	out

# the path of a `git status --porcelain` line ("XY path")
fn pathOfStatus(line str):
	line[3..].copy() if line.len > 3 else line.copy()

# a branch at work that took no card (begun before the board, or without `take`): what it
# committed past main or left uncommitted, shown as Doing under the area "no-card"; none when it
# holds neither
fn unlinkedWork(t Worktree, mainBranch str, changed str[], last i64) Placed?:
	ahead = i64.parse(git(t.path, ["rev-list", "--count", "{mainBranch}..HEAD"]).trimmed()) ?? 0
	if ahead == 0 and changed.isEmpty: return none
	subject = git(t.path, ["log", "-1", "--format=%s"]).trimmed()
	title = "{t.branch}: {subject}" if ahead > 0 else "{t.branch}: uncommitted work"
	files = changed.map(pathOfStatus(it))
	body = "{ahead} commits past {mainBranch}, {changed.len} files uncommitted:\n{files.join("\n")}"
	card = Card(
		id = t.branch.copy(),
		area = "no-card",
		areaOrder = 0,
		n = 0,
		path = "",
		title,
		body,
		needs = [],
		size = "",
		check = "",
		blocked = "",
		branch = t.branch.copy(),
		by = "",
		ticked = 0,
		items = 0
	)
	Placed(
		card,
		lane = .Doing,
		branch = t.branch.copy(),
		lastCommit = last if ahead > 0 else 0,
		dirty = changed.len,
		took = 0,
		agent = ""
	)

# the whole board, as main's checkout and the branches' worktrees hold it now
pub fn readBoard(root str, mut texts {str: str}) Board:
	trees = worktrees(root)
	main = trees[0].path.copy() if not trees.isEmpty else root.copy()
	cards, problems = loadCards(main)
	took = takes(main)
	placed = []
	for card in cards:
		placed.push(
			Placed(
				card,
				lane = .Backlog,
				branch = "",
				lastCommit = 0,
				dirty = 0,
				took = took.get(card.id) ?? 0,
				agent = ""
			)
		)
	for t in trees[1..]:
		taken, _ = loadCards(t.path)
		finished = deletions(t.path, "{trees[0].branch}..HEAD", 1_000).map(idOfPath(.path))
		last = i64.parse(git(t.path, ["log", "-1", "--format=%ct"]).trimmed()) ?? 0
		changed = git(t.path, ["status", "--porcelain"]).lines()
		dirty = changed.len
		linked = false
		for mut p in placed:
			copy = taken.find(.id == p.card.id and .branch == t.branch)
			if p.card.id in finished:
				p.lane = .Review
			elif copy is c:
				p.card = c.copy()
				p.lane = .Doing
			else:
				continue
			p.branch = t.branch.copy()
			p.lastCommit = last
			p.dirty = dirty
			linked = true
		if not linked and t.unlinkedWork(trees[0].branch, changed, last) is work:
			placed.push(work)
	sessions = sessionsRunning()
	for mut p in placed:
		if p.card.by == "": continue
		p.agent = "{p.card.by[..8.min(p.card.by.len)]} (ended)"
		if sessions.find(.sessionId == p.card.by) is s:
			p.agent = "{s.name} ({s.status})"
	open = placed.map(.card.id.copy())
	for mut p in placed:
		if p.lane == .Doing or p.lane == .Review: continue
		if p.card.blocked != "": p.lane = .Blocked
		elif p.card.needs.all(it not in open): p.lane = .Ready
	estimated = 0.0
	spent = 0.0
	for d in deletions(main, "HEAD", 40):
		card = landedCard(main, d, texts) ?? continue
		start = took.get(card.id) ?? 0
		if start > 0 and d.at > start:
			estimated += sizeHours(card.size)
			spent += (d.at - start) / 3600.0
	Board(
		placed,
		problems,
		ratio = spent / estimated if estimated > 0.0 else 1.0,
		made = unixSeconds(),
		areas = loadAreas(main)
	)
