# An Android app's process (`zap build --target android`): the program runs on a thread of its own
# (compiler/targets/android/entry.zap) in a process the system made, so stdout's and stderr's
# lines go to logcat (logd's socket, info and error, tag `<package>.out`: the package alone is the
# system's own lines' tag), the end is said there (tag `<package>.exit`, the exit code) before the
# process ends, a crash is reported there with the program's calls as on Linux (faults.zap), and
# the image is where its loader put it.

extern "syscall socket" fn sysSocket(family i64, kind i64, protocol i64) i64
extern "syscall connect" fn sysConnect(s i64, address u8[], size i64) i64
extern "libc.so" "sigaction" fn sigactionOfC(signal i64, action u8[], old i64) i32

# global slots: 11 where the image is (its loader's relocation, elf.zap), 12 where its package
# is (compiler/targets/android/entry.zap), 13 logd's socket, 18 the ANativeActivity the
# system made the app with (the entry keeps it), 19..24 its window and input (window.zap)
slotImageBase = 11
slotAppTag = 12
slotLogSocket = 13
slotActivity = 18

pub imageBase = gv(slotImageBase)

# the bytes of a logcat record's text at most (logd takes 4068)
logRecordBytes = 4000

# The kernel's page size, which an app finds by trying (its auxiliary vector is not given it, nor
# /proc/self/auxv readable): the smallest size past which mprotect takes a page's start
fn pageBytes() i64:
	known = gv(slotPageBytes)
	if known != 0: return known
	most = 65_536
	base = sysMmap(0, 2 * most, protectNone, mapPrivate, -1, 0)
	size = 4096
	while size < most and failed(sysMprotect(base + size, size, protectNone)):
		size *= 2
	_ = sysMunmap(base, 2 * most)
	gset(slotPageBytes, size)
	size

# A crash's signals handled as on Linux (faults.zap's crashSignal), through the C library's
# sigaction: ART's chain of signals (libsigchain, which the process lives by) keeps those it
# claims (its own checks in Java's code) and hands the others to the handler. Its action as
# bionic lays it out: the flags (SA_SIGINFO, SA_ONSTACK, SA_NODEFER), the handler, the mask.
fn setCrashFilter() bool:
	setCrashStack()
	action = zeroBytes(32)
	action.setU32le(0, 0x4800_0004)
	action.setU64le(8, u64(__callback(crashSignal)))
	for s in crashSignals:
		_ = sigactionOfC(s, action, 0)
	true

# stdout's and stderr's bytes to logcat, a record a line, info and error
fn writeSome(h i64, bytes u8[]) i64:
	if h != 1 and h != 2:
		n = sysWrite(h, bytes, bytes.len)
		return -1 if failed(n) else n
	from = 0
	for i, b in bytes:
		if b == '\n' or i - from == logRecordBytes:
			logWrite(4 if h == 1 else 6, "{appTag()}.out", bytes[from..i])
			from = i + (1 if b == '\n' else 0)
	if from < bytes.len:
		logWrite(4 if h == 1 else 6, "{appTag()}.out", bytes[from..])
	bytes.len

# ExitProcess(code): the code to logcat, the activity finished (the app closes to the launcher: a
# process that ends under its activity has it started again), then every thread ends
fn exitProcess(code i64):
	logWrite(4, "{appTag()}.exit", "{code}".bytes())
	finishActivity()
	_ = sysExitGroup(code)

# the app's package, which its tags start with
fn appTag() str:
	str(cBytes(gv(slotAppTag)))

# a record of logd's: its header (the main log, the thread, the time), the priority, the tag, the
# text
fn logWrite(priority i64, tag str, text u8[]):
	time = zeroBytes(16)
	_ = sysClockGettime(0, time)
	record u8[] = [0]
	record.pushU16le(sysGettid())
	record.pushU32le(time.i64le(0))
	record.pushU32le(time.i64le(8))
	record.push(u8(priority))
	record.extend(tag.bytes())
	record.push(0)
	record.extend(text)
	record.push(0)
	_ = sysWrite(logSocket(), record, record.len)

# logd's socket, connected at the first record
fn logSocket() i64:
	known = gv(slotLogSocket)
	if known != 0: return known - 1
	s = sysSocket(1, 0x8_0002, 0)   # AF_UNIX, SOCK_DGRAM | SOCK_CLOEXEC
	address = zeroBytes(110)
	address.setU16le(0, 1)
	for i, b in "/dev/socket/logdw".bytes():
		address[2 + i] = b
	_ = sysConnect(s, address, 110)
	gset(slotLogSocket, s + 1)
	s

# The dir of the app's own files outside its private storage, ANativeActivity's externalDataPath
# (/storage/emulated/0/Android/data/<package>/files): what adb puts there is the app's to read, the
# player's files beside "the program" and its arguments.
fn appFilesDir() str:
	dir = externalDataDir()
	unpackAssets(dir)
	dir

fn externalDataDir() str:
	str(cBytes(__ld64(gv(slotActivity) + 40)))

# An app is given no environment: the variables are the lines of `env` in its files dir
# ("NAME=value"; `zap run --target android` writes ZAP_RUN's there), its assets not unpacked yet
# (the runtime reads ZAP_RUN before its first allocation is done), its read not noted (the file
# of the paths read is named by a variable).
fn givenEnvValue(prefix str) str?:
	text = readOpened(openUnnoted("{externalDataDir()}/env")) ?? return none
	for line in text.lines():
		if line.startsWith(prefix): return line[prefix.len..].copy()
	none

# the arguments: the lines of `args` in the app's files dir (`zap run --target android` writes it)
fn commandLine() str[]:
	text = readFile("{appFilesDir()}/args") ?? return []
	text.lines().filter(not .isEmpty).map(it.copy())

# the program as the app's files dir holds it: the files beside it are those adb put for the app
pub fn exePath() str:
	"{appFilesDir()}/{appTag()}"
