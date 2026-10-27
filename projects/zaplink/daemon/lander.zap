# The daemon coordinates the lands: a branch whose agent finished its card (the card deleted in the
# branch, Review on the board) is landed through `zap branch land`, as many at once as the
# settings' lands (each in a land checkout of its own). Each land's output is kept in the state
# dir. A land that fails is shown on its card and its output's end sent to the branch's agent (the
# last one that worked in its worktree, started again when stopped); the branch is landed again
# once it or main has a new commit. An agent whose card has left Doing and that waits for nothing
# is stopped, so its place goes to the next card.

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
	tried {str: str} = {}   # the heads (the branch's and main's) each branch was last landed at, so a failed one waits for a new commit
	failed {str: str} = {}   # why each branch's last land failed: its output's last line

	# the lands under way read, the ended ones dropped, the next ones started up to the settings'
	# lands; whether the board changed
	fn advance(mut fleet agents.Fleet, board cards.Board, repo str):
		ended = false
		k = landings.len
		while k > 0:
			k -= 1
			if landings[k].ended(fleet, failed):
				landings.remove(k)
				ended = true
		for p in board.placed:
			if landings.len >= fleet.settings.lands: break
			if p.lane != .Review or p.branch == "" or landings.any(.branch == p.branch): continue
			heads = "{headOf("{repo}-wt-{p.branch}")} {headOf(repo)}"
			if (tried.get(p.branch) ?? "") == heads: continue
			tried[p.branch.copy()] = heads.copy()
			process = win.startPiped("{repo}/build/zap.exe branch land {p.branch}", repo) ?? continue
			landings.push(Landing(branch = p.branch.copy(), agent = fleet.agentOf("{repo}-wt-{p.branch}", p.card.by), process, out = ""))
		ended

# the land's output read; when it ended, kept in the state dir and, failed, kept in failed (shown on
# its card) and sent to the branch's agent: whether it ended
fn ended(mut run Landing, mut fleet agents.Fleet, mut failed {str: str}):
	run.out = "{run.out}{str(run.process.read())}"
	if not run.process.hasEnded(): return false
	_ = fs.writeFile("{fleet.dir}/{run.branch}.land.log", run.out)
	passed = run.process.code == 0 and run.out.indexOf("landed") != none
	if passed:
		failed.remove(run.branch)
	else:
		lines = run.out.trimmed().lines()
		failed[run.branch.copy()] = lines[lines.len - 1].copy() if not lines.isEmpty else "the land ended with {run.process.code}"
		if run.agent != "":
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
