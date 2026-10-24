# An app's assets (`zap build --assets dir`: the files of dir in the APK under assets/): copied
# into the app's files dir at its first start, each once (one there of the same size stays), so
# the program finds them beside it as it finds what adb put there (app.zap).

extern "libandroid.so" fn AAssetManager_openDir(manager i64, dir str) i64
extern "libandroid.so" fn AAssetDir_getNextFileName(dir i64) i64
extern "libandroid.so" fn AAssetDir_close(dir i64)
extern "libandroid.so" fn AAssetManager_open(manager i64, name str, mode i64) i64
extern "libandroid.so" fn AAsset_getLength64(asset i64) i64
extern "libandroid.so" fn AAsset_getBuffer(asset i64) i64
extern "libandroid.so" fn AAsset_close(asset i64)

assetBuffer = 3   # AASSET_MODE_BUFFER: the asset whole in memory
mut assetsUnpacked = false

# the assets copied into dir (the app's files dir), those missing or of another size
fn unpackAssets(dir str):
	if assetsUnpacked: return
	assetsUnpacked = true
	manager = __ld64(gv(slotActivity) + 64)   # ANativeActivity's assetManager
	if manager == 0: return
	listing = AAssetManager_openDir(manager, "")
	if listing == 0: return
	loop:
		at = AAssetDir_getNextFileName(listing)
		if at == 0: break
		name = str(cBytes(at))
		unpackAsset(manager, name, "{dir}/{name}")
	AAssetDir_close(listing)

fn unpackAsset(manager i64, name str, path str):
	asset = AAssetManager_open(manager, name, assetBuffer)
	if asset == 0: return
	size = AAsset_getLength64(asset)
	if existingSize(path) != size:
		bytes = zeroBytes(size)
		from = AAsset_getBuffer(asset)
		if from != 0 and size > 0:
			__memcpy(__ld64(hdr(bytes)), from, size)
			_ = writeBytes(path, bytes)
	AAsset_close(asset)

# the file's size, -1 when there is none
fn existingSize(path str) i64:
	h = openForRead(path)
	if h == -1: return -1
	n = fileSize(h)
	CloseHandle(h)
	n
