---
needs: [zaplink-5]
size: L
---
# The page shows what each agent changed

zaplink's page (`projects/zaplink/web`) shows each agent's steps but not the files it changed. A
read-only view of what an agent's worktree changed lets the user review work from the phone.

- [ ] the daemon serves, for an agent's worktree, the list of changed files and the diff of one
  (from `git status` and `git diff`, in `projects/zaplink/daemon/serve.zap`); a request returns
  them as text
- [ ] the page shows the tree of changed files, a file's content and its diff in the agent's view
  (`web/agents.zapx`), usable at a phone's width; opening an agent that changed a file shows the
  file and its diff
