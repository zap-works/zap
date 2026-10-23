# TODO: zaplink

## Order


1. In zap: std/net's server parts (done), ConPTY and processes in std/win, std/unicode.
2. `vt` with its recorded-output checks; in the engine, text on demand, text input, the cell grid.
3. `zaplinkd`: profiles, agent presets, sessions, snapshot, notifications, protocol, logon task;
   tested by a client on loopback.
4. The Windows client: terminals and tabs.
5. Files and diffs: the daemon's side, the text view and the tree, on Windows.
6. The Android client once Zap builds for the phone (zap step 13): soft keyboard,
   foreground service, notifications; debugged on the user's phone over adb.
7. Browser tabs: the extension, the JPEG decoder, the frame view, on Windows then on the phone.
8. Sessions started again after a reboot.

## What Zap and the engine still lack


Whatever zaplink needs and the language or the engine lacks is built there, in their repos, as
general parts any program can use, not worked around inside zaplink. Missing:

zap (std and runtime):

- std/net: only raw TCP. HTTP/1.1, the WebSocket upgrade and frames, the reader/writer split
  across jobs and listening on a given address came with httpjson (done).
- std/win: only libraries, events, handles and COM. Adds ConPTY and processes (STARTUPINFOEX, the
  attribute list, pipes, waiting on exit, a child's environment and its captured output for `git`
  and `rg`), the clipboard, directory watches (ReadDirectoryChangesW), toasts, the scheduled task
  at logon.
- std/unicode: UTF-8 decoding and the cell width of a code point (East Asian Wide, combining
  marks), for `vt`, the glyph cache and the file views.
- std/image: a JPEG decoder (baseline and progressive) beside png, fast enough for a screencast on
  the phone.
- The Android side (done on Linux; step 13 left): sockets, threads and files over Linux system calls, floats
  and NEON, the APK; and JNI for what a NativeActivity cannot do alone (the soft keyboard,
  notifications, the foreground service, the clipboard).

The engine:

- Text: glyphs drawn on demand into a growing atlas, any code point, wide cells, bold and italic,
  fallback faces; a .ttf read by the engine itself on Android, where GDI does not exist.
- Input: text and IME (WM_CHAR, WM_IME_COMPOSITION) on Windows; touch, gestures and the soft
  keyboard on Android.
- The window and drawing on Android (a NativeActivity's surface and Vulkan, step 13's "later").
- Widgets: a grid of cells drawn in one pass, a scrolling text view with colored spans (files,
  diffs), a tree, tabs, a frame view (JPEG frames scaled, taps mapped back, pinch to zoom).
