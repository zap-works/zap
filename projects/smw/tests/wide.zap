# The widescreen picture (wide/): the route into Yoshi's Island 1 played at --wide-width 486 (a
# phone's shape), the cartridge's sprite windows widened, the wide picture's hash taken every
# frame. Its native play is Mesen 2's (routes.zap); this baseline moves when the wide composition
# or the widened windows do, and `zap test --update` keeps the new one.
#   needs: projects/recomp/snes/rom/smw.sfc (the player's dump, never committed)

import digest
import fs

test "the route into Yoshi's Island 1 played wide keeps its wide picture":
	expect Process.output("{zapPath()} run projects/smw/prepare.zap").code == 0
	expect Process.output("{zapPath()} build projects/smw/recomp/smw.zap").code == 0
	path = "build/smw-wide-yi1.txt"
	played = Process.output(
		"{builtExe("smw")} --headless --wide --wide-width 486 --frames 5000 --route projects/smw/tests/routes/yi1.txt --wide-hashes {path}"
	)
	expect played.code == 0
	lines = (fs.readFile(path) ?? "").lines()
	expect lines.len == 5000
	for k in 0..20:
		print(lines[k * 250])
	print("drawn wide: {lines.filter(.split(" ")[2] == "1").len} of {lines.len}")
	print("all: {digest.fnv1a(lines.join(" ").bytes()):08x}")
	prints """
		1 2ccf00c5 0 0000000000 1
		251 2ccf00c5 0 0000000000 1
		501 1869ef1c 0 0000000000 1
		751 694cf84f 0 0000000000 2
		1001 694cf84f 0 0000000000 2
		1251 694cf84f 0 0000000000 2
		1501 9eb90685 0 0000000000 1
		1751 da3a2b35 0 0000000028 2
		2001 bb07405a 0 0000000028 2
		2251 cf5fda3d 0 0000000028 2
		2501 7cb51f8e 0 0000000028 2
		2751 3e195cea 0 0000000028 1
		3001 6e171189 0 0000000028 1
		3251 2ccf00c5 0 0000000029 1
		3501 ff881914 1 0000000029 0
		3751 2e75aa91 1 0000000029 0
		4001 2ccf00c5 0 0000000029 1
		4251 d3297d21 1 0000000029 0
		4501 2ccf00c5 0 0000000729 1
		4751 2ccf00c5 0 0000000029 1
		drawn wide: 1036 of 5000
		all: 833878a0
		"""
