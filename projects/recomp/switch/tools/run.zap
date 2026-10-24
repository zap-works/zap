# An executable run interpreted on the HLE kernel, what it prints shown as it goes. Run from the
# repository root:
#
#   zap run projects/recomp/switch/tools/run.zap <homebrew.nro | exefs dir> [--steps n] [--calls] [--profile file] [--record-shaders dir]
#
# --at <hex> [--hit n] stops at the n-th time code reaches the address and prints the thread's
# registers and the --memory <hex>,<n>[;...] ranges as tools/edenstop.zap prints Eden's;
# --modules prints where each module lies; --calls notes each supervisor call and IPC request; --profile writes the address of every block
# that ran, a line each, for main.zap's --profile. --record-shaders writes each program the draws
# use, once, into a dir (tools/shaders.zap translates it).

import fs
import recomp.switch.cpu
import recomp.switch.horizon

path = args.positional().first ??
	fail("usage: zap run projects/recomp/switch/tools/run.zap <nro | exefs dir> [--steps n]")
steps = i64.parse(args.option("--steps") ?? "100000000") ?? 100_000_000
k = horizon.launch(path) ?? fail
k.traceCalls = "--calls" in args
if "--modules" in args:
	for m in k.modules:
		print("{m.name} {m.at:x}-{m.at + m.size:x}")
k.gpu.recordDir = args.option("--record-shaders") ?? ""
profile = args.option("--profile") ?? ""
cpu.recording = profile != ""
if args.option("--at") is at:
	cpu.breakAt = i64.parse("0x{at}") ?? fail("--at <hex address>")
	cpu.breakHit = i64.parse(args.option("--hit") ?? "1") ?? fail("--hit <count>")
why = k.runProcess(steps)
if (why.indexOf(": breakpoint") ?? -1) >= 0:
	stopped = k.threads.find(.c.pc == cpu.breakAt) ?? fail("no thread at the breakpoint")
	printStop(stopped.c, args.option("--memory") ?? "")
for line in k.log:
	print(line)
print("-- {why}")
for line in k.gpuReport():
	print(line)
if profile != "":
	blocks = cpu.entered.keys().sorted().map("{it:x}").join("\n")
	fs.writeFile(profile, "{blocks}\n") ?? fail("cannot write {profile}: {error}")
	print("{cpu.entered.len} blocks into {profile}")

# the registers of a thread stopped at --at, and the --memory ranges, as tools/edenstop.zap prints
# Eden's: a line each, to set one beside the other
fn printStop(c cpu.Cpu, ranges str):
	for k in 0..33:
		name = "x{k}" if k < 31 else ["sp", "pc"][k - 31]
		value = u64(c.pc) if k == 32 else c.x[32] if k == 31 else c.x[k]   # (sp is x[32])
		print("{name} {value:016x}")
	for range in ranges.split(";").filter(not .isEmpty):
		parts = range.split(",")
		start = i64.parse("0x{parts.first ?? ""}") ?? fail("--memory <hex>,<n>")
		n = i64.parse(parts.last ?? "") ?? fail("--memory <hex>,<n>")
		print("{start:x}: {cpu.memory.read(start, n).map("{it:02x}").join("")}")
