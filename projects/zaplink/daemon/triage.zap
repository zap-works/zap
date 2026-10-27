# Priorities set from the page: each one written on its card in the branch `triage` and committed
# there at once (the board reads that branch's priorities, so the page shows them at once); a
# minute after the last one the branch is landed, through `zap branch land` as any branch is,
# main merged in first (a card landed meanwhile stays gone). A land that fails is tried again a
# minute later, and priorities a daemon before this one left unlanded are landed too.

import cards
import fs
import win

# a priority asked for a card
type Asked:
	card str
	level str

pub type Triage:
	pending Asked[] = []   # not yet written: they wait while a land runs
	changedAt i64 = 0   # clockMs of the last commit not landed, 0 for none
	landing win.Piped? = none

	# priorities a daemon before this one committed and did not land, landed a minute from now
	fn pickUp(repo str):
		ahead = Process.output(["git", "-C", repo.copy(), "rev-list", "--count", "main..triage"])
		if ahead.code == 0 and (i64.parse(ahead.out.trimmed()) ?? 0) > 0: changedAt = clockMs()

	# a priority to write
	fn ask(card str, level str):
		if level in cards.priorities: pending.push(Asked(card = card.copy(), level = level.copy()))

	# the pending priorities written and committed, the branch landed a minute after the last;
	# whether anything changed on the board
	fn advance(repo str):
		if landing is mut run:
			if not run.hasEnded(): return false
			if run.code != 0: changedAt = clockMs()
			run.close()
			landing = none
			return true
		if not pending.isEmpty:
			written = self.write(repo)
			pending = []
			if written: changedAt = clockMs()
			return written
		if changedAt != 0 and clockMs() - changedAt > 60_000:
			catchUp("{repo}-wt-triage")
			landing = win.startPiped("{repo}/build/zap.exe branch land triage", repo) ?? none
			changedAt = 0
		false

	# each pending priority written on its card in the triage worktree (made when missing) and
	# committed; whether one was
	fn write(repo str):
		tree = "{repo}-wt-triage"
		if not fs.exists(tree):
			made = Process.output(["{repo}/build/zap.exe", "branch", "new", "triage"], dir = repo)
			if made.code != 0: return false
		held, _ = cards.loadCards(tree)
		paths = []
		for asked in pending:
			card = held.find(.id == asked.card) ?? continue
			text = fs.readFile("{tree}/{card.path}") ?? continue
			_ = fs.writeFile("{tree}/{card.path}", cards.withKey(text, "priority", asked.level))
			paths.push(card.path.copy())
		if paths.isEmpty: return false
		said = []
		for asked in pending:
			said.push("{asked.card} {asked.level}")
		commit = ["git", "-C", tree, "commit", "-m", "Priorities: {said.join(", ")}", "--"]
		commit.extend(paths)
		Process.output(commit).code == 0

# main merged into the triage worktree: a card main deleted (landed) while a priority was written
# on it stays deleted; any other conflict leaves the merge undone, for the land to say
fn catchUp(tree str):
	if not fs.exists(tree): return
	if Process.output(["git", "-C", tree.copy(), "merge", "-q", "--no-edit", "main"]).code == 0: return
	both = Process.output(["git", "-C", tree.copy(), "diff", "--name-only", "--diff-filter=U"])
	for path in both.out.lines():
		if path == "": continue
		if Process.output(["git", "-C", tree.copy(), "cat-file", "-e", "main:{path}"]).code == 0:
			Process.output(["git", "-C", tree.copy(), "merge", "--abort"])
			return
		Process.output(["git", "-C", tree.copy(), "rm", "-q", path.copy()])
	_ = Process.output(["git", "-C", tree.copy(), "commit", "-q", "--no-edit"])
