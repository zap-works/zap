---
size: S
check: zaplinkd started prints the phone's link with its token; the Controls screen shows it as a QR code on this PC only
branch: phone2
by: 704a3f6e-3fab-463a-9569-01d68ba36a46
---
# The phone's link, by itself

- [ ] At start the daemon runs `tailscale serve --bg --yes <port>` (Serve must be enabled once in
  the tailnet's admin) and prints `https://<machine>.ts.net/?token=<token>`.
- [ ] Controls shows that link as a QR code (drawn in the browser), only to a request of this
  machine, so the token never reaches another device's page.
