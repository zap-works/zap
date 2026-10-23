# zaplinkd: the daemon that owns the terminal sessions on this machine, shared by every zaplink
# client (README.md). It listens on the address and port of its config
# (%LOCALAPPDATA%/zaplink/config.json) and admits the clients that give its token
# (%LOCALAPPDATA%/zaplink/token).
#
#   zap build projects/zaplink/zaplinkd.zap && build/zaplinkd.exe

import server

mut hub = server.startHub()
listener = hub.listen() ??
	exit(1, "zaplinkd: cannot listen on {hub.config.host}:{hub.config.port}: {error}")
print("zaplinkd on {hub.config.host}:{hub.config.port}, {hub.profiles.len} terminals, {hub.config.agents.len} agents")
hub.serve(listener, Atomic(1))
