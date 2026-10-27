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
	since i64 = 0   # when it started, unix seconds

	# what the land wrote since, read: whether it ended (one past landLimit stopped: a suite that
	# hangs does not hold the lands)
	fn ended() bool:
		out = "{out}{str(process.read())}"
		if not process.hasEnded() and since > 0 and unixSeconds() - since > landLimit:
			process.close()
			out = "{out}\nland: stopped by zaplinkd after {landLimit / 60} minutes"
		process.hasEnded()

# seconds a land may run before the daemon stops it
landLimit = 3_600

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
			# its agent ends its turn first (then it is stopped): a land removes the worktree it is in
			if fleet.agents.any(.dir == "{repo}-wt-{p.branch}" and .state == .Working): continue
			heads = "{agents.headOf("{repo}-wt-{p.branch}")} {agents.headOf(repo)}"
			if (tried.get(p.branch) ?? "") == heads: continue
			# a card's priority set in main meanwhile no longer stops the land
			cards.mergeMain("{repo}-wt-{p.branch}")
			heads = "{agents.headOf("{repo}-wt-{p.branch}")} {agents.headOf(repo)}"
			tried[p.branch.copy()] = heads.copy()
			process = win.startPiped("{repo}/build/zap.exe branch land {p.branch}", repo) ?? continue
			landings.push(Landing(since = unixSeconds(), branch = p.branch.copy(), card = p.card.id.copy(), agent = fleet.agentOf("{repo}-wt-{p.branch}", p.card.by), process, out = ""))
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

# the agents on a card no longer worked on (it went to Review, landed or left the board) that wait
# for nothing, stopped; so is one idle a while on a card still Doing (it stopped before the end,
# its Handoff written), so the card goes back to the queue and resumes; a message starts it again.
# One that stopped with no commit beyond the board (its Handoff at most) leaves its card blocked,
# so the next agent does not try the same again: the user reads the Handoff and decides.
pub fn stopFinished(mut fleet agents.Fleet, board cards.Board):
	now = unixSeconds()
	for a in fleet.agents.copy():
		# queued for a card that landed meanwhile (a land's failure it waited to fix): nothing left
		if a.state == .Queued and a.card != "" and not board.placed.any(.card.id == a.card):
			fleet.kill(a.id)
			continue
		if a.card == "" or a.state != .Idle or a.standing: continue
		doing = board.placed.find(.card.id == a.card and .lane == .Doing)
		if doing is p:
			if a.idleSince == 0 or now - a.idleSince < idleStop: continue
			if a.startHead != "" and onlyBoard(a.dir, a.startHead):
				cards.blockCard(a.dir, p.card.path, "{a.name} stopped with nothing to commit; its Handoff (or its last answer) says why")
		fleet.kill(a.id)

# seconds an agent may stay idle on a card still Doing before it is stopped
idleStop = 900

# whether the worktree's commits since from touch nothing outside board/ (none, or a Handoff)
fn onlyBoard(tree str, from str):
	ran = Process.output(["git", "-C", tree.copy(), "diff", "--name-only", "{from}..HEAD"])
	ran.code == 0 and ran.out.lines().all(.isEmpty or .startsWith("board/"))
