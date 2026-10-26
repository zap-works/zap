---
size: L
check: zaplinkd starts an agent, shows its steps, sends it a message, kills and resumes it
branch: agents
by: 704a3f6e-3fab-463a-9569-01d68ba36a46
---
# Agents run by the daemon

Each agent is `claude -p --input-format stream-json --output-format stream-json --verbose
--session-id <id>` (or `--resume <id>`) in a dir, with a model and bypassed permissions, its
ANTHROPIC_API_KEY removed so it uses the subscription.

- [ ] Start, kill, resume; a message sent into the running session.
- [ ] Each event of the stream kept per agent (text, tool calls with their input and output,
  results, cost and tokens), on disk so a restart of the daemon keeps them.
- [ ] Agents resumed after a reboot or a restart of the daemon.
