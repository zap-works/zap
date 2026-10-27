# Cards taken by a branch: its worktree made by `zap branch new` when it has none, each card's
# `branch:` and `by:` written there and committed alone as "Take <ids>".

import fs

# why cards could not be taken
pub type TakeRefused:
	why str

# the worktree that took the cards, or why they could not be taken
pub fn takeCards(main str, ids str[], branch str, by str) str ? TakeRefused:
	texts {str: str} = {}
	board = readBoard(main, texts)
	for id in ids:
		p = board.placed.find(.card.id == id) ?? return TakeRefused(why = "{id}: no such card")
		if p.lane == .Doing or p.lane == .Review:
			return TakeRefused(why = "{id} is {p.lane} in branch {p.branch}")
	# a card a branch already holds goes on in that branch's worktree
	into = branch.copy()
	if board.placed.find(.card.id == ids[0] and .resumes) is held: into = held.branch.copy()
	tree = "{main}-wt-{into}"
	if not fs.exists(tree):
		made = Process.output(["{main}/build/zap.exe", "branch", "new", into.copy()], dir = main)
		if made.code != 0: return TakeRefused(why = made.out.copy())
	commit = ["git", "-C", tree.copy(), "commit", "-m", "Take {ids.join(" ")}", "--"]
	for id in ids:
		path = (board.placed.find(.card.id == id) ?? continue).card.path
		text = fs.readFile("{tree}/{path}") ?? return TakeRefused(why = "{tree}/{path}: {error}")
		taken = withKey(text, "branch", into)
		if by != "": taken = withKey(taken, "by", by)
		fs.writeFile("{tree}/{path}", taken) ?? return TakeRefused(why = "{path}: {error}")
		commit.push(path.copy())
	committed = Process.output(commit)
	if committed.code != 0: return TakeRefused(why = committed.out.copy())
	tree

# the card in the worktree tree marked blocked for why, committed there (its lane Blocked until a
# person takes the key out)
pub fn blockCard(tree str, path str, why str):
	text = fs.readFile("{tree}/{path}") ?? return
	fs.writeFile("{tree}/{path}", withKey(text, "blocked", why)) ?? return
	_ = Process.output(["git", "-C", tree.copy(), "commit", "-q", "-m", "Blocked {idOfPath(path)}: {why}", "--", path.copy()])

# main merged into the worktree tree before its land: a card one side deleted (landed in main, or
# finished in the branch) while the other changed it (a priority, a tick) stays deleted; any other
# conflict leaves the merge undone, for the land to report to the branch's agent
pub fn mergeMain(tree str):
	if not fs.exists(tree): return
	if Process.output(["git", "-C", tree.copy(), "merge", "-q", "--no-edit", "main"]).code == 0: return
	both = Process.output(["git", "-C", tree.copy(), "diff", "--name-only", "--diff-filter=U"])
	for path in both.out.lines():
		if path == "": continue
		ours = Process.output(["git", "-C", tree.copy(), "cat-file", "-e", "HEAD:{path}"]).code == 0
		theirs = Process.output(["git", "-C", tree.copy(), "cat-file", "-e", "main:{path}"]).code == 0
		if not path.startsWith("board/") or (ours and theirs):
			Process.output(["git", "-C", tree.copy(), "merge", "--abort"])
			return
		Process.output(["git", "-C", tree.copy(), "rm", "-q", path.copy()])
	_ = Process.output(["git", "-C", tree.copy(), "commit", "-q", "--no-edit"])

# the worktree of the branch that holds the card (Doing or Review), none when no branch does or
# its worktree is gone
pub fn heldTree(main str, id str) str?:
	texts {str: str} = {}
	board = readBoard(main, texts)
	p = try board.placed.find(.card.id == id)
	if p.lane != .Doing and p.lane != .Review: return none
	tree = "{main}-wt-{p.branch}"
	tree if fs.exists(tree) else none

# the first message of an agent on a card: the card, its area's README and what the asker added
pub fn briefing(main str, id str, extra str) str:
	cardsNow, _ = loadCards(main)
	card = cardsNow.find(.id == id) ?? return "Work on card {id} of the board (board/). {extra}"
	area = fs.readFile("{main}/{fs.dirOf(card.path)}/README.md") ?? ""
	lines = [
		"Work on card {card.id}, {card.path}, in this worktree (taken for you on its branch).",
		"Read AGENTS.md first. If the worktree already holds work on the card (git status, git log,",
		"the card's Handoff), go on from it. Tick the card's checklist as each part lands in a commit;",
		"when the step is done, `git rm` the card in the last commit; never land or merge into main.",
		"If you stop before it is done, write a `## Handoff` section at the card's end (at most ten",
		"lines: what is done, what was tried and failed, what is left) and commit it: the next agent",
		"on the card starts from it. Put in the memory only lessons that hold beyond this card.",
		"Report at the end in at most 15 lines.",
		"",
		"The card:",
		fs.readFile("{main}/{card.path}") ?? "",
		"",
		"Its area:",
		area
	]
	if extra != "": lines.push("\nAlso: {extra}")
	lines.join("\n")
