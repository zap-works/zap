---
needs: [runtime-7, zaplink-4]
size: L
check: from the phone: start an agent on a card, read its steps live, send it an order, kill it
---
# The web app

zapx live pages (runtime-7) served by zaplinkd, the same on the phone and the PC.

- [ ] Agents: each one's state, card, model, tokens and time; start, kill, resume.
- [ ] An agent's steps live, as the terminal shows them but laid out to read on a phone; a box to
  send it an order, and quick ones (stop, finish and land, say what you are doing).
- [ ] Goals and loops, the queue, the limit and the plan's usage.
- [ ] The board (tools/board's page) as a tab.
- [ ] Installable on the phone (PWA) with a notice when an agent ends, stops or asks.
