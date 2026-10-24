# Writes guest memory as the loader lays the modules out: n bytes from a hex address into a file,
# for an outside disassembler. Run from the repository root:
#
#   zap run projects/recomp/switch/tools/dump.zap <exefs dir> <hex address> <n> <out file>

import fs
import recomp.switch.cpu.core
import recomp.switch.horizon

given = args.positional()
if given.len < 4: fail("usage: dump.zap <exefs dir> <hex address> <n> <out file>")
_ = horizon.loadCode(given[0]) ?? fail
at = i64.parse("0x{given[1]}") ?? fail("{given[1]} is no hex address")
n = i64.parse(given[2]) ?? fail("{given[2]} is no count")
bytes = []
for k in 0..n:
	bytes.push(u8(core.memory.load(at + k, 0)))
fs.writeBytes(given[3], bytes) ?? fail("cannot write {given[3]}: {error}")
print("{n} bytes from {at:x} into {given[3]}")
