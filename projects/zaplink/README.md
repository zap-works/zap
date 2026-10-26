# zaplink

The daemon on this PC that runs the coding agents and the plan's board, and its web app, the same
on the phone and the PC. What is left is board/14-zaplink.

## What runs

- `zaplinkd.zap`: the daemon. It serves the board's page at the address and port of its config
  (`%LOCALAPPDATA%\zaplink\config.json`, 127.0.0.1:7781 by default): a job answers the browser
  from the page last made while the daemon reads git again every 1.5 s; `/version` tells the page
  when to fetch `/board`; the areas' filter, the card's dialog and the times run in the browser.
- `zaplink.zap`: the command line. `board check`, `board next`, `board take <id>... [--branch b]
  [--by session]` (the agent's Claude Code session by default, so the page names it).
- `cards/`: the board read from git (board/README.md): main's checkout holds the open cards, a
  branch's worktree the ones it took, main's history the landed ones; the Claude Code sessions
  running here from `~/.claude/sessions` (name, busy or idle).
- `agents/`: the fleet. Each agent runs in a host of its own (`zaplinkhost.zap <id>`, started
  detached), which owns its Claude Code, logs its stream and reads its inbox: the daemon only reads
  and writes those files, so a restart (Controls, Restart daemon) stops no agent and the new daemon
  goes on reading where the old one was.
- `web/`: the page, in zapx. `pwa.zap` makes it installable on a phone (manifest, icon and service worker, served
  without the token) and notices an agent that ends a turn or stops, once the viewer turns notices
  on in Controls (shown while the page is open or in the background, not by a push from the daemon).
- `daemon/`: the config, the token and the web server.

    zap run projects/zaplink/zaplinkd.zap
    zap run projects/zaplink/zaplink.zap board next
