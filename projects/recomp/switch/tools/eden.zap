# A homebrew run by Eden (an emulator, the oracle for whole programs) on the arm64 host
# (ZAP_BENCH_HOST, reached by ssh), headless: eden-cli with SDL's offscreen driver and the null
# renderer. What the homebrew printed with svcOutputDebugString is written to
# tests/homebrew/<name>.txt, which tests/homebrew.zap compares with this recompiler's run. Eden is
# fetched and set up on the host the first time. Run from the repository root:
#
#   zap run projects/recomp/switch/tools/eden.zap <homebrew.nro>...

import fs

edenUrl = "https://git.eden-emu.dev/eden-emu/eden/releases/download/v0.2.1/Eden-Linux-v0.2.1-aarch64-gcc-standard.AppImage"
host = env.get("ZAP_BENCH_HOST") ?? fail("no arm64 host: set ZAP_BENCH_HOST")
expected = "projects/recomp/switch/tests/homebrew"

# a command run on the host; its output
fn remote(command str):
	got = Process.output("ssh {host} \"{command}\"")
	got.out

# Eden on the host, extracted, its configuration made once and its renderer set to null (2)
fn setUp():
	remote(
		"mkdir -p ~/oracle && cd ~/oracle && if [ ! -x eden/squashfs-root/bin/eden-cli ]; then mkdir -p eden && cd eden && curl -sL -o eden.AppImage {edenUrl} && chmod +x eden.AppImage && ./eden.AppImage --appimage-extract > /dev/null; fi"
	)
	config = "~/.config/eden/sdl2-config.ini"
	remote(
		"cd ~/oracle && if [ ! -f {config} ]; then SDL_VIDEODRIVER=offscreen timeout 10 ./eden/squashfs-root/bin/eden-cli > /dev/null 2>&1; fi; sed -i 's/^backend.default=true/backend\\\\\\\\default=false/; s/^backend=[0-9]/backend=2/' {config}"
	)

# the lines the homebrew printed, from Eden's log (each after the logger's line for the call)
fn printed(log str):
	out = []
	lines = log.lines()
	inside = false
	for line in lines:
		if "svc_debug_string" in line:
			inside = true
			continue
		if line.startsWith("[") or (not line.isEmpty and line[0] == 27): inside = false   # the next log entry
		if not inside: continue
		plain u8[] = line.replace("[0m", "").bytes().filter(it != 27)   # the colour's escape gone
		if plain.text().trimmed() != "": out.push(plain.text().trimmed().copy())
	out

setUp()
for path in args.positional():
	name = fs.stem(path)
	Process.output("scp -q {path} {host}:oracle/{name}.nro")
	log = remote("cd ~/oracle && SDL_VIDEODRIVER=offscreen timeout 60 ./eden/squashfs-root/bin/eden-cli {name}.nro 2>&1")
	lines = printed(log)
	target = "{expected}/{name}.txt"
	fs.writeFile(target, "{lines.join("\n")}\n") ?? fail("cannot write {target}: {error}")
	print("{target}: {lines.len} lines")
