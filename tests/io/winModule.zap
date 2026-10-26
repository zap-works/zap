# std/win: system functions, GUIDs, HRESULTs and COM's basics.

import win

extern loaded fn tickCount() i64

test "a function loaded by name, a GUID's bytes, an HRESULT's text":
	at = win.loadFunction("kernel32.dll", "GetTickCount64")
	bindExtern(tickCount, at)
	expect at != 0
	expect tickCount() > 0
	expect win.guid("189819f1-1db6-4b57-be54-1821339b85f7") ==
		[241, 25, 152, 24, 182, 29, 87, 75, 190, 84, 24, 33, 51, 155, 133, 247]
	expect win.hresultText == {-i32(2_005_270_523): "0x887a0005", 1: "0x00000001"}

test "an event made and closed":
	e = win.CreateEventA(0, true, false, 0)
	print("{e != 0} {win.WaitForSingleObject(e, 0)}")
	win.CloseHandle(e)
	prints "true 258"

test "random bytes from the system":
	a = win.secureRandom(32)
	b = win.secureRandom(32)
	expect a.len == 32
	expect a != b
