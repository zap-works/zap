# zaplink

Agents and terminals from any browser, phone or PC.

zaplinkd, the daemon on this PC, runs the coding agents (Claude Code without a window, over
stream-json), schedules them from the board's queue under one limit for the whole machine, keeps
goals and loops going, and serves one web app (zapx) that does on the phone what it does on the PC:
start and stop agents, read each one's every step, give it orders. Reached over Tailscale, whose
tailnet is the user's alone. The native clients and `vt` are gone: the web app is the client.
