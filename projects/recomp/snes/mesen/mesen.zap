# Mesen 2 (GPL-3, `winget install SourMesen.Mesen2`) run headless over tools/oracle.lua: the
# original played from power-on for a number of frames, with a route's buttons or none, writing
# what the mode says (the hashes of every frame, where the jumps through memory went...). Needs
# Mesen's settings to allow the script I/O (C:/Users/<you>/Documents/Mesen2/settings.json:
# Debug.ScriptWindow.AllowIoOsAccess, and Preferences.DisableFrameSkipping so every frame is drawn).

import fs

script = "projects/recomp/snes/tools/oracle.lua"

fn mesenWord():
	SetupWord("mesen", "mesen=<path>: Mesen.exe, when it is not the winget package's")

# Mesen's executable: mesen of ZAP_SETUP, else the winget package's
pub fn mesenPath() str:
	if mesenWord().value() is given: return given.copy()
	packages = "{env.get("LOCALAPPDATA") ?? ""}/Microsoft/WinGet/Packages"
	for name in fs.list(packages) ?? []:
		if name.startsWith("SourMesen.Mesen2"):
			exe = "{packages}/{name}/Mesen.exe"
			if fs.exists(exe): return exe
	fail("Mesen 2 not found: winget install SourMesen.Mesen2, or ZAP_SETUP=mesen=<path to Mesen.exe>")
	""

# Mesen 2 reads a coprocessor's firmware from its own folder only: the firmware files beside the
# dump (tools/gather.zap's) are copied there, so the project's folder stays the one source.
fn giveFirmware(romPath str):
	folder = "{fs.userDir()}/Documents/Mesen2/Firmware"
	dir = fs.dirOf(romPath)
	for name in fs.list(dir) ?? []:
		if not name.endsWith(".rom"): continue
		bytes = fs.readBytes(fs.join(dir, name)) ?? continue
		target = fs.join(folder, name)
		if (fs.readBytes(target) ?? []) == bytes: continue
		_ = fs.createDir(folder)
		fs.writeBytes(target, bytes) ?? fail("cannot give Mesen {target}: {error}")

# Runs the oracle in `mode` over the cartridge for `frames` frames, writing `out`; `route` a
# file of "frame buttons" lines or ""; `extra` more of the script's variables (its header), the
# values absolute paths where they are paths. The script's timeout is generous: a long route
# takes its time. Fails when Mesen does.
pub fn runOracle(mode str, romPath str, frames i64, out str, route str, extra {str: str}):
	giveFirmware(romPath)
	env.set("SNESRECOMP_MODE", mode)
	env.set("SNESRECOMP_FRAMES", "{frames}")
	env.set("SNESRECOMP_OUT", fs.join(currentDir(), out))
	env.set("SNESRECOMP_ROUTE", fs.join(currentDir(), route) if not route.isEmpty else "")
	for name, value in extra:
		env.set(name, value)
	timeout = frames / 10 + 300   # generous: Mesen with the script runs some 40-100 frames a second
	command = "\"{mesenPath()}\" --testRunner --timeout={timeout} --snes.ramPowerOnState=AllZeros --snes.port1.type=SnesController --snes.disableFrameSkipping=true {script} \"{romPath}\""
	if Process.run(command) != 0: fail("Mesen failed: {command}")
	if not fs.exists(out):
		fail("Mesen wrote nothing to {out}: is the script's I/O allowed in its settings?")

# The build `exe` played headless from power-on along `route` for `frames` frames (with `options`),
# its hashes written to `hashes` and compared with Mesen 2's for the route: compare.zap's verdict.
pub fn playedAgainst(
	exe str, route str, mesenHashes str, hashes str, frames i64, options str
) str:
	played = Process.output(
		"{exe} --headless {options} --frames {frames} --route {route} --hashes {hashes}"
	)
	if played.code != 0: return "the build ended with {played.code}"
	said = Process.output("{zapPath()} run projects/recomp/snes/compare.zap {mesenHashes} {hashes}")
	(said.out.lines().first ?? "compare.zap said nothing").copy()

# the verdict of `frames` frames all equal
pub fn allEqual(frames i64) str:
	"{frames} frames compared: {frames} match whole, {frames} in work RAM, {frames} in the picture"
