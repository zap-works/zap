---
needs: [zaplink-5]
size: XL
blocked: after the agents; the extension, the JPEG decoder and the frame view
priority: P3
---
# The PC's browser tabs are mirrored to the phone

The user's Edge tabs on the PC are to be seen and used from the phone through zaplink's page. It
waits until the agents part is finished, and needs three pieces.

- [ ] a browser extension (Edge) that captures the active tab's frames and sends them to the
  daemon, and receives clicks and keys to replay in the tab
- [ ] a JPEG decoder in Zap (`std/image`), so the page's client (JS only where a browser needs it)
  or the daemon can show the frames
- [ ] the frame view in the page (`projects/zaplink/web`): the phone shows the tab's picture and
  sends taps back; a tab opened on the PC shows on the phone within a second
