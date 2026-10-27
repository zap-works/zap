# The daemon coordinates the lands: a branch whose agent finished its card (the card deleted in the
# branch, Review on the board) is landed through `zap branch land`, as many at once as the
# settings' lands (each in a land checkout of its own). Each land's output is kept in the state
# dir. A land that fails is shown on its card and its output's end sent to the branch's agent (the
# last one that worked in its worktree, started again when stopped), or to a new agent started in
# the worktree when it never had one; the branch is landed again once it or main has a new commit.
# After a few failed lands the daemon stops trying and waits for the user's "Land again". An agent
# whose card has left Doing and that waits for nothing is stopped, so its place goes to the next
# card.

import agents
import cards
import fs
import win

# a land under way
type Landing:
	branch str
	card str   # the card the branch finished
	agent str   # the agent that worked in the branch's worktree last, "" for none
	process win.Piped
	out str

	# what the land wrote since, read: whether it ended
	fn ended() bool:
		out = "{out}{str(process.read())}"
		process.hasEnded()

# failed lands of a branch before the daemon waits for the user
landTries = 3

pub type Lander:
	landings Landing[] = []
	tried {str: str} = {}   # the heads (the branch's and main's) each branch was last landed at, so a failed one waits for a new commit
	failed {str: str} = {}   # why each branch's last land failed: its output's last line
	tries {str: i64} = {}   # each branch's failed lands since it last landed or the user asked again

	# the lands under way read, the ended ones told, the next ones started up to the settings'
	# lands; whether the board changed
	fn advance(mut fleet agents.Fleet, board cards.Board, repo str):
		ended = false
		k = landings.len
		while k > 0:
			k -= 1
			if not landings[k].ended(): continue
			self.finish(landings.remove(k), fleet, repo)
			ended = true
		for p in board.placed:
			if landings.len >= fleet.settings.lands: break
			if p.lane != .Review or p.branch == "" or landings.any(.branch == p.branch): continue
			if (tries.get(p.branch) ?? 0) >= landTries: continue
			heads = "{headOf("{repo}-wt-{p.branch}")} {headOf(repo)}"
			if (tried.get(p.branch) ?? "") == heads: continue
			tried[p.branch.copy()] = heads.copy()
			process = win.startPiped("{repo}/build/zap.exe branch land {p.branch}", repo) ?? continue
			landings.push(Landing(branch = p.branch.copy(), card = p.card.id.copy(), agent = fleet.agentOf("{repo}-wt-{p.branch}", p.card.by), process, out = ""))
		ended

	# an ended land kept in the state dir; failed, shown on its card and given to an agent to fix
	# while the tries last
	fn finish(move run Landing, mut fleet agents.Fleet, repo str):
		_ = fs.writeFile("{fleet.dir}/{run.branch}.land.log", run.out)
		passed = run.process.code == 0 and run.out.indexOf("landed") != none
		run.process.close()
		if passed:
			failed.remove(run.branch)
			tries.remove(run.branch)
			return
		lines = run.out.trimmed().lines()
		why = lines[lines.len - 1].copy() if not lines.isEmpty else "the land ended with {run.process.code}"
		count = (tries.get(run.branch) ?? 0) + 1
		tries[run.branch.copy()] = count
		if count >= landTries:
			failed[run.branch.copy()] = "{count} lands failed, waiting for Land again: {why}"
			return
		failed[run.branch.copy()] = why
		tail = run.out[(run.out.len - 3_000).max(0)..].copy()
		fix = "The daemon's land of {run.branch} failed. Its output's end:\n\n{tail}\n\nFix it in the branch and commit (merge main into it for a conflict); the daemon lands it again after your next commit. Never land or merge into main yourself."
		if run.agent != "":
			fleet.message(run.agent, fix)
			return
		tree = "{repo}-wt-{run.branch}"
		id = fleet.ask(repo, fleet.settings.model, fleet.settings.effort, "Read AGENTS.md first. You work in this worktree, on branch {run.branch}. {fix}", run.card, "land {run.branch}")
		if fleet.find(id) is k: fleet.agents[k].dir = tree.copy()

	# the user's "Land again": the branch's tries forgotten, so it lands at the next look
	fn again(branch str):
		tried.remove(branch)
		tries.remove(branch)
		failed.remove(branch)

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
