# Files and dirs on Linux (sys.zap): a handle is a file descriptor, paths are taken as the
# program writes them, from the working directory (AT_FDCWD).

extern "syscall mkdirat" fn sysMkdirat(dir i64, path u8[], mode i64) i64
extern "syscall unlinkat" fn sysUnlinkat(dir i64, path u8[], flags i64) i64
extern "syscall renameat2" fn sysRenameat2(
	fromDir i64,
	from u8[],
	toDir i64,
	to u8[],
	flags i64
) i64
extern "syscall openat" fn sysOpenat(dir i64, path u8[], flags i64, mode i64) i64
extern "syscall close" fn sysClose(fd i64) i64
extern "syscall getdents64" fn sysGetdents64(fd i64, buf u8[], n i64) i64
extern "syscall lseek" fn sysLseek(fd i64, offset i64, whence i64) i64
extern "syscall readlinkat" fn sysReadlinkat(dir i64, path u8[], buf u8[], size i64) i64
extern "syscall newfstatat" fn sysNewfstatat(dir i64, path u8[], stat u8[], flags i64) i64
extern "syscall fstat" fn sysFstat(fd i64, stat u8[]) i64

workingDir = -100   # AT_FDCWD

# the descriptors are below this; a handle above it is a thread's event or semaphore (threads.zap)
descriptorEnd = 1_048_576

# CreateFileA: GENERIC_READ, GENERIC_WRITE or FILE_APPEND_DATA; CREATE_NEW 1, CREATE_ALWAYS 2,
# OPEN_EXISTING 3, OPEN_ALWAYS 4, TRUNCATE_EXISTING 5. The descriptor, or -1.
fn createFileA(
	path u8[],
	access i64,
	share i64,
	security i64,
	disposition i64,
	attrs i64,
	template i64
) i64:
	_ = share + security + attrs + template
	reads = access & 0x8000_0000 != 0
	writes = access & 0x4000_0004 != 0
	flags = 0x8_0000   # O_CLOEXEC
	flags |= 2 if reads and writes else 1 if writes else 0
	if access & 0x4000_0000 == 0 and access & 4 != 0:
		flags |= 0x400   # O_APPEND
	flags |= [0, 0xC0, 0x240, 0, 0x40, 0x200][disposition.clamp(0, 5)]
	fd = sysOpenat(workingDir, path, flags, 420)   # rw-r--r--
	-1 if failed(fd) else fd

# CloseHandle: a descriptor closed, or a thread's event or semaphore freed
fn closeHandle(h i64) bool:
	if h >= descriptorEnd: return closeSync(h)
	not failed(sysClose(h))

# the size of a regular file, 0 for any other handle (a pipe, a terminal)
fn fileSize(h i64) i64:
	stat = zeroBytes(statBytes)
	if failed(sysFstat(h, stat)) or stat.u32le(statMode) & 0xF000 != 0x8000: return 0
	stat.i64le(48)

fn fileLeft(h i64) i64:
	size = fileSize(h)
	at = sysLseek(h, 0, 1)   # SEEK_CUR
	if size == 0 or failed(at): return size
	(size - at).max(0)

# the file's position set to at, from its start: where it is then (-1 when it cannot move)
pub fn seekFile(h i64, at i64) i64:
	moved = sysLseek(h, at, 0)
	-1 if failed(moved) else moved

fn deleteFileA(path u8[]) bool:
	not failed(sysUnlinkat(workingDir, path, 0))

fn moveFileExA(from u8[], to u8[], flags i64) bool:
	_ = flags   # (rename replaces what is there)
	not failed(sysRenameat2(workingDir, from, workingDir, to, 0))

fn createDirectoryA(path u8[], security i64) bool:
	_ = security
	not failed(sysMkdirat(workingDir, path, 493))   # rwxr-xr-x

fn removeDirectoryA(path u8[]) bool:
	not failed(sysUnlinkat(workingDir, path, 0x200))   # AT_REMOVEDIR

# the stat of a path, or none (getLastError says why)
fn statOf(path u8[]) u8[]?:
	stat = zeroBytes(statBytes)
	if failed(sysNewfstatat(workingDir, path, stat, 0)): return none
	stat

# GetFileAttributesA: FILE_ATTRIBUTE_DIRECTORY (16) or NORMAL (128), -1 when nothing is there
fn getFileAttributesA(path u8[]) i32:
	stat = statOf(path) ?? return -1
	16 if stat.u32le(statMode) & 0xF000 == 0x4000 else 128

# Windows' ticks (100 ns since 1601) of a Unix time
unixEpochTicks = 116_444_736_000_000_000

fn modifiedAt(path str) i64?:
	stat = statOf(cstr(path)) ?? return none
	stat.i64le(88) * 10_000_000 + stat.i64le(96) / 100 + unixEpochTicks

# names in a dir (no "." and ".."), in order as Windows lists them
fn listDir(path str) str[] ? i64:
	fd = sysOpenat(workingDir, cstr(path), openDirectory | 0x8_0000, 0)   # O_DIRECTORY | O_CLOEXEC
	if failed(fd): return systemError()
	r str[] = []
	buf = zeroBytes(32_768)
	loop:
		n = sysGetdents64(fd, buf, buf.len)
		if n <= 0: break
		at = 0
		while at < n:
			end = at + 19
			while buf[end] != 0:
				end += 1
			name = str(buf[at + 19..end].copy())
			if name != "." and name != "..":
				r.push(name)
			at += i64(buf.u16le(at + 16))
	_ = sysClose(fd)
	r.sorted()

# names in a dir (no "." and "..") with when each was last written (modifiedAt's ticks)
fn listDirTimes(path str) (str, i64)[] ? i64:
	r (str, i64)[] = []
	for name in try listDir(path):
		r.push((name.copy(), modifiedAt("{path}/{name}") ?? 0))
	r

# the path of the running executable
pub fn exePath() str:
	buf = zeroBytes(4096)
	n = sysReadlinkat(workingDir, cstr("/proc/self/exe"), buf, 4095)
	buf.truncate(n.max(0))
	str(move buf)

pub fn exeSuffix() str:
	""

pub fn pathListSeparator() str:
	":"

# the working directory
pub fn currentDir() str:
	buf = zeroBytes(4096)
	n = sysGetcwd(buf, 4095)
	buf.truncate((n - 1).max(0))   # (its NUL counted)
	str(move buf)

# CreateFileMappingA of a file to read: the mapping's handle, the descriptor's one above it
fn createFileMappingA(h i64, attrs i64, protect i64, sizeHigh i64, sizeLow i64, name i64) i64:
	_ = attrs + protect + sizeHigh + sizeLow + name
	h + 1

# MapViewOfFile of the whole file, to read (0 when it cannot be mapped)
fn mapViewOfFile(mapping i64, access i64, offHigh i64, offLow i64, size i64) i64:
	_ = access + offHigh + offLow + size
	view = sysMmap(0, fileSize(mapping - 1), 1, 2, mapping - 1, 0)   # PROT_READ, MAP_PRIVATE
	0 if failed(view) else view
