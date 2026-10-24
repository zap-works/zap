# lm, the log manager (switchbrew: Log services): a process opens a logger and sends it packets,
# which the kernel's log shows. A packet is a header (process id, thread id, flags with head and
# tail bits, severity, verbosity, payload size) and the payload's chunks: a key, a length and the
# bytes. Key 2 is the message's text; a message may span several packets.

packetHeaderSize = 24
keyMessage = 2
flagTail = 2

fn logManager(mut k Kernel, i i64, req Request, mut res Response):
	match req.command:
		0: k.offer(res, "ILogger")
		_: k.unwritten(i, req)

# the text in a packet's chunks, and whether its message ends with it
fn packetText(packet u8[]):
	if packet.len < packetHeaderSize: return ("", true)
	text = []
	at = packetHeaderSize
	while at + 2 <= packet.len:
		key = i64(packet[at])
		n = i64(packet[at + 1])
		if key == keyMessage: text.extend(packet[at + 2..(at + 2 + n).min(len)])
		at += 2 + n
	(text.text().copy(), i64(packet[16]) & flagTail != 0)

fn logger(mut k Kernel, i i64, req Request, mut res Response):
	match req.command:
		0:
			text, last = packetText(req.sent(0))
			k.services[i].path = "{k.services[i].path}{text}"
			if last:
				k.log.push("lm: {k.services[i].path}")
				k.services[i].path = ""
		1: pass
		_: k.unwritten(i, req)
