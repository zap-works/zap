---
needs: [compiler-23, runtime-7]
size: L
check: a page rendered natively and hydrated by the same .zapx under the JS target, its events and navigation without the server
priority: P2
---
# A zapx page rendered by the server is taken over by the browser

Next.js calls this hydration. The same `.zapx` components run on both sides: the server renders
the HTML with the page's state written into it (`toBytes()`, base64); the browser loads the module
the JS target built from the same file, reads the state (`fromBytes()`), runs the same view over the
DOM already there without drawing it again, and binds its events. From then on navigation, filters
and dialogs happen in the browser, and data is fetched as typed values. The code is in `std/zapx`.

- [ ] events as Zap closures in markup (`onClick={...}`), state changes rerendering through the
  same diff as zapx live (`std/zapx/diff.zap`); a test page changes its own text by a click with no
  server request
- [ ] a router: routes map to views, links are handled in the browser, and the server renders any
  route first; opening a route's URL directly and clicking to it show the same page
- [ ] `zap build` makes both halves of a page (the native server and the JS module) from one
  entry; the check above passes
