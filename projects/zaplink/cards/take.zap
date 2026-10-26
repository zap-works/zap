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
	tree = "{main}-wt-{branch}"
	if not fs.exists(tree):
		made = Process.output(["{main}/build/zap.exe", "branch", "new", branch.copy()], dir = main)
		if made.code != 0: return TakeRefused(why = made.out.copy())
	commit = ["git", "-C", tree.copy(), "commit", "-m", "Take {ids.join(" ")}", "--"]
	for id in ids:
		path = (board.placed.find(.card.id == id) ?? continue).card.path
		text = fs.readFile("{tree}/{path}") ?? return TakeRefused(why = "{tree}/{path}: {error}")
		taken = withKey(text, "branch", branch)
		if by != "": taken = withKey(taken, "by", by)
		fs.writeFile("{tree}/{path}", taken) ?? return TakeRefused(why = "{path}: {error}")
		commit.push(path.copy())
	committed = Process.output(commit)
	if committed.code != 0: return TakeRefused(why = committed.out.copy())
	tree

# the first message of an agent on a card: the card, its area's README and what the asker added
pub fn briefing(main str, id str, extra str) str:
	cardsNow, _ = loadCards(main)
	card = cardsNow.find(.id == id) ?? return "Work on card {id} of the board (board/). {extra}"
	area = fs.readFile("{main}/{fs.dirOf(card.path)}/README.md") ?? ""
	lines = [
		"Work on card {card.id}, {card.path}, in this worktree (taken for you on its branch).",
		"Read AGENTS.md first. Tick the card's checklist as each part lands in a commit on the branch;",
		"when the step is done, `git rm` the card in the last commit; never land or merge into main.",
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
