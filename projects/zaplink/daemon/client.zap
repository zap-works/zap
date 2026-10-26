# The command line's side of the daemon: an order posted to it, or a page of it read, over HTTP on
# the address of the daemon's config.

import net

# the daemon's answer to a request: its body, or why there is none
pub fn askDaemon(config Config, method str, path str, body str) str ? net.Error:
	conn = try net.tcpConnect(config.host, config.port)
	conn.queueRequest(method, path, "{config.host}:{config.port}", body.bytes())
	try conn.flush()
	answer = try conn.nextResponse()
	str(answer.body)
