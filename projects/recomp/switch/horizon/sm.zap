# sm:, the service manager (switchbrew: Services API): a client registers, then asks for services
# by name (8 bytes, NUL-padded) and gets a session to each. CMIF and TIPC number the same
# commands: 0 RegisterClient (Initialize), 1 GetServiceHandle, 2 RegisterService, 3
# UnregisterService.

fn serviceManager(mut k Kernel, req Request, mut res Response):
	match req.command:
		0: pass
		1:
			raw = req.arg(0, 8)
			name = []
			for b in 0..8:
				c = (raw >> (8 * b)) & 0xFF
				if c == 0: break
				name.push(u8(c))
			res.objects.push(k.newService(name.text()))
		_: k.log.push("sm: #{req.command}: not written")
