# An executable run interpreted on the HLE kernel, what it prints shown as it goes. Run from the
# repository root:
#
#   zap run projects/recomp/switch/tools/run.zap <homebrew.nro | exefs dir> [--steps n] [--calls] [--profile file] [--record-shaders dir]
#
# --calls notes each supervisor call and IPC request; --profile writes the address of every block
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
k.gpu.recordDir = args.option("--record-shaders") ?? ""
profile = args.option("--profile") ?? ""
cpu.recording = profile != ""
why = k.runProcess(steps)
for line in k.log:
	print(line)
print("-- {why}")
for line in k.gpuReport():
	print(line)
if profile != "":
	blocks = cpu.entered.keys().sorted().map("{it:x}").join("\n")
	fs.writeFile(profile, "{blocks}\n") ?? fail("cannot write {profile}: {error}")
	print("{cpu.entered.len} blocks into {profile}")
