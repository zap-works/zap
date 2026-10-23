# The service objects behind IPC sessions, and the dispatch of a request to the one a session (or a
# domain's object) names. A service is known by its name (a port's, or an interface's such as
# IApplicationProxy); what its commands do is in a file of its family (sm.zap, ...), reached from
# `dispatch`. A command no file knows answers success with nothing and is noted, so a run shows
# what a game asks for that is not written.

pub type Service:
	name str
	domain bool = false
	objects {i64: i64} = {}   # a domain's object ids and the services they name
	nextObject i64 = 1
	data u8[] = []   # an object's own bytes (an IStorage's)
	path str = ""   # an object's place on the host (an IFile's, an IDirectory's)
	value i64 = 0   # an object's own number (a mode, an event, a position)

# the service of this name made, its index
pub fn newService(mut k Kernel, name str) i64:
	k.services.push(Service(name = name.copy()))
	k.services.len - 1

# A new object of the interface `name` given back by the request (a domain's id, or a moved
# handle); its index.
pub fn subService(mut k Kernel, mut res Response, name str) i64:
	s = k.newService(name)
	res.objects.push(s)
	s

fn sendSyncRequest(mut k Kernel, i i64, h i64, at i64):
	service = match k.object(h):
		Session(s): s
		_: return k.reply(i, resultInvalidHandle)
	domain = k.services[service].domain
	req = readRequest(at, domain)
	k.reply(i, resultSuccess)
	if req.kind == typeClose:
		k.objects.remove(h)
		return
	target = service
	if domain and req.domainCommand != 0:
		target = k.services[service].objects.get(req.domainObject) ?? service
		if req.domainCommand == 2:
			k.services[service].objects.remove(req.domainObject)
			return writeResponse(at, Response(), true, false)
	if k.traceCalls: k.log.push("  {k.services[target].name} #{req.command} ({req.kind})")
	res = Response()
	control = req.kind == typeControl or req.kind == typeControlWithContext
	if control: k.control(service, req, res)
	else: k.dispatch(target, req, res)
	if domain and not control:
		ids = []
		for o in res.objects:
			id = k.services[service].nextObject
			k.services[service].nextObject += 1
			k.services[service].objects[id] = o
			ids.push(id)
		res.objects = ids
	else:
		res.objects = res.objects.map(k.add(.Session(it)))
	writeResponse(at, res, domain and not control, req.kind >= 16)

# the control commands (switchbrew: IPC Marshalling#Control)
fn control(mut k Kernel, service i64, req Request, mut res Response):
	match req.command:
		0:
			k.services[service].domain = true
			k.services[service].objects[0] = service
			res.u32(0)
		2, 4: res.moved.push(k.add(.Session(service)))
		3: res.data.pushU16le(0x8000)
		_: res.result = 0xF601

# a request to service index i
fn dispatch(mut k Kernel, i i64, req Request, mut res Response):
	name = k.services[i].name.copy()
	match name:
		"sm:": k.serviceManager(req, res)
		_: k.log.push("{name} #{req.command}: not written")
