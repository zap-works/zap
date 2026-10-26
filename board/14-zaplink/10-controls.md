---
needs: [zaplink-3]
size: M
check: from the page: the pace halved slows the starts, the limit changed holds, an agent past its memory cap is stopped by the system
---
# Controls: the pace, the agents, the machine

Set from the page while the daemon runs, kept in its config.

- [x] The pace of the plan: the window's reset (`resetsAt`) and use come with every agent's
  stream; at pace 1 the use may grow evenly to the reset, at 0.5 half as fast, at 2 twice; no
  agent starts ahead of it. The default model and a ceiling of use beside it.
- [x] The number of agents at once.
- [x] The machine: processor, memory and GPU (`nvidia-smi` when there is one) shown and kept under
  ceilings before an agent starts; each agent's job capped in memory and processor by the system
  (job objects) and its use shown.
