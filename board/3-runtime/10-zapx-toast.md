---
size: S
check: a page shows a toast from zapx.ui after an action, dismissed by itself, on the phone too
priority: P2
---
# zapx.ui has a toast

`std/zapx/ui` (`ui.zapx`) has the components except a toast, which needs a script in the page. A
toast is a short message that appears after an action and goes away on its own. zaplink's page
(`projects/zaplink`) should show one when an order, a setting or a new agent is sent.

- [ ] add a `Toaster` component to `std/zapx/ui/ui.zapx`, placed once in a page, and a call that
  shows a message for a few seconds (Sonner's look: bottom right, stacked, a title and a
  description); a test page under `std/zapx` shows a toast after a click and it disappears by
  itself, also at a phone's width
- [ ] call it from zaplink's page when an order, a setting or a new agent is sent
  (`projects/zaplink`); the page shows the toast after each of the three actions
