# The process on Linux (sys.zap): the arguments and the environment the kernel put on the
# stack at the start (global slot 2 keeps where: argc, the argument pointers, 0, the
# environment's, 0) and the variables a program sets.

extern "syscall clone" fn sysClone(flags i64, stack i64, parentTid i64, tls i64, childTid i64) i64

slotStackBase = 2

# the address of the i-th word the kernel left on the stack
fn startWord(i i64) i64:
	__ld64(gv(slotStackBase) + 8 * i)

# the arguments after the program's name
fn commandLine() str[]:
	(1..startWord(0)).map(str(cBytes(startWord(1 + it))))

# the variables set by the program, "NAME=value", the latest last
mut envSet str[] = []

# the address of the environment's first pointer
fn environmentStart() i64:
	gv(slotStackBase) + 8 * (startWord(0) + 2)

# slot 9: the kernel's page size once read
slotPageBytes = 9

# The kernel's page size: 4 KB, or 16 KB or 64 KB on some (an Android of 16 KB pages), its
# auxiliary vector's AT_PAGESZ, the pairs after the environment's last pointer
fn pageBytes() i64:
	known = gv(slotPageBytes)
	if known != 0: return known
	at = environmentStart()
	while __ld64(at) != 0:
		at += 8
	at += 8
	size = 4096
	while __ld64(at) != 0:
		if __ld64(at) == 6: size = __ld64(at + 8)
		at += 16
	gset(slotPageBytes, size)
	size

# the value of the variable, none when it is not set
fn envValue(name str) str?:
	prefix = "{name}="
	for i in 0..envSet.len:
		v = envSet[len - 1 - i]
		if v.startsWith(prefix): return v[prefix.len..].copy()
	givenEnvValue(prefix)

# the value the process was given of the variable (`prefix` its name and =), none when it was not
fn givenEnvValue(prefix str) str?:
	p = environmentStart()
	while __ld64(p) != 0:
		v = str(cBytes(__ld64(p)))
		if v.startsWith(prefix): return v[prefix.len..].copy()
		p += 8
	none

# GetEnvironmentVariableA: the value and its NUL in buf when they fit (its length), else the
# room they need; 0 when it is not set
fn getEnvironmentVariableA(name u8[], mut buf u8[], size i64) i32:
	value = envValue(str(name[..len - 1].copy())) ?? return 0
	if value.len + 1 > size: return i32(value.len + 1)
	for i, b in value.bytes():
		buf[i] = b
	buf[value.len] = 0
	i32(value.len)

fn setEnvironmentVariableA(name u8[], value u8[]) bool:
	envSet.push(str(name[..len - 1].copy()) + "=" + str(value[..len - 1].copy()))
	true
