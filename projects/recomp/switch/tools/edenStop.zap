# A game stopped in Eden (the oracle) where its code reaches an address, the registers and memory
# there printed, to set beside this recompiler's at the same place. Eden runs headless with its
# gdb stub on (its eden-cli and configuration where --eden says, the user's own, outside the
# repository), the game the user's own NSP. Run from the repository root:
#
#   zap run projects/recomp/switch/tools/edenStop.zap --eden <dir of eden-cli> --game <nsp>
#       --at <hex> [--hit n] [--memory <hex>,<n>[;<hex>,<n>...]] [--info] [--after ms]
#
# stops at the n-th time (1 by default) the code reaches --at, prints the registers and each
# --memory range, and ends Eden.

import fs
import recomp.switch.oracle

edenDir = args.option("--eden") ?? fail("--eden <dir of eden-cli>")
game = args.option("--game") ?? fail("--game <nsp>")
at = i64.parse("0x{args.option("--at") ?? ""}") ?? fail("--at <hex address>")
hits = i64.parse(args.option("--hit") ?? "1") ?? fail("--hit <count>")
port = 6543

config = fs.join(edenDir, "user/config/sdl2-config.ini")
oracle.setGdbStub(config, port) ?? fail(error.why)
env["SDL_VIDEODRIVER"] = "offscreen"   # no window
Process.start("{quoteArg(fs.join(edenDir, "eden-cli.exe"))} {quoteArg(game)}")
r = oracle.remoteWithin("127.0.0.1", port, 60_000) ?? fail(error.why)
if "--info" in args:
	print(r.monitor("get info") ?? fail(error.why))
sleepMs(i64.parse(args.option("--after") ?? "3000") ?? 3000)   # the game's process started first
paused = r.pause() ?? fail(error.why)
eprint("paused: {paused}")
first = r.registers() ?? fail(error.why)
eprint("pc at the pause {first[32]:x}, sp {first[31]:x}")
r.breakAt(at) ?? fail(error.why)
eprint("breakpoint at {at:x} set")
loop hits:
	stop = r.resumeTo(at) ?? fail(error.why)
	if not stop.startsWith("T"): fail("Eden stopped otherwise: {stop}")
regs = r.registers() ?? fail(error.why)
for k, v in regs:
	name = "x{k}" if k < 31 else ["sp", "pc"][k - 31]
	print("{name} {v:016x}")
for range in (args.option("--memory") ?? "").split(";").filter(not .isEmpty):
	parts = range.split(",")
	start = i64.parse("0x{parts.first ?? ""}") ?? fail("--memory <hex>,<n>")
	n = i64.parse(parts.last ?? "") ?? fail("--memory <hex>,<n>")
	bytes = r.memory(start, n) ?? fail(error.why)
	print("{start:x}: {bytes.map("{it:02x}").join("")}")
r.kill()   # Eden ends with the game
