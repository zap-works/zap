# zaplinkhost: one agent's host (agents/host.zap), started detached by the daemon; a program of its
# own so that the command line, zaplink, is never held by a running host.
#
#   zap run projects/zaplink/zaplinkhost.zap <agent id>

import agents
import daemon
import fs

if args.len != 1: exit(2, "usage: zaplinkhost <agent id>")
agents.runHost(fs.join(daemon.stateDir(), "agents"), args[0])
