# Files on Linux (`zap build --target linux`): each declaration takes the place of the one of
# the same name (the compiler's target.zap), over the runtime's Linux layer (runtime/core/linux/).

extern "syscall fchmodat" fn sysFchmodat(dir i64, path u8[], mode i64, flags i64) i64

pub fn canRun(path str) bool:
	not rt.failed(sysFchmodat(-100, rt.cstr(path), 0x1ED, 0))   # mode 0755

fn bytesAt(handle i64, at i64, n i64) u8[] ? Error:
	if rt.seekFile(handle, at) != at: return fsError(rt.systemError())
	buf = rt.zeroBytes(n)
	if rt.readFully(handle, buf, 0) < n: return Error.Ended
	buf
