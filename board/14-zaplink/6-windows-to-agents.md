---
size: S
check: no Claude Code window works on zap; every session is a daemon's agent
branch: adopt
by: 704a3f6e-3fab-463a-9569-01d68ba36a46
---
# Claude Code windows on zap become agents of the daemon

A Claude Code session open on zap in a terminal window is invisible to zaplinkd's page and outside
its limit on agents. Once such a session is idle, it should end in its window and go on as the
daemon's agent, from the same conversation, under its own name.

- [ ] when a window's session is idle (read from `~/.claude/sessions`, `projects/zaplink/cards`),
  the daemon starts an agent of the fleet (`projects/zaplink/agents/fleet.zap`) with
  `claude --resume <session id>` under the session's name, and ends the window's session; the page
  lists the agent with the conversation's earlier steps
- [ ] the check above: with a window session idle, after the daemon's pass no Claude Code process
  works on zap outside a daemon's agent
