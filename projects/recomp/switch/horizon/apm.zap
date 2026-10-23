# apm, the performance manager (switchbrew: PTM services#apm): a session per client holding the
# performance configuration it asked for in each mode (0 handheld, 1 docked). The console is
# handheld.

performanceHandheld = 0
defaultConfiguration = 0x0001_0000

fn performanceManager(mut k Kernel, i i64, req Request, mut res Response):
	match req.command:
		0:
			s = k.subService(res, "apm ISession")
			loop 2:
				k.services[s].data.pushU32le(defaultConfiguration)
		1: res.u32(performanceHandheld)
		_: k.unwritten(i, req)

# the session's configurations are the four bytes at 4 * mode of its data
fn performanceSession(mut k Kernel, i i64, req Request, mut res Response):
	mode = req.arg(0, 4)
	if mode > 1 and req.command < 2: return res.fail(resultInvalidPerformanceMode)
	match req.command:
		0: k.services[i].data.setU32le(4 * mode, u32(req.arg(4, 4)))
		1: res.u32(k.services[i].data.u32le(4 * mode))
		2: pass
		_: k.unwritten(i, req)

# apm's Result for a mode that is not handheld or docked
resultInvalidPerformanceMode = 0x1F6
