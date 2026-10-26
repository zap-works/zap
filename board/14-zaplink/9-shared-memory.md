---
needs: [zaplink-4]
size: M
check: an agent on a card starts from the card's handoff and the area's notes; the memory is one for every worktree
---
# Memory shared, compacted and aimed at the task

Agents never start from nothing, and never from everything.

- [ ] One memory for every agent: each worktree's Claude Code project memory joined (a junction) to
  the main checkout's, so what one agent learns the others read.
- [ ] The first message aimed at the task: the card, its handoff, the area's README and the memory
  entries the area names, built by the daemon.
- [ ] A handoff before an agent stops: the daemon asks for at most ten lines on the card (done,
  tried, left) and only durable lessons in the memory.
- [ ] A loop on a small model that compacts the memory and the handoffs (duplicates merged, what
  landed dropped).
