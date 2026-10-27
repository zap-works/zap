# Files and dirs, the system's calls under std's fs (sys.zap): buffers are u8[] values the system
# fills; strings are built in a u8[] and become a str without a copy (str(move bytes)).

# The file functions fail with the system's error code (GetLastError), which std's fs names.

# the code of the system's last failed call
fn systemError() i64:
	GetLastError()

# the system's code for a file that ends before the bytes asked for (ERROR_HANDLE_EOF)
endOfFileError = 38

# the whole text of a file
fn readFile(path str) str ? i64:
	readOpened(openForRead(path))

# the whole text of the file h opened for reading (-1: it could not be), closed after
fn readOpened(h i64) str ? i64:
	if h == -1: return systemError()
	size = fileSize(h)
	buf = bytesToFill(size)
	n = readFully(h, buf, 0)
	if size == 0:
		readRest(h, buf)   # a file the system tells no size of (Linux's /proc) read to its end
	CloseHandle(h)
	if n < size: return endOfFileError
	str(move buf)

# writes the bytes to a file, replacing what it held, or adds them at its end (append), creating
# it if needed
fn writeBytes(path str, bytes u8[], append bool = false) ? i64:
	# FILE_APPEND_DATA and OPEN_ALWAYS, or GENERIC_WRITE and CREATE_ALWAYS
	access i64 = 4 if append else 1_073_741_824
	disp i64 = 4 if append else 2
	h = CreateFileA(cstr(path), access, 1, 0, disp, 128, 0)
	if h == -1: return systemError()
	writeRaw(h, bytes)
	_ = CloseHandle(h)

# writes the text to a file, replacing what it held
fn writeFile(path str, text str) ? i64:
	try writeBytes(path, text.bytes())

# adds the text at the end of a file, creating it if needed
fn appendFile(path str, text str) ? i64:
	try writeBytes(path, text.bytes(), append = true)

# when the file or dir was last written, in the system's ticks (100 ns since 1601); none when
# it cannot be read (systemError() says why)
fn modifiedAt(path str) i64?:
	info = zeroBytes(36)   # WIN32_FILE_ATTRIBUTE_DATA
	if not GetFileAttributesExA(cstr(path), 0, info): return none
	i64(info.u64le(20))   # ftLastWriteTime

# whether a file or dir exists at the path
fn fileExists(path str) bool:
	GetFileAttributesA(cstr(path)) != -1   # INVALID_FILE_ATTRIBUTES when there is none

# whether the path is a dir
fn isDir(path str) bool:
	attributes = GetFileAttributesA(cstr(path))
	attributes != -1 and attributes & 16 != 0   # FILE_ATTRIBUTE_DIRECTORY

# removes the file
fn deleteFile(path str) ? i64:
	if DeleteFileA(cstr(path)): return
	return systemError()

# moves the file to the other path, replacing what is there whole: a program reading `to`
# meanwhile reads the old file or the new one, never part of one
fn moveFile(from str, to str) ? i64:
	if MoveFileExA(cstr(from), cstr(to), 1): return   # MOVEFILE_REPLACE_EXISTING
	return systemError()

# removes a dir with what it holds, or a file (one that is not there counts as removed); the
# error is the first part that could not be removed
fn deleteTree(path str) ? i64:
	at = path[..len - 1].copy() if path.endsWith("/") else path.copy()
	if not fileExists(at): return
	if not isDir(at): return deleteFile(at)
	for name in listDir(at) ?? []:
		try deleteTree("{at}/{name}")
	if not RemoveDirectoryA(cstr(at)): return systemError()

# creates a dir and the dirs above it that are missing (an existing dir counts as
# created)
fn createDir(path str) ? i64:
	if CreateDirectoryA(cstr(path), 0) or fileExists(path): return
	# a missing dir above it is made first
	cut = path.lastIndexOf("/") ?? (path.lastIndexOf("\\") ?? 0)
	if cut <= 0: return systemError()
	try createDir(path[..cut])
	if CreateDirectoryA(cstr(path), 0) or fileExists(path): return
	return systemError()

# names in a dir (no "." and "..")
fn listDir(path str) str[] ? i64:
	r str[] = []
	for (name, _) in try listDirTimes(path):
		r.push(name.copy())
	r

# names in a dir (no "." and "..") with when each was last written (modifiedAt's ticks), one
# listing for them all
fn listDirTimes(path str) (str, i64)[] ? i64:
	r (str, i64)[] = []
	info = zeroBytes(600)   # a WIN32_FIND_DATAA: ftLastWriteTime at byte 20, the name at 44
	h = FindFirstFileA(cstr(path + "/*"), info)
	if h == -1: return systemError()
	going = true
	while going:
		n i64 = 0
		while info[44 + n] != 0:
			n += 1
		if not (n == 1 and info[44] == '.') and
			not (n == 2 and info[44] == '.' and info[45] == '.'):
			r.push((str(info[44..44 + n]), i64(info.u64le(20))))
		if not FindNextFileA(h, info):
			going = false
	FindClose(h)
	r
