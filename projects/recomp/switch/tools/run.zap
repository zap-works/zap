# An executable run interpreted on the HLE kernel, what it prints shown as it goes. Run from the
# repository root:
#
#   zap run projects/recomp/switch/tools/run.zap <homebrew.nro | exefs dir> [--steps n] [--calls]
#
# --calls notes each supervisor call and IPC request.

import recomp.switch.horizon

path = args.positional().first ??
	fail("usage: zap run projects/recomp/switch/tools/run.zap <nro | exefs dir> [--steps n]")
steps = i64.parse(args.option("--steps") ?? "100000000") ?? 100_000_000
# BotW's heap: what the application's memory pool gives it (3.2 GB), and its program id
k = (
	horizon.launchNro(path, 0x1000_0000) if path.endsWith(".nro")
	else horizon.launchExefs(path, 0xC800_0000, 0x0100_7EF0_0011_E000)
) ??
	fail
k.traceCalls = "--calls" in args
why = k.runProcess(steps)
for line in k.log:
	print(line)
print("-- {why}")
