# The machine and the system a build writes for, the one switch the backend reads: a target is a
# machine (x64 or arm64: the code) and a system (Windows or Linux: the executable's format, the
# stubs of the extern fns, the runtime's system layer). Windows on x64 writes a PE (the default);
# Linux a static ELF, on x64 (`--target linux`) or on arm64 (`linux-arm64`); Android runs Linux's
# (`android` is arm64's, run on a device over adb, `android-x64` x64's, on an emulator). The lowering and its passes are the same for all.

import fs

machineX64 = 0

machineArm64 = 1

systemWindows = 0

systemLinux = 1

# where zap test runs a target's executables when they are not the host's (run.zap)
runnerDocker = 0
runnerSsh = 1
runnerAdb = 2

type Target:
	name str
	machine i64
	system i64
	runner i64 = runnerDocker
	isHost bool = true   # a system the compiler runs on, with a seed (Android is a target only)
	atomics bool = false   # arm64 with ARMv8.1's atomics (LSE): Linux's servers have them, phones may not

targets = [
	Target("windows", machineX64, systemWindows),
	Target("linux", machineX64, systemLinux),
	Target("linux-arm64", machineArm64, systemLinux, runner = runnerSsh, atomics = true),
	Target("android", machineArm64, systemLinux, runner = runnerAdb, isHost = false),
	Target("android-x64", machineX64, systemLinux, runner = runnerAdb, isHost = false)
]

# whether the build is an Android app's program (`zap build --target android`): a shared object
# the app's process loads (elf.zap), its runtime's system read from linux/app/ too (systemDirsOf)
mut appBuild = false
mut appAssetsDir = ""   # --assets: the dir whose files an app's APK carries under assets/
mut appIconFile = ""   # --icon: the PNG an app's launcher shows
mut appLabel = ""   # --label: the name it shows under it (the file's stem when none)

# the runner of the build's target
fn runner():
	targets[buildTarget].runner

# the target this compiler runs on (compiler/linux/x64/ and arm64/ say theirs)
fn hostTarget():
	"windows"

mut buildTarget = targets.findIndex(.name == hostTarget()) ?? 0   # the build's target in targets

# the row of the target this compiler runs on
fn host():
	targets.find(.name == hostTarget()) ?? targets[0]

# whether the build's executables run here: the target's machine and system the host's
fn hostRuns():
	targets[buildTarget].machine == host().machine and targets[buildTarget].system == host().system

# whether the build writes AArch64 code
fn onArm():
	targets[buildTarget].machine == machineArm64

# whether the build's atomics are single instructions (ldaddal, casal) rather than ldaxr/stlxr loops
fn armAtomics():
	targets[buildTarget].atomics

# whether the build is for Linux (an ELF, Linux's system calls, the runtime's linux/ dirs)
fn onLinux():
	targets[buildTarget].system == systemLinux

# the target named by `--target`, refused with the names there are
fn chooseTarget(name str):
	buildTarget = targets.findIndex(.name == name) ?? exit(
		2,
		"zap build: no target '{name}' ({targets.map(.name).join(", ")})"
	)

# what the names of a build's own files (the IR cache's) add for the target: "" for the host's
# machine and system, those for the others (android and linux-arm64 share theirs)
fn targetTag():
	t = targets[buildTarget]
	"" if hostRuns() else ".{["x64", "arm64"][t.machine]}-{["windows", "linux"][t.system]}"

# an executable's extension for the target: Linux's has none
fn extensionOf(t Target):
	"" if t.system == systemLinux else ".exe"

# the build's executables' extension
fn exeExtension():
	targets[buildTarget].extensionOf()

# the executable built from a source of this stem (in buildsDir: build/, or a test's own dir; a
# run's outside a checkout in the user's cache, runstamp.zap; an app's program, its shared object)
fn exeFileOf(stem str):
	dir = runExeDir if runExeDir != "" else buildsDir()
	"{dir}{stem}{".so" if appBuild else exeExtension()}"

# An executable written at path: a program running from that file (the zap that rebuilds itself,
# a game rebuilt while it runs) is moved aside to path.old first, as Windows writes no running
# program's file and Linux refuses to open one for writing. Whether it was written.
fn writeExecutable(path str, bytes u8[]):
	if fs.exists(path):
		match fs.deleteFile(path):
			error:
				aside = "{path}.old"
				_ = fs.deleteFile(aside)
				Process.run(shellLine(moveLine(path, aside)))
			_: pass
	match fs.writeBytes(path, bytes):
		error: false
		_: true

# the option a zap started to build for the target is given ("" for windows)
fn targetOption():
	"" if targets[buildTarget].name == hostTarget() else " --target {targets[buildTarget].name}"

# The declarations of a module for the target's system live in a dir of its own beside the
# module's files (runtime/system/linux/, std/net/linux/), and those of the target's machine in
# one inside it (linux/x64/, linux/arm64/), and an Android app's (linux/app/, appBuild) after them,
# read only when building for it: each takes the place
# of the declaration of the same name before it (a method's, of the same name and type), so the
# Windows parts, the module's own files, are what a windows build reads. A function of Windows the
# module calls by name (an extern fn, PascalCase) is replaced by one whose name is that name with
# its first letter lowered, which takes the Windows name.
fn systemDirsOf(dir str):
	if not onLinux(): return []
	dirs = ["{dir}linux/", "{dir}linux/{["x64", "arm64"][targets[buildTarget].machine]}/"]
	if appBuild:
		dirs.push("{dir}linux/app/")
	dirs

# the key a declaration is replaced by: its name, a method's type and name
fn replacedKey(nodes Node[], d NodeId):
	if nodes[d].kind == nImplDecl and nodes[d].kids.len == 1:
		return "{nodes[d].text}.{nodes[nodes[d].kids[0]].text}"
	nodes[d].text.copy()

# the module's files' declarations (one list a file) without those its system's files replace,
# the system's that replace a Windows function renamed to it
fn replaceForTarget(mut nodes Node[], move own NodeId[,], move system NodeId[,]):
	theirs {str: NodeId} = {}
	for file in system:
		for d in file:
			theirs[replacedKey(nodes, d)] = d
	kept = []
	for file in own:
		left = []
		for d in file:
			key = replacedKey(nodes, d)
			if key in theirs: continue
			if key == "":   # (a line with no name: a test's, the parts')
				left.push(d)
				continue
			lowered = "{key[..1].lower()}{key[1..]}"
			# (a function that took a Windows name before, from an earlier dir, too)
			windows = nodes[d].hasFlag(flagExtern) or nodes[d].kind == nFnDecl
			if windows and theirs.get(lowered) is r:
				nodes[r].text = key.copy()
				continue
			left.push(d)
		kept.push(left)
	kept.extend(system)
	kept
