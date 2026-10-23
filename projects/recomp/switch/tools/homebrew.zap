# The test homebrews built into rom/homebrew/<name>.nro with libnx, in the devkitpro/devkita64
# container (Docker): ours (tests/homebrew/*.c, written to compare this recompiler's run with an
# emulator's) and switchbrew's deko3d examples (switch-examples, fetched once into the cache: a
# triangle, and the nine examples behind a menu), the GPU's first tests. Run from the repository
# root:
#
#   zap run projects/recomp/switch/tools/homebrew.zap

import fs

sources = "projects/recomp/switch/tests/homebrew"
out = "projects/recomp/switch/rom/homebrew"
examplesUrl = "https://github.com/switchbrew/switch-examples/archive/refs/heads/master.tar.gz"
examples = ["graphics/deko3d/deko_basic", "graphics/deko3d/deko_examples"]

# the command line run in the container, the dirs mounted at /src and /out
fn inContainer(src str, line str) str:
	got = Process.output(
		"docker run --rm -v {src}:/src -v {fs.normalize(currentDir())}/{out}:/out devkitpro/devkita64 sh -c \"{line}\"",
		vars = ["MSYS_NO_PATHCONV=1"]
	)
	if got.code != 0: fail(got.out)
	got.out

fs.createDir(out) ?? fail("cannot make {out}: {error}")
for name in fs.list(sources) ?? []:
	if not name.endsWith(".c"): continue
	stem = fs.stem(name)
	inContainer(
		"{fs.normalize(currentDir())}/{sources}",
		"DKP=/opt/devkitpro; $DKP/devkitA64/bin/aarch64-none-elf-gcc -march=armv8-a+crc+crypto -mtune=cortex-a57 -mtp=soft -fPIE -O2 -D__SWITCH__ -I$DKP/libnx/include -specs=$DKP/libnx/switch.specs /src/{name} -L$DKP/libnx/lib -lnx -lm -o /tmp/{stem}.elf && $DKP/tools/bin/elf2nro /tmp/{stem}.elf /out/{stem}.nro"
	)
	print("{out}/{stem}.nro")
cache = fs.join(fs.cacheDir("zap"), "switch-examples")
if not fs.isFetched(cache) and not fs.fetchUnpacked(examplesUrl, "switch-examples-master", cache):
	fail("cannot fetch {examplesUrl}")
for dir in examples:
	stem = fs.fileName(dir)
	inContainer(
		cache,
		"cp -r /src/{dir} /tmp/{stem} && cd /tmp/{stem} && make > /dev/null && cp {stem}.nro /out/"
	)
	print("{out}/{stem}.nro")
