# 13.1 The `zap` command
#
# Seven commands: `zap run` compiles and runs, the words after the file going to the program; `zap
# build`; `zap test`; `zap fmt`; `zap doc`; `zap branch`, which begins, lands and lists the
# repository's branches (13.1.5); and `zap lsp`, the language server on stdin and stdout.
# The commands, their options and what follows them are the compiler's declarations, each with a
# line saying what it does: the command line is read from them, and `zap` alone and `zap doc
# commands` (after this section) print them. A command, an option or a valued option's value that
# is missing or unknown is refused with the command's usage, exit code 2. The tests below run
# `zapPath()` (build/zap) from the repository's root on files they write in their own `testDir()`.

import fs

# what a zap command line writes, both streams, and its exit code
fn zapSays(words str):
	said = Process.output("{zapPath()} {words}")
	"{said.code}\n{said.out.replace("\r\n", "\n")}"

test "an option the command does not declare is refused with its usage":
	said = zapSays("build --fast x.zap").lines()
	print(said[..3].join("\n"))
	prints """
		2
		zap build: no option --fast
		zap build [--assets dir] [--icon file.png] [--label name] [--target name] [--seeds] <file.zap>
		"""

test "zap alone prints every command, and a command that is none is refused":
	expect zapSays("").startsWith(
		"2\nzap run [--assets dir] [--icon file.png] [--label name] [--target name] <file.zap> [args...]\n"
	)
	expect zapSays("frob").startsWith("2\nzap: no command 'frob'\nzap run ")

# `zap build file.zap` checks, then writes `build/file.exe` under the working directory (created
# when missing; what a test starts writes it in the test's dir, 13.1), for the system zap runs on. `--target` names another: `windows` (x64, a PE),
# `linux` (x64) or `linux-arm64`, a static ELF `build/file` that needs no loader nor library,
# unless the program calls a function of a library (`extern loaded`, or Vulkan's): then glibc's
# loader loads it with the C library, whose dlopen finds the library when the program runs, so a
# machine without it builds the program and stops it at the call (`android` and `android-x64`
# make an app of the same code, below). `zap test --target` runs the tests so built
# where the target runs: x64 Linux's in a Docker container of linux/amd64, arm64's on the machine
# arm64 in ZAP_SETUP names, over ssh, Android's over adb on an emulator, skipping those of Windows' own
# tools (compiler/targets/run.zap), and `zap run --target` runs the program built so there. zap
# itself runs on each, built as any program (`zap build --target linux compiler/zap.zap`). An
# error reads
# `file:line:col: error: message` (`error[code]:` for a named one, the code of the name `refuses`
# gives), then the source line with a caret.

test "an error names its place and its code, then shows its line with a caret":
	file = "{testDir()}wrong.zap"
	_ = fs.writeFile(file, "x = 1\nprint(y)\n")
	compiled = Process.output("{zapPath()} build {file}")
	said = compiled.out.replace("\r\n", "\n").lines()
	print(compiled.code != 0)
	print(said[0].endsWith("wrong.zap:2:7: error[unknown-variable]: unknown variable 'y'"))
	print(said[1..3].join("\n"))
	prints """
		true
		true
		   2 | print(y)
		     |       ^
		"""

# `--target android` or `android-x64` makes the program an app, `build/file.apk`, written by zap
# alone: the framework's NativeActivity (no Java code), its manifest, and the
# program as the shared object `lib/<abi>/libmain.so` the app's process loads (its entry
# `ANativeActivity_onCreate`, its code the executable's, its few addresses relocated where the
# loader puts it), signed by APK Signature Scheme v2 with a key made once per machine, outside any
# checkout (`android-debug-key` in `fs.cacheDir("zap")`). The app's package is `zap.<file>`. The
# program runs on a thread of its own; its stdout's and stderr's lines go to logcat (tag
# `zap.<file>.out`, info and error), and its end says its exit code there (`zap.<file>.exit`) and
# ends the app's process. Its files are the dir the system gives it outside its private storage
# (`/sdcard/Android/data/zap.<file>/files`): `exePath()` names it as the program's place, so what
# adb puts there is beside the program, and its arguments are the lines of `args` there. `zap run
# --target android-x64 file.zap args...` installs the app over adb on the emulator, writes the
# arguments, starts it, prints its lines as logcat gives them and ends with its exit code; with no
# emulator answering it says so, exit code 2, and the test below is skipped, saying so.
# `--assets dir` puts dir's files in the APK (assets/), which the app copies into its files dir at
# its first start: what the program needs beside it travels inside the app. `--icon file.png` is
# its launcher's picture (an adaptive icon filled by it) and `--label name` the name under it. An
# app calls the system's C libraries (`extern "libandroid.so" fn ...`) from a thread of bionic's;
# it is wide (landscape, no status bar) and kept through a turn of the device, its window, keys and
# touches the engine's (engine/linux/app/: a picture of any size shown filling the screen's height, the
# fingers' places, a game pad's buttons, AAudio's sound), and its end, Back included, ends the
# program. The GPU is not an app's yet.

# The program `source` written as `stem`.zap and run as an app with the words (FILE its path):
# what zap said (its code, then its lines), none when no emulator answers (the test skipped)
fn appSays(stem str, source str, words str) str?:
	file = "{testDir()}{stem}.zap"
	_ = fs.writeFile(file, source)
	said = zapSays("run --target android-x64 {words.replace("FILE", file)}")
	if said.startsWith("2\nzap: no Android emulator"):
		eprint("  skipped   an app on Android: {said.lines()[1]}")
		return none
	said

test "an app built by zap runs on Android's emulator, what it prints read from logcat":
	file = "{testDir()}hello.zap"
	source = "print(\"hello from an app\")\neprint(\"\{6 * 7}\")\nprint(args.positional().join(\" \"))\nprint(exePath())\nexit(4)\n"
	said = appSays("hello", source, "FILE one two") ?? return
	expect said == "4\nhello from an app\n42\none two\n/storage/emulated/0/Android/data/zap.hello/files/zap.hello\n"
	expect zapSays("build --target android-x64 {file}") == "0\nbuilt build/hello.apk\n"

test "an app's assets are in its files dir when it runs":
	assets = "{testDir()}assets"
	_ = fs.createDir(assets)
	_ = fs.writeFile("{assets}/note.txt", "carried in the app")
	source = "import fs\nprint(fs.readFile(fs.join(fs.dirOf(exePath()), \"note.txt\")) ?? \"none\")\n"
	said = appSays("carried", source, "--assets {assets} FILE") ?? return
	expect said == "0\ncarried in the app\n"

# Each function's optimized intermediate form is kept in `build/cache/ir/` (a file per source
# file, shared by every program that builds its functions), keyed by its form as lowered, each
# source file's nodes as parsed in `build/cache/parse/`, keyed by its text, and each stage of the
# runtime and std as checked in `build/cache/` (14.2), so the next build, of this program or
# of another using the same modules, skips those passes for what did not change and writes the
# same bytes. `ZAP_RUN=kept` says the stages a build read kept and those it kept.

fn built(file str, cache bool):
	Process.output("{zapPath()} build {file}", vars = [] if cache else ["ZAP_RUN=nocache"])
	fs.readFile(builtExe(fs.stem(file))) ?? "none"

# the program, its function twice multiplying by `factor` (and one with a number parameter,
# whose body the parser keeps)
fn program(factor i64):
	"fn twice(x i64) i64: x * {factor}\n\nfn label(x i64) str: \"n\{x}\"\n\nfn last<N n64>(a i64[N]) i64: a[N - 1]\n\nprint(label(twice(last([20, 21]))))\n"

test "a build from the cache is the build without it, after an edit too":
	dir = testDir()
	file = "{dir}cached.zap"
	_ = fs.writeFile(file, program(2))
	cold = built(file, false)
	made = built(file, true)
	expect made == cold and (fs.list("build/cache/ir") ?? []).any(.endsWith("-cached.ir")) and
		(fs.list("build/cache/parse") ?? []).any(.endsWith("-cached"))
	expect built(file, true) == cold
	_ = fs.writeFile(file, program(3))
	edited = built(file, true)
	expect edited != cold and edited == built(file, false)
	expect Process.output(builtExe("cached")).out.trimmed() == "n63"

test "a second build of an edited program reuses the kept runtime and std":
	file = "{testDir()}reused.zap"
	_ = fs.writeFile(file, "import fs\n\nprint(fs.fileName(\"a/b.zap\"))\n")
	Process.output("{zapPath()} build {file}", vars = ["ZAP_RUN=kept"])
	_ = fs.writeFile(file, "import fs\n\nprint(fs.fileName(\"a/c.zap\"))\n")
	said = Process.output("{zapPath()} build {file}", vars = ["ZAP_RUN=kept"]).out
	expect "kept: read rt/core" in said and
		said.lines().any(.startsWith("kept: read ") and .endsWith(" fs"))
	expect (fs.readFile(builtExe("reused")) ?? "none") == built(file, false)
	expect Process.output(builtExe("reused")).out.trimmed() == "c.zap"

# `zap run` builds as `zap build` does and starts the executable with the words after the file. A
# run that changed nothing builds nothing: the executable is kept with a stamp of what it was
# built from (the compiler, each source the build read with its dir, the entry, the words of
# ZAP_RUN and ZAP_SETUP, the executable's own write), and a run that finds them as they were
# starts it without loading the program (a source or a dir last written when the stamp says is
# not read again: its text is the one hashed). A file outside a checkout (no build/zap.exe in its dir
# or one above it) is built in the user's cache (`fs.cacheDir("zap")`), its executable under the
# file's full path and its caches with the others there: the working dir is left as it was.

test "a run of an unchanged file starts the executable it built":
	file = "{testDir()}again.zap"
	_ = fs.writeFile(file, "print(\"first\")\n")
	ran = Process.output("{zapPath()} run {file}").out
	exe = builtExe("again")
	written = fs.modified(exe) ?? -1
	expect ran.trimmed() == "first" and Process.output("{zapPath()} run {file}").out == ran
	expect (fs.modified(exe) ?? -2) == written
	_ = fs.writeFile(file, "print(\"second\")\n")
	expect Process.output("{zapPath()} run {file}").out.trimmed() == "second"
	expect (fs.modified(exe) ?? -2) != written

test "a run of a file outside a checkout leaves the working dir as it was":
	dir = "{fs.cacheDir("zap")}/outside"
	_ = fs.createDir(dir)
	_ = fs.writeFile("{dir}/alone.zap", "print(\"alone\")\n")
	said = Process.output("{fs.join(currentDir(), zapPath())} run alone.zap", dir = dir).out
	listed = fs.list(dir) ?? []
	_ = fs.deleteTree(dir)
	expect said.trimmed() == "alone" and listed == ["alone.zap"]

# A second program using a module finds its functions in the module's file of the cache, which
# it leaves as the first program wrote it, and builds the same bytes as without the cache.
test "two programs sharing a module reuse its cached functions":
	dir = testDir()
	_ = fs.createDir("{dir}scales")
	_ = fs.writeFile(
		"{dir}scales/scales.zap",
		"pub fn scaled(x i64) i64: x * 3 + 1\n\npub fn named(xs i64[]) str: xs.map(\"s\{scaled(it)}\").join(\" \")\n"
	)
	for i, name in ["first", "second"]:
		_ = fs.writeFile(
			"{dir}{name}.zap",
			"import scales\n\nprint(\"{name}\")\nprint(scales.named([{i}, 7]))\n"
		)
	built("{dir}first.zap", true)
	shard = "build/cache/ir/{(fs.list("build/cache/ir") ?? []).filter(.endsWith("-scales-scales.ir")).first ?? "none"}"
	kept = fs.readFile(shard) ?? "none"
	second = built("{dir}second.zap", true)
	expect kept != "none" and (fs.readFile(shard) ?? "") == kept
	expect second == built("{dir}second.zap", false)
	expect Process.output(builtExe("second")).out.trimmed().lines() == ["second", "s4 s22"]

# A module's file read back from the cache lands where its nodes go this time (here after entry
# files of 40 lines, then fewer), an arm of several patterns still the arm of its first.
test "an arm of several patterns read back from the cache":
	dir = testDir()
	_ = fs.createDir("{dir}picks")
	picks = "pub fn pick(o i64) str:\n\tmatch o:\n\t\t1, 3, 5, 7: \"odd\"\n\t\t2: \"two\"\n\t\t4, 6: \"even\"\n\t\t_: \"other\"\n"
	_ = fs.writeFile("{dir}picks/picks.zap", picks)
	file = "{dir}arms.zap"
	said = []
	for lines in [40, 21, 7, 0]:
		filler = (0..lines).map("print({it})\n").join("")
		_ = fs.writeFile(file, "import picks\n\n{filler}print([1, 2, 6, 7].map(picks.pick(it)))\n")
		built(file, true)
		out = Process.output(builtExe("arms")).out
		said.push(str(out.trimmed().lines().last ?? ""))
	print(said.filter(it != "[\"odd\", \"two\", \"even\", \"odd\"]"))
	prints "[]"
