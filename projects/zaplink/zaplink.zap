# zaplink: the client of zaplinkd in a terminal (README.md). It lists the sessions on this PC,
# opens new ones (terminal, agent, dir) and attaches to any of them, shared with every other
# client attached; Ctrl+] leaves a session running. The token is read from
# %LOCALAPPDATA%/zaplink/token unless given.
#
#   zap build projects/zaplink/zaplink.zap && build/zaplink.exe [--host 127.0.0.1] [--port 7781] [--token t]

import client
import fs
import link
import win

host = args.option("--host") ?? "127.0.0.1"
port = i64.parse(args.option("--port") ?? "") ?? link.defaultPort
kept = fs.readFile(link.tokenPath()) ?? ""
token = args.option("--token") ?? kept.trimmed()
mut app = client.connect(host, port, token) ?? exit(1, "zaplink: {error}")
was = win.rawConsole()
keys = Channel<u8[]>()
background((): client.readKeys(keys))
app.run(keys)
client.resetTerminal()
client.clearScreen()
was.restore()
exit(0)
