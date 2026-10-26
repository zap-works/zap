---
size: L
check: a test of std/zapx: two renders give the patch that turns one DOM into the other
branch: zapxlive
by: 704a3f6e-3fab-463a-9569-01d68ba36a46
---
# zapx live: server state, patches over a socket

The LiveView way, for pages whose state stays on the server: a `.zapx` view renders the page
(SSR); a small client of std/zapx keeps a WebSocket open, sends clicks (`event="name:value"`),
same-origin links (navigation without a reload, `history.pushState`) and key presses; the server
updates its state, renders again, diffs the new tree against the last one (keyed children by a
`key` attribute, React's reconciliation) and sends only the patches, which the client applies.

- [ ] std/zapx's diff: two Node trees to a list of patches (text, attributes, children by key or
  index), fragments flattened and adjacent texts merged as the browser's DOM holds them.
- [ ] A session over std/net's WebSocket: events in, patches out, a render pushed when the server's
  own state changes (a timer, a file).
- [ ] The client: a short script std/zapx serves (written by hand until the JS target writes it
  from Zap).
- [ ] The board's page on it (tooling-6 then moves it to hydration).
