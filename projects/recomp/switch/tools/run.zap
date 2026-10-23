# An executable run interpreted on the HLE kernel, what it prints shown as it goes. Run from the
# repository root:
#
#   zap run projects/recomp/switch/tools/run.zap <homebrew.nro> [--steps n]

import recomp.switch.horizon

path = args.positional().first ??
	fail("usage: zap run projects/recomp/switch/tools/run.zap <nro> [--steps n]")
steps = i64.parse(args.option("--steps") ?? "100000000") ?? 100_000_000
k = horizon.launchNro(path, 0x1000_0000) ?? fail
why = k.runProcess(steps)
for line in k.log:
	print(line)
print("-- {why}")
