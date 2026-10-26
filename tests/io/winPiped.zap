# std/win's piped programs: stdout read as it comes, stdin written, a running one stopped.

import net
import win

test "a program's stdout is read as it comes and its stdin written":
	p = win.startPiped("sort", currentDir()) ?? fail
	expect p.write("pear\r\napple\r\n".bytes())
	p.closeInput()
	got u8[] = []
	loop:
		ended = p.hasEnded()
		got.extend(p.read())
		if ended: break
		sleepMs(5)
	print(str(got).replace("\r\n", "|"))
	prints "apple|pear|"

test "closing a running program stops it":
	p = win.startPiped("ping -n 30 127.0.0.1", currentDir()) ?? fail
	sleepMs(100)
	expect not p.hasEnded()
	p.close()
	print(p.code)
	prints "1"

test "the machine's processors and memory are read":
	before = win.cpuTimes()
	sleepMs(50)
	share = win.cpuTimes().busySince(before)
	memory = win.memoryUse()
	print(share >= 0.0 and share <= 1.0 and memory.total > memory.free and memory.free > 0)
	prints "true"

test "a piped program inherits its pipes and not this program's sockets":
	listener = net.tcpListen(0) ?? fail
	port = listener.port()
	p = win.startPiped("ping -n 30 127.0.0.1", currentDir()) ?? fail
	listener.close()
	match net.tcpListen(port):
		again: print("free")
		error: print("held: {error}")
	p.close()
	prints "free"
