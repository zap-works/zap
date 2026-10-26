---
needs: [runtime-8]
size: M
check: the board's page filters, opens cards and navigates with no request to the server
---
# The board as a hydrated page

tools/board's page moves from zapx live (runtime-7) to hydration (runtime-8): the areas' filter,
the card's dialog and the times shown run in the browser; the server only sends a new board when
git changes.
