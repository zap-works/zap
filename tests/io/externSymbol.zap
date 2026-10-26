# An extern named after its library may be found by another symbol than its own name, beside a
# declaration of that symbol itself.
# host: windows

extern "kernel32.dll" "GetTickCount64" fn ticks() i64
extern "kernel32.dll" fn GetTickCount64() i64

test "an extern found by a symbol of its own beside the symbol's own declaration":
	expect ticks() > 0
	expect GetTickCount64() > 0
