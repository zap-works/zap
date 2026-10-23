# pctl:a and its siblings, the parental controls (switchbrew: PCTL services): a factory whose
# service answers that no restriction is on, so a game is never held back.

fn parentalFactory(mut k Kernel, i i64, req Request, mut res Response):
	match req.command:
		0, 1: k.offer(res, "IParentalControlService")
		_: k.unwritten(i, req)

fn parentalControl(mut k Kernel, i i64, req Request, mut res Response):
	match req.command:
		1, 1001, 1002, 1013, 1014, 1015, 1016, 1017, 1046, 1047: pass
		1018, 1031: res.u8(0)
		_: k.unwritten(i, req)
