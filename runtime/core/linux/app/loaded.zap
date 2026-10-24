# An app's loaded builds (runtime/core/loaded.zap): the C library's functions a build calls are
# the process's, which the system's loader loaded with the app.

extern "libdl.so" fn dlsym(handle i64, name u8[]) i64

# the word at the address of the C library's function name, found among the process's libraries
# (RTLD_DEFAULT); whether there is one
fn bindLibrary(word i64, name str) bool:
	named = zeroBytes(name.len + 1)
	__memcpy(__ld64(__addr(named)), sPtr(name), name.len)
	found = dlsym(0, named)
	__st64(word, found)
	found != 0
