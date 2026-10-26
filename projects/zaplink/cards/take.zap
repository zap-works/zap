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
