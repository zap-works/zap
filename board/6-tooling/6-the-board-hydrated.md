---
needs: [runtime-8]
size: M
check: the board's page filters, opens cards and navigates with no request to the server
priority: P2
---
# The board's page runs in the browser

The board's page (`projects/zaplink/web`, the zaplink page that shows the board) is written with
zapx live (runtime-7): every click is a request to the server. After runtime-8 (hydration) it
should run in the browser, the server only sending a new board when git changes.

- [ ] move the page's areas filter, the card dialog and the times shown to hydrated components;
  filtering and opening a card make no request to the server (the check above, read from the
  server's request log)
- [ ] the server sends a new board only when git changes; a change of a card in git shows in the
  open page
