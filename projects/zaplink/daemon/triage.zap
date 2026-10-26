# Priorities set from the page: each one written on its card in the branch `triage` and committed
# there at once (the board reads that branch's priorities, so the page shows them at once); a
# minute after the last one the branch is landed, through `zap branch land` as any branch is.

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

	# a priority to write
	fn ask(card str, level str):
		if level in cards.priorities: pending.push(Asked(card = card.copy(), level = level.copy()))

	# the pending priorities written and committed, the branch landed a minute after the last;
	# whether anything changed on the board
	fn advance(repo str) bool:
		if landing is mut run:
			if not run.hasEnded(): return false
			run.close()
			landing = none
			return true
		if not pending.isEmpty:
			written = self.write(repo)
			pending = []
			if written: changedAt = clockMs()
			return written
		if changedAt != 0 and clockMs() - changedAt > 60_000:
			landing = win.startPiped("{repo}/build/zap.exe branch land triage", repo) ?? none
			changedAt = 0
		false

	# each pending priority written on its card in the triage worktree (made when missing) and
	# committed; whether one was
	fn write(repo str) bool:
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
		commit = ["git", "-C", tree, "commit", "-m", "Priorities: {pending.map("{it.card} {it.level}").join(", ")}", "--"]
		commit.extend(paths)
		Process.output(commit).code == 0
