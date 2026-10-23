# Each test homebrew (tests/homebrew/<name>.c, built by tools/homebrew.zap) prints what Eden
# printed running it (tools/eden.zap wrote <name>.txt): run interpreted on the HLE kernel, and
# translated by main.zap into a program that is built and run.
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

# what hello translated by main.zap with those options prints, built as `name`
fn translated(name str, options str):
	out = "projects/recomp/switch/out/tests/{name}"
	made = Process.output("{zapPath()} run projects/recomp/switch/main.zap projects/recomp/switch/rom/homebrew/hello.nro --out {out} --name {name} --build {options}")
	if made.code != 0: return made.out
	Process.output("{builtExe(name)} --frames 100000").out.replace("\r\n", "\n")

test "hello translated prints what it printed on Eden":
	expected = fs.readFile("projects/recomp/switch/tests/homebrew/hello.txt") ?? ""
	expect translated("hello", "") == "{expected}-- exited\n"

test "hello translated as parts loaded at its start prints the same":
	expected = fs.readFile("projects/recomp/switch/tests/homebrew/hello.txt") ?? ""
	expect translated("helloparts", "--part 3000") == "{expected}-- exited\n"
