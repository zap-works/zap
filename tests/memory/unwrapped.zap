# A map or a box (an owned word) unwrapped from a result: a call's moves out of the temporary to
# the binding (`??`, `try`, a match's name), a place's is lent where it is; a Box where a result
# is wanted is that result's side as it is.

type Spot:
	x i64

fn frames(ok bool) {str: f32} ? str:
	if not ok: return "none"
	out {str: f32} = {}
	out["a"] = 0.5
	out

fn boxed(ok bool) Box<Spot> ? str:
	if not ok: return "none"
	Box(Spot(x = 7))

fn mapLeaves() i64 ? str:
	m = frames(true) ?? return error
	n = 0
	for name, time in m:
		n += name.len + i64(time * 2)
	n + m.keys().len

fn mapTried() i64 ? str:
	m = try frames(true)
	m.keys().len

fn mapsGiven():
	n = 0
	for ok in [false, true]:
		m = frames(ok) ?? continue
		n += m.keys().len
	fallback {str: f32} = {}
	fallback["z"] = 1.0
	a = frames(false) ?? fallback
	b = frames(true) ?? {}
	c = frames(true) ?? fail
	n + a.keys().len + b.keys().len + c.keys().len

fn boxLeaves() i64 ? str:
	b = boxed(true) ?? return error
	t = try boxed(true)
	b.x + t.x

fn fromPlaces():
	r = frames(true)
	m = r ?? return 0
	n = m.len + (r ?? fail("no")).len
	match r:
		v: n += v.keys().len
		error: n += error.len
	kept Box<Spot> ? str = Box(Spot(x = 4))
	b = kept ?? return 0
	n + b.x

test "a map or a box unwrapped from a call's result is the binding's own, a place's lent":
	print("{mapLeaves() ?? 0} {mapTried() ?? 0} {mapsGiven()} {boxLeaves() ?? 0} {fromPlaces()}")
	prints "3 1 4 14 7"

fn hostOf(given str?, fallback str) str:
	host = given ?? (fallback if fallback != "" else fail("no host"))
	host

test "an optional's fallback that is a choice with an arm that fails":
	print("{hostOf("a", "b")} {hostOf(none, "b")}")
	prints "a b"
