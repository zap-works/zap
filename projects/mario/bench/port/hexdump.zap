# hexdump -v -e '1/1 "0x%X,"' [file]: each byte of the file (or of stdin) as 0x%X, with no
# separator or newline, the only form the sm64ex build uses. Built and copied into the build's
# shim dir as hexdump.exe (see README.md):
#   zap build projects/mario/bench/port/hexdump.zap

import fs

mut path = ""
for a in args:
	if a != "-v" and a != "-e" and not a.startsWith("1/1") and fs.exists(a):
		path = a.copy()
input = stdin.all() if path == "" else fs.readFile(path) ?? fail("hexdump: cannot read {path}")
digits = "0123456789ABCDEF"
mut out u8[] = []
out.reserve(input.len * 5)
for b in input.bytes():
	out.push('0')
	out.push('x')
	if b >= 16:
		out.push(digits[b >> 4])
	out.push(digits[b & 15])
	out.push(',')
stdout.writeBytes(out)
