# Each test homebrew (tests/homebrew/<name>.c, built by tools/homebrew.zap) run interpreted on the
# HLE kernel prints what Eden printed running it (tools/eden.zap wrote <name>.txt).
#   needs: projects/recomp/switch/rom/homebrew/hello.nro (built from tests/homebrew/hello.c)

import fs
import recomp.switch.horizon

# what the homebrew printed, then how its run ended
fn printed(name str):
	k = horizon.launchNro("projects/recomp/switch/rom/homebrew/{name}.nro", 0x1000_0000) ??
		return error
	why = k.runProcess(200_000_000)
	"{k.log.join("\n")}\n-- {why}"

test "hello prints what it printed on Eden":
	expected = fs.readFile("projects/recomp/switch/tests/homebrew/hello.txt") ?? ""
	expect printed("hello") == "{expected}-- exited"
