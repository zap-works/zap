---
needs: [zaplink-3]
size: M
check: a loop runs on its interval; a goal is pursued again until its check passes
branch: agents2
by: 704a3f6e-3fab-463a-9569-01d68ba36a46
---
# Goals and loops

- [ ] A loop: a prompt run by a fresh agent every N minutes, or again as soon as the last one
  ends (the benchmark agent that is always on), never two at once.
- [ ] A goal: an aim and the command that says it is met; the agent works toward it, and when it
  stops the daemon runs the check and resumes it with the check's output until it passes or a
  budget runs out; an agent can say a goal is met (`zaplink goal done`).
- [ ] Both kept on disk, paused and resumed from the app.
