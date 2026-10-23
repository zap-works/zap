# An executable run interpreted on the HLE kernel, what it prints shown as it goes. Run from the
# repository root:
#
#   zap run projects/recomp/switch/tools/run.zap <homebrew.nro | exefs dir> [--steps n] [--calls] [--profile file]
#
# --calls notes each supervisor call and IPC request; --profile writes the address of every block
# that ran, a line each, for main.zap's --profile.

import fs
import recomp.switch.cpu
import recomp.switch.horizon

path = args.positional().first ??
	fail("usage: zap run projects/recomp/switch/tools/run.zap <nro | exefs dir> [--steps n]")
steps = i64.parse(args.option("--steps") ?? "100000000") ?? 100_000_000
k = horizon.launch(path) ?? fail
k.traceCalls = "--calls" in args
profile = args.option("--profile") ?? ""
cpu.recording = profile != ""
why = k.runProcess(steps)
for line in k.log:
	print(line)
print("-- {why}")
if not k.gpu.channels.isEmpty:
	st = k.gpu.stats
	print("gpu: {k.display.presented} frames, {st.draws} draws, {st.macroCalls} macro calls, {st.dispatches} dispatches, {st.copies} copies, {st.inlineUploads} uploads, {st.semaphores} semaphores, {st.syncpointIncrements} syncpoint increments")
	for note in k.gpu.notes:
		print("gpu note: {note}")
if profile != "":
	blocks = cpu.entered.keys().sorted().map("{it:x}").join("\n")
	fs.writeFile(profile, "{blocks}\n") ?? fail("cannot write {profile}: {error}")
	print("{cpu.entered.len} blocks into {profile}")
