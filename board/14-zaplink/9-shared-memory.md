---
size: M
check: an agent on a card starts from the card's handoff and the area's notes; the memory is one for every worktree
branch: agents3
by: 704a3f6e-3fab-463a-9569-01d68ba36a46
priority: P1
---
# Agents share one memory that is compacted and aimed at the task

Agents never start from nothing, and never from everything. The daemon's agents
(`projects/zaplink/agents`) read one memory and a first message built for their card.

- [x] one memory for every agent: each worktree's Claude Code project memory is joined (a
  junction) to the main checkout's, so what one agent learns the others read
- [x] the first message is aimed at the task: the card, its handoff, the area's README and the
  memory entries the area names, built by the daemon
- [x] a handoff before an agent stops: the daemon asks for at most ten lines on the card (done,
  tried, left) and only durable lessons in the memory
- [ ] a loop on a small model that compacts the memory and the handoffs (duplicates merged, what
  landed dropped): add it to the daemon's loops (`projects/zaplink/agents/plans.zap`); after a run
  the memory index has no two entries on one fact, and no handoff of a landed card remains
