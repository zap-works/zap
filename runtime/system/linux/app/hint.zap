# The app's pace told to the system's performance hints (ADPF, Android 13 on): the thread that
# shows the pictures named once with the time a picture has, then the work of each one reported
# (the thread's processor time since the last, its waits left out), so the system keeps the
# processor fast enough for that work instead of slowing it in the pauses between pictures, which
# makes a frame late and the sound break up.

extern "libandroid.so" fn APerformanceHint_getManager() i64
extern "libandroid.so" fn APerformanceHint_createSession(
	manager i64, threads u8[], count i64, targetNanos i64
) i64
extern "libandroid.so" fn APerformanceHint_updateTargetWorkDuration(session i64, nanos i64) i32
extern "libandroid.so" fn APerformanceHint_reportActualWorkDuration(session i64, nanos i64) i32

hintSdk = 33   # the hints' first Android
mut hintSession = 0
mut hintTried = false
mut hintTarget = 0   # the nanoseconds a picture has, as last told
mut workFrom = 0   # the thread's processor time when the last picture was shown

# A picture is about to be shown at `perSecond` pictures a second (0: not said): the work since
# the last reported.
fn reportPictureWork(perSecond f64):
	now = threadCycles()
	work = now - workFrom
	workFrom = now
	if perSecond <= 0.0: return
	target = i64(1_000_000_000.0 / perSecond)
	if not hintTried:
		hintTried = true
		if androidSdk() < hintSdk: return
		manager = APerformanceHint_getManager()
		if manager == 0: return
		thread = zeroBytes(4)
		thread.setU32le(0, u32(sysGettid()))
		hintSession = APerformanceHint_createSession(manager, thread, 1, target)
		hintTarget = target
		return
	if hintSession == 0: return
	if target != hintTarget:
		_ = APerformanceHint_updateTargetWorkDuration(hintSession, target)
		hintTarget = target
	if work > 0: _ = APerformanceHint_reportActualWorkDuration(hintSession, work)
