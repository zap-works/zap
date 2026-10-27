# A game stopped in Eden (the oracle) where its code reaches an address, the registers and memory
# there printed, to set beside this recompiler's at the same place. Eden runs headless with its
# gdb stub on (its eden-cli and configuration where --eden says, the user's own, outside the
# repository), the game the user's own NSP. Run from the repository root:
#
#   zap run projects/recomp/switch/tools/edenStop.zap --eden <dir of eden-cli> --game <nsp>
#       --at <hex> [--hit n] [--trace <hex>,...] [--memory <hex>,<n>[;<hex>,<n>...]] [--monitor <command>] [--watch <hex>] [--after ms]
#
# stops at the n-th time (1 by default) the code reaches --at, prints the registers and each
# --memory range, and ends Eden. --trace prints the stop, the registers and the --memory ranges at each of its addresses
# on the way; put them on the instruction after a supervisor call, never on the call (the stub steps
# off a breakpoint, and a stepped svc breaks the game). --watch <hex> stops, prints and goes on at
# each write to the 4 bytes there.

import fs
import recomp.switch.oracle

fn printMemory(mut r oracle.Remote):
	for range in (args.option("--memory") ?? "").split(";").filter(not .isEmpty):
		parts = range.split(",")
		start = i64.parse("0x{parts.first ?? ""}") ?? fail("--memory <hex>,<n>")
		n = i64.parse(parts.last ?? "") ?? fail("--memory <hex>,<n>")
		bytes = r.memory(start, n) ?? fail(error.why)
		print("{start:x}: {bytes.map("{it:02x}").join("")}")

edenDir = args.option("--eden") ?? fail("--eden <dir of eden-cli>")
game = args.option("--game") ?? fail("--game <nsp>")
at = i64.parse("0x{args.option("--at") ?? ""}") ?? fail("--at <hex address>")
hits = i64.parse(args.option("--hit") ?? "1") ?? fail("--hit <count>")
port = 6543
traced = (args.option("--trace") ?? "")
	.split(",")
	.filter(not .isEmpty)
	.map(i64.parse("0x{it}") ?? fail("--trace <hex>,..."))

config = fs.join(edenDir, "user/config/sdl2-config.ini")
oracle.setGdbStub(config, port) ?? fail(error.why)
env["SDL_VIDEODRIVER"] = "offscreen"   # no window
Process.start("{quoteArg(fs.join(edenDir, "eden-cli.exe"))} {quoteArg(game)}")
r = oracle.remoteWithin("127.0.0.1", port, 60_000) ?? fail(error.why)
sleepMs(i64.parse(args.option("--after") ?? "3000") ?? 3000)   # the game's process started first
paused = r.pause() ?? fail(error.why)
eprint("paused: {paused}")
first = r.registers() ?? fail(error.why)
eprint("pc at the pause {first[32]:x}, sp {first[31]:x}")
r.breakAt(at) ?? fail(error.why)
eprint("breakpoint at {at:x} set")
for extra in traced:
	r.breakAt(extra) ?? fail(error.why)
watched = i64.parse("0x{args.option("--watch") ?? "0"}") ?? fail("--watch <hex address>")
if watched != 0:
	r.watchWrites(watched, 4) ?? fail(error.why)
stops = [at]
stops.extend(traced)
reached = 0
loop:
	stop = r.resumeTo(stops) ?? fail(error.why)
	if not stop.startsWith("T"): fail("Eden stopped otherwise: {stop}")
	if "watch" in stop:
		print(
			"watch: pc {oracle.stopPc(stop) ?? 0:x} lr {(r.registers() ?? fail(error.why))[30]:x}"
		)
		r.stepPastWatch(watched, 4) ?? fail(error.why)
		continue
	if (oracle.stopPc(stop) ?? 0) != u64(at):
		print("{stop} {(r.registers() ?? fail(error.why)).map("{it:x}").join(" ")}")
		r.printMemory()
		continue
	reached += 1
	if reached == hits: break
regs = r.registers() ?? fail(error.why)
for k, v in regs:
	name = "x{k}" if k < 31 else ["sp", "pc"][k - 31]
	print("{name} {v:016x}")
r.printMemory()
if args.option("--monitor") is command:
	print(r.monitor(command) ?? fail(error.why))   # Eden's own at the stop: get info, get mappings
r.kill()   # Eden ends with the game
