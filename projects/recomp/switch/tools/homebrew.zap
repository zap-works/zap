# The test homebrews (tests/homebrew/*.c, written to compare this recompiler's run with an
# emulator's) built into rom/homebrew/<name>.nro with libnx, in the devkitpro/devkita64 container
# (Docker). Run from the repository root:
#
#   zap run projects/recomp/switch/tools/homebrew.zap

import fs

sources = "projects/recomp/switch/tests/homebrew"
out = "projects/recomp/switch/rom/homebrew"

fs.createDir(out) ?? fail("cannot make {out}: {error}")
here = fs.normalize(currentDir())
for name in fs.list(sources) ?? []:
	if not name.endsWith(".c"): continue
	stem = fs.stem(name)
	build = "DKP=/opt/devkitpro; $DKP/devkitA64/bin/aarch64-none-elf-gcc -march=armv8-a+crc+crypto -mtune=cortex-a57 -mtp=soft -fPIE -O2 -D__SWITCH__ -I$DKP/libnx/include -specs=$DKP/libnx/switch.specs src/{name} -L$DKP/libnx/lib -lnx -lm -o /tmp/{stem}.elf && $DKP/tools/bin/elf2nro /tmp/{stem}.elf out/{stem}.nro"
	got = Process.output(
		"docker run --rm -v {here}/{sources}:/src -v {here}/{out}:/out devkitpro/devkita64 sh -c \"{build}\"",
		vars = ["MSYS_NO_PATHCONV=1"]
	)
	if got.code != 0: fail("{name}: {got.out}")
	print("{out}/{stem}.nro")
