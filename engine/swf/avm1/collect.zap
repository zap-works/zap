# The heap collected between frames, when no code runs: a mark from the roots (the globals and
# the built-in prototypes, the objects of the stage's nodes, the classes, the callbacks, the
# timers and the queue) through properties, prototypes, elements, functions' scope chains and
# boxed values, then every object and scope not reached removed from its pool, the places given to
# the next ones made and a handle to a removed one naming nothing. Every call makes an activation
# object and a scope, which this gives back.

# frees what the machine's code can no longer reach
pub fn collect(mut m Machine):
	marked = fill(m.heap.placeCount(), false)
	scopesMarked = fill(m.scopes.placeCount(), false)
	work = m.roots()
	while work.pop() is id:
		if id not in m.heap or marked[id.index]: continue
		marked[id.index] = true
		m.reach(id, work, scopesMarked)
	for h in m.heap.handles():
		if not marked[h.index]: m.heap.remove(h)
	for h in m.scopes.handles():
		if not scopesMarked[h.index]: m.scopes.remove(h)
	m.liveAfterCollect = m.heap.len

fn roots(m Machine):
	out = [m.globals, m.stageObject, m.keyListeners, m.mouseListeners]
	if m.focus is focused: out.push(focused)
	p = m.protos
	out.extend([p.object, p.function, p.array, p.string, p.number, p.boolean, p.clip, p.text,
		p.button, p.textFormat, p.rectangle, p.point, p.date, p.error])
	for link in m.nodeObjects:
		if link is l and l.node in m.stage.nodes: out.push(l.object)
	out.extend(m.classes.values())
	for c in m.callbacks.values():
		out.pushValue(c.me)
		out.pushValue(c.function)
	for t in m.intervals:
		out.pushValue(t.me)
		out.pushValue(t.function)
		for v in t.args:
			out.pushValue(v)
	out

fn pushValue(mut out Handle<Obj>[], v Value):
	if v is Obj(id): out.push(id)

# the objects and scopes one object holds, queued
fn reach(m Machine, id Handle<Obj>, mut work Handle<Obj>[], mut scopesMarked bool[]):
	o = m.heap.get(id) ?? return
	if o.proto is proto: work.push(proto)
	for name in o.order:
		p = o.props[name]
		work.pushValue(p.value)
		if p.getter is getter: work.push(getter)
		if p.setter is setter: work.push(setter)
	for v in o.items:
		work.pushValue(v)
	work.extend(o.interfaces)
	match o.kind:
		Function(f): m.reachScope(f.scope, work, scopesMarked)
		Boxed(v): work.pushValue(v)
		Super(me, base):
			work.push(me)
			work.push(base)
		_: pass

fn reachScope(m Machine, start Handle<Scope>, mut work Handle<Obj>[], mut scopesMarked bool[]):
	s Handle<Scope>? = start
	while s is at:
		if at not in m.scopes or scopesMarked[at.index]: break
		scopesMarked[at.index] = true
		work.push(m.scopes[at].object)
		s = m.scopes[at].parent
