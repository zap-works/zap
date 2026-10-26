---
needs: [compiler-23, runtime-7]
size: L
check: a page rendered natively and hydrated by the same .zapx under the JS target, its events and navigation without the server
priority: P1
---
# zapx hydration, as Next does

The same `.zapx` components run on both sides: the server renders the HTML with the page's state
written into it (`toBytes()`, base64), the browser loads the module the JS target built from the
same file, reads the state (`fromBytes()`), runs the same view over the DOM already there without
drawing it again (hydration) and binds its events; from then on navigation, filters and dialogs
happen in the browser, and data is fetched as typed values.

- [ ] Events as Zap closures in markup (`onClick={...}`), state changes rerendering through the
  same diff as zapx live.
- [ ] A router: routes to views, links handled in the browser, the server rendering any route
  first.
- [ ] `zap build` making both halves of a page from one entry.
