---
priority: P1
size: XL
---
# Requests from the user for zaplink

A standing card: the agent on it takes the user's requests for zaplink (projects/zaplink and
std/zapx's ui) as they come in its chat, each one a checklist item here, done in commits on this
branch. It never restarts zaplinkd (the user does, from Controls, once a change lands) and never
lands (the daemon does); it keeps the card open when the list is empty, waiting for the next.

- [ ] (the user's requests go here)
