# std/win's piped programs: stdout read as it comes, stdin written, a running one stopped.

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
