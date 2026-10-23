# acc:u0, the account service for applications (switchbrew: Account services): one user, whose
# id is a u128 (userId in its low word, 0 in its high one).

pub userId = 0x1_0001
userNickname = "Link"

# the user's ProfileBase (0x38 bytes): the id, when it was last edited, the nickname
fn profileBase():
	p u8[] = zeros(0x38)
	p.setU64le(0, u64(userId))
	p.setU64le(0x10, 1)
	for k, c in userNickname.bytes():
		p[0x18 + k] = c
	p

fn accountService(mut k Kernel, i i64, req Request, mut res Response):
	match req.command:
		0: res.u32(1)
		1: res.u8(1 if req.arg(0, 8) == userId and req.arg(8, 8) == 0 else 0)
		2, 3: req.receive(0).putBuffer(userIdBytes())
		4:
			res.u64(userId)
			res.u64(0)
		5: k.offer(res, "IProfile")
		100: pass
		101: k.offer(res, "IManagerForApplication")
		140: req.receive(0).putBuffer(userIdBytes())
		_: k.unwritten(i, req)

# the user's u128 id, as a list of users holds it
fn userIdBytes():
	b u8[] = zeros(16)
	b.setU64le(0, u64(userId))
	b

fn profile(mut k Kernel, i i64, req Request, mut res Response):
	match req.command:
		0:
			req.receive(0).putBuffer(zeros(0x80))
			res.bytes(profileBase())
		1: res.bytes(profileBase())
		10: res.u32(0)
		_: k.unwritten(i, req)

fn applicationAccountManager(mut k Kernel, i i64, req Request, mut res Response):
	match req.command:
		0: pass
		1: res.u64(0x00FF_EE00_0000_0001)
		_: k.unwritten(i, req)
