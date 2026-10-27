# A profile written adds to the file's: the runs of a partition's build accumulate.

import fs
import recomp.switch.cpu

test "a profile written keeps the blocks the file already held":
	path = "{testDir()}profile.txt"
	fs.writeFile(path, "1000\n2000\n") ?? fail
	cpu.entered[0x3000] = true
	cpu.entered[0x1000] = true
	_ = cpu.writeProfile(path)
	expect (fs.readFile(path) ?? "") == "1000\n2000\n3000\n"
