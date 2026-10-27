# The daemon coordinates the lands: a branch whose agent finished its card (the card deleted in the
# branch, Review on the board) is landed through `zap branch land`, as many at once as the settings' lands (each in a
# land checkout of its own); a land that fails sends its output's end to the branch's agent, and the branch is landed again once it has
# a new commit. An agent whose card has left Doing and that waits for nothing is stopped, so its
# place goes to the next card.

import agents
import cards
import fs
import win

# a land under way
type Landing:
	branch str
	agent str   # the session that took the branch's cards, "" for none
	process win.Piped
	out str

pub type Lander:
	landings Landing[] = []
	tried {str: str} = {}   # the head each branch was last landed at, so a failed one waits for a new commit

	# the lands under way read, the ended ones dropped, the next ones started up to the settings'
	# lands; whether the board changed
	fn advance(mut fleet agents.Fleet, board cards.Board, repo str):
		ended = false
		k = landings.len
		while k > 0:
			k -= 1
			if landings[k].ended(fleet):
				landings.remove(k)
				ended = true
		for p in board.placed:
			if landings.len >= fleet.settings.lands: break
			if p.lane != .Review or p.branch == "" or landings.any(.branch == p.branch): continue
			head = headOf("{repo}-wt-{p.branch}")
			if (tried.get(p.branch) ?? "") == head: continue
			tried[p.branch.copy()] = head.copy()
			process = win.startPiped("{repo}/build/zap.exe branch land {p.branch}", repo) ?? continue
			landings.push(Landing(branch = p.branch.copy(), agent = p.card.by.copy(), process, out = ""))
		ended

# the land's output read; when it ended, a failure sent to the branch's agent: whether it ended
fn ended(mut run Landing, mut fleet agents.Fleet):
	run.out = "{run.out}{str(run.process.read())}"
	if not run.process.hasEnded(): return false
	passed = run.process.code == 0 and run.out.indexOf("landed") != none
	if not passed and run.agent != "" and fleet.find(run.agent) != none:
		tail = run.out[(run.out.len - 3_000).max(0)..].copy()
		fleet.message(run.agent, "The daemon's land of {run.branch} failed. Its output's end:\n\n{tail}\n\nFix it in the branch and commit; the daemon lands it again after your next commit.")
	run.process.close()
	true

# the commit a worktree is at, "" when it is gone
fn headOf(tree str):
	if not fs.exists(tree): return ""
	ran = Process.output(["git", "-C", tree.copy(), "rev-parse", "HEAD"])
	ran.out.trimmed().copy() if ran.code == 0 else ""

# the agents on a card no longer worked on (it went to Review, landed or left the board) that wait
# for nothing, stopped
pub fn stopFinished(mut fleet agents.Fleet, board cards.Board):
	for a in fleet.agents.copy():
		if a.card == "" or a.state != .Idle or a.standing: continue
		if board.placed.any(.card.id == a.card and .lane == .Doing): continue
		fleet.kill(a.id)
