# zaplinkd: the daemon on this PC (README.md). It serves the web app at the address and port of its
# config (%LOCALAPPDATA%/zaplink/config.json): the board of the repository it was first started in.
#
#   zap run projects/zaplink/zaplinkd.zap

import daemon

config = daemon.loadConfig()
daemon.serve(config.repo, config.host, config.port)
