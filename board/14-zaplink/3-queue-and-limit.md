---
needs: [zaplink-2]
size: M
check: with the limit at 2, three asked agents run two at a time
---
# The queue and the machine's limit

- [ ] One limit for the machine (7 by default): the daemon's running agents plus the Claude Code
  sessions open by hand (~/.claude/sessions); what is over waits in the queue.
- [ ] The queue: asked agents, then the board's Ready cards in order; an agent that ends a card
  frees its place and the next one starts, each card in a fresh session in its worktree (`take`).
- [ ] `zaplink spawn <card> | --prompt "..."` for an agent to ask for another one, through the
  daemon, which decides.
- [ ] AGENTS.md's rules in the scheduler: at most two agents on the compiler; the model by the card.
