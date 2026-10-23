# zaplink

The user's coding agents (Claude Code, opencode, Codex, any other terminal program) always run on
this Windows machine; zaplink lets the user open, watch and drive them from Windows or from their
Android phone, the same sessions on both at once. A session opened on the phone starts here and
shows up on Windows; one opened on Windows shows up on the phone. Beside the terminals: the PC's
Edge tabs and a read-only view of the files and diffs the agents are working on.

zaplink depends on no agent's features: no Remote Control, no Claude app, no hooks or accounts of
any vendor. It sees terminals, the browser and folders, so any agent works the same. Written in Zap;
reached only over Tailscale (the daemon listens on the tailnet's address, a token besides), never
the internet.

## The MVP (2026-10-18)

What runs today, in `zaplink/`:

- `zaplinkd.zap`: the daemon. ConPTY sessions (std/win's `startPty`), Windows Terminal's profiles,
  the agent presets and recent dirs of `%LOCALAPPDATA%\zaplink\config.json`, the token of
  `%LOCALAPPDATA%\zaplink\token`; one loop polls the listener, the clients and the sessions
  (std/net's `poll` and `pollFrame`). It listens on 127.0.0.1:7781 by default.
- `zaplink.zap`: a client that runs inside any terminal (Windows Terminal, or an SSH session from
  the phone): a menu of the sessions, a new one by terminal, agent and dir, any one attached in
  raw mode with its screen passed through; Ctrl+] leaves it running. Several clients attached to
  one session see the same output; the one typing last sets the size.
- `tests/hub.zap`: two clients over loopback share a session, a wrong token is refused, a session
  closed ends for both.

The phone reaches it before the native APK through SSH: OpenSSH Server on Windows, the phone on
the tailnet, an SSH app (Termius) to the PC, then `zaplink`. A client that attaches gets a fresh
screen by a resize of the pseudo console, not by `vt`, so a program's modes (mouse, bracketed
paste) are not replayed to a client that attaches later.

## Parts

- `zaplinkd`, the daemon on Windows: owns every session, outlives every client.
- `zaplink`, the native client, one program built for two targets: a window on Windows, an APK on
  Android. No web client.
- `vt`, a terminal emulator in Zap shared by the daemon and both clients.
- A small extension for Microsoft Edge, the PC's default browser, that mirrors its tabs.

Only sessions opened through zaplink are shared; a tab of Windows Terminal stays outside (ConPTY
gives no way to attach to a console another program owns).

## Sessions (the daemon)

- Each session a ConPTY (CreatePseudoConsole, ResizePseudoConsole, the process attribute list,
  CreateProcessW with STARTUPINFOEX) running a profile's command line in a directory.
- The daemon feeds each session's output through `vt`, so it always holds the screen, the
  scrollback and the modes (alternate screen, bracketed paste, cursor keys, title). A client that
  attaches gets that state as a snapshot, then the live output; reconnecting after the phone slept
  costs one snapshot, not a replay.
- Sessions survive clients: closing the window or losing the phone's network detaches, never
  kills. A session ends when its process exits or a client closes it.
- The list (id, profile, agent, directory, title) is kept on disk. After a reboot each session can
  be started again in its directory with its agent's resume command if the preset has one
  (`claude --continue`, `codex resume --last`, `opencode --continue`), else as a fresh shell.
- Started at the user's logon by a scheduled task, not as a service: a service runs in session 0,
  and its shells would lack the user's desktop, profile and credentials.
- Size: the client that typed last sets the columns and rows; the others draw that grid scaled to
  their screen.

## Opening a session

The client asks for three things: the terminal, the agent, the directory.

Terminals come from Windows Terminal's `settings.json`
(`%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState`), reread when it
changes; the profiles Windows Terminal generates (`source`) are resolved to their command lines by
the daemon. Today (2026-10-18):

| Profile | Command line | In zaplink |
|---|---|---|
| Zsh | `C:\Program Files\Git\usr\bin\zsh.exe -l -i`, from the dev dir | yes |
| PowerShell (7) | `C:\Program Files\PowerShell\7\pwsh.exe` | yes, the default |
| Windows PowerShell | `powershell.exe` | yes |
| Prompt de comando | `cmd.exe` | yes |
| Git Bash | `C:\Program Files\Git\bin\bash.exe -l -i` | yes |
| Developer PowerShell / Command Prompt for VS 18 | the VS launch scripts | yes |
| Ubuntu (WSL) | none: no WSL distro installed, only `docker-desktop` | hidden while absent |
| Azure Cloud Shell | a remote connector | no |

The Zsh tab is zsh 5.9 of Git for Windows (`x86_64-pc-cygwin`, over Git's `msys-2.0.dll`), not a
separate MSYS2: there is no `C:\msys64`. It runs under ConPTY as Windows Terminal runs it; the
daemon sets `TERM=xterm-256color` and `COLORTERM=truecolor`, and `MSYS=enable_pcon` if the runtime
needs it.

Agents are presets in the daemon's config, a command typed into the chosen terminal once it
starts, plus its resume command; none is built in beyond that. Installed today: `claude`,
`opencode`, `codex`. "None" opens the bare shell. Adding one is a line of config.

Directories: the recent ones first, then a folder picker over the PC's disks; git worktrees under a
repo are listed with it (the agents work in their own worktrees).

## Agents across devices

- `vt` must draw every agent's interface right: truecolor SGR, box drawing and symbols (Unicode
  beyond ASCII, Portuguese accents, wide characters), synchronized output (mode 2026), bracketed
  paste, the alternate screen (opencode is a full-screen TUI), mouse reporting (opencode's
  clicks and scrolls), frequent redraws of the bottom of the screen.
- Keys the phone lacks, on a row above its keyboard: Esc, Shift+Tab, Ctrl (sticky), Alt, Tab, the
  arrows, Ctrl+C, Ctrl+R, Enter without closing the keyboard; the row is configurable per agent.
- Waiting for the user, with no agent's hooks: the bell, OSC 9 and OSC 777 notifications, a
  change of the window title, and a session that drew output and then went quiet for a few
  seconds; the phone shows an Android notification that opens the session, the Windows client a
  toast and a mark on the tab.
- Paste: text from either device's clipboard; images later (the file copied to the PC, its path
  typed).

## Browser tabs

A program in a session sometimes opens a web page (an agent's login, an OAuth flow, a dev server,
docs), and agents that drive a browser drive the PC's browser, Edge. zaplink mirrors Edge's tabs,
it does not load them again: the user's logins and cookies, `localhost:3000` and an OAuth callback
to `localhost:<port>` show on the phone as they are on the PC, and the user can take over a step an
agent is stuck on (a login, a captcha).

- The zaplink extension (Manifest V3) lists the tabs and follows them (opened, closed, navigated,
  title); for the tab a client watches it attaches `chrome.debugger` and runs the DevTools
  protocol's `Page.startScreencast` (JPEG frames, sized to the client) and `Input.dispatchMouseEvent`,
  `dispatchTouchEvent`, `dispatchKeyEvent` and `insertText` for the client's taps, scrolls and
  keys. It talks to the daemon over a WebSocket on localhost with the daemon's token. It is the one
  part not in Zap, kept as small as it can be. Edge is Chromium, so the API keeps the `chrome.`
  names. `--remote-debugging-port` would mean restarting Edge, and Chromium refuses it on the
  default profile, so an extension is the way in.
- `chrome.debugger` shows Edge's "is debugging this browser" bar while attached; zaplink
  attaches only while a client watches the tab. Several debuggers (another agent's extension
  among them) can share a tab.
- A tab opened while a session's program ran is marked with that session.
- Frames go only to the clients watching, each acked before the next, so the rate follows the
  link. A client can also open a URL or close a tab.

## Files and diffs (read only)

The agents write; the user reads. A viewer of its own, not VS Code for the web: code-server is an
editor with a Node server to run and keep up, and here nothing is ever edited.

- A tree of the session's directory (or any recent one), `.gitignore`d entries dimmed or hidden;
  files shown with line numbers, syntax colors (Zap, C#, TypeScript, Python, Rust, C, JSON, YAML,
  Markdown, shell), search by name and by content (the daemon runs `rg`).
- Git: the status of the working tree, the diff of each changed file against HEAD (unified, side
  by side on a wide screen), the staged part apart, the log with each commit's diff, the branches
  and worktrees, a branch compared with main. The daemon runs `git` (`status --porcelain=v2`,
  `diff`, `log`, `show`) and sends the parsed result.
- Live: the daemon watches the directory, so a file or a diff open in a client updates as the
  agent writes, and a session's tab shows how many files it has changed.
- Read only by construction: the protocol has no message that writes a file or runs a git command
  that changes anything; the daemon serves only paths under the directories it was asked for.
- Images and PDFs shown as such; binaries as their size and type.

## The protocol

One WebSocket per client over std/net (HTTP/1.1, upgrade, frames, the connection split into a
reader and a writer), on the tailnet's address. Tailscale already encrypts; the token says the
client is the user's. Binary messages:

- `hello` (token, client name, screen size); `sessions` and `profiles` (the lists, sent on
  connect).
- `create` (profile, agent, directory, columns, rows) and `close`; `created`, `exited`, `renamed`
  go to every client, which is how a session opened on one device appears on the other at once.
- `attach` / `detach`; `snapshot` (screen, scrollback, modes); `output` (the bytes as ConPTY wrote
  them, the client's own `vt` applying them); `input` (keys, paste, mouse); `resize`.
- `notify` (session, reason, text).
- `browserTabs`, `watch` / `unwatch`, `frame` (JPEG, size, scroll offset), `pointer`, `keys`,
  `openUrl`, `closeTab`.
- `listDir`, `readFile` (a range, for big files), `search`, `gitStatus`, `gitDiff`, `gitLog`,
  `gitShow`, `subscribe` / `changed` for the live updates.

## The client

- Tabs of three kinds, the same on both devices: terminals, browser tabs, file views; a session's
  browser and file tabs grouped under it.
- Drawing through the engine: the grid of cells, the frame view, the file and diff views.
- Input: keys, text and IME on Windows; touch, gestures and the soft keyboard on Android.
- Android: a foreground service keeps the WebSocket while the app is in the background, so the
  notifications arrive without Google's push; it reconnects when the network returns.

## Debugging on the real phone

- `adb` from Google's platform-tools, installed by winget (`Google.PlatformTools`); the phone with
  USB debugging, or wireless debugging (`adb pair`, then `adb connect`) so it can stay unplugged.
- The loop: `zap build --target android` and the APK (zap step 13), `adb install -r`,
  `adb shell am start`, `adb logcat -s zaplink` for the client's log, `adb shell screencap` to see
  what it drew. An agent runs and reads all of it, no manual step.
- The phone reaches the daemon over Tailscale as it will for real; the daemon logs every message
  with ZAP_RUN.
- Checks without the phone: `vt` against recorded output of each agent and shell (Claude Code,
  opencode, Codex, zsh, PowerShell) compared with the screen it must give; the daemon's protocol
  driven by a test client on loopback (sessions, files, diffs, a fake extension); the client's
  drawing compared as images.

## What Zap and the engine still lack

Whatever zaplink needs and the language or the engine lacks is built there, in their repos, as
general parts any program can use, not worked around inside zaplink. Missing today (2026-10-18):

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
