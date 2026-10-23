# Builds loaded into the running program (`zap build --loadable`, spec 13.1): another build of the
# same program's modules, more code beside them, mapped next to the program as a live build is
# (live.zap), its references to the state led to the program's, so its code reads and changes the
# program's module variables; then its main runs once. A program too large to build at once is
# built as several such builds.

extern loaded fn loadedMain()

# The build whose executable is at path (its .load file beside it) loaded and its main run; why
# not when it cannot be.
pub fn loadBuild(path str) ? str:
	image = readFile(path) ?? return "cannot read {path}"
	info = readFile("{path}.load") ?? return "cannot read {path}.load"
	p = sPtr(info)
	if info.len < 20 or not info.startsWith("ZLOD"): return "{path}.load is no loadable build's"
	if __ld64(p + 4) != gv(slotLayout):
		return "{path} lays out the state otherwise than this program (built from other sources)"
	count = __ld32(p + 16)
	if info.len < 20 + count * 8: return "{path}.load is cut short"
	base, size = liveImage(sPtr(image))
	if base == 0: return "no room for {path} within reach of the program"
	for k in 0..count:
		at = p + 20 + k * 8
		place = __ld32(at + 4)
		state = gv(slotModuleVariables) + (place & 0x7FFF_FFFF) if place >= 0x8000_0000
			else __globals() + place
		if not leadTo(base + __ld32(at), state): return "{path} lies out of reach of the state"
	liveRunnable(base, size)
	bindExtern(loadedMain, base + __ld32(p + 12))
	loadedMain()

# the 32-bit displacement at field led to target; false when it cannot reach it
fn leadTo(field i64, target i64) bool:
	rel = target - (field + 4)
	if rel < -2_147_483_648 or rel > 2_147_483_647: return false
	__st32(field, rel)
	true
