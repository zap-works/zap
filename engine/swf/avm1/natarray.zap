# Array's natives (Ruffle's core/src/avm1/globals/array.rs): the elements of the array object
# itself, sort and sortOn with their options (CASEINSENSITIVE 1, DESCENDING 2, UNIQUESORT 4,
# RETURNINDEXEDARRAY 8, NUMERIC 16) and a compare function of the movie's.

# long: Array's methods, one arm each
fn arrayNative(prog Program, mut m Machine, name str, me Value, args Value[]) Value ? Thrown:
	if name == "Array": return Value.Obj(m.newArray(arrayArgs(args)))
	id = me.objectId() ?? return Value.Undefined
	if not m.isArray(id): return Value.Undefined
	match name:
		"push":
			for v in args:
				m.heap[id].items.push(v.copy())
			Value.Num(f64(m.heap[id].items.len))
		"pop": m.heap[id].items.pop() ?? .Undefined
		"shift":
			if m.heap[id].items.isEmpty: return Value.Undefined
			m.heap[id].items.remove(0)
		"unshift":
			for k in 0..args.len:
				m.heap[id].items.insert(k, args[k].copy())
			Value.Num(f64(m.heap[id].items.len))
		"splice": try prog.splice(m, id, args)
		"slice":
			n = m.heap[id].items.len
			start = sliceIndex(try prog.intArg(m, args, 0, 0), n)
			end = sliceIndex(try prog.intArg(m, args, 1, n), n)
			Value.Obj(m.newArray(m.heap[id].items[start..end.max(start)].map(.copy())))
		"join", "toString":
			sep = ","
			if name == "join" and arg(args, 0) != .Undefined:
				sep = try prog.textArg(m, args, 0)
			parts = []
			for v in m.heap[id].items.copy():
				parts.push("" if v.isNullish() else try prog.toText(m, v))
			Value.Str(parts.join(sep))
		"concat":
			out = m.heap[id].items.copy()
			for v in args:
				if v is Obj(other):
					if m.heap[other].kind is Array:
						out.extend(m.heap[other].items.copy())
						continue
				out.push(v.copy())
			Value.Obj(m.newArray(out))
		"reverse":
			m.heap[id].items.reverse()
			me.copy()
		"sort": try prog.sortArray(m, id, args)
		"sortOn": try prog.sortOn(m, id, args)
		_:
			m.missing("Array.{name}")
			Value.Undefined

# an index of slice: from the end when negative, kept in 0..n
fn sliceIndex(k i64, n i64):
	(k + n if k < 0 else k).clamp(0, n)

fn splice(prog Program, mut m Machine, id Handle<Obj>, args Value[]) Value ? Thrown:
	n = m.heap[id].items.len
	start = sliceIndex(try prog.intArg(m, args, 0, 0), n)
	count = (try prog.intArg(m, args, 1, n - start)).clamp(0, n - start)
	removed = []
	loop count:
		removed.push(m.heap[id].items.remove(start))
	for k in 2..args.len:
		m.heap[id].items.insert(start + k - 2, args[k].copy())
	Value.Obj(m.newArray(removed))

# sort(compare?, options?) or sort(options): an insertion sort, stable, the compare function's
# sign or the elements' text (or number with NUMERIC) deciding
fn sortArray(prog Program, mut m Machine, id Handle<Obj>, args Value[]) Value ? Thrown:
	compare = Value.Undefined
	options = 0
	if arg(args, 0) is Obj: compare = arg(args, 0)
	elif not args.isEmpty: options = try prog.intArg(m, args, 0, 0)
	if args.len > 1: options = try prog.intArg(m, args, 1, 0)
	items = m.heap[id].items.copy()
	keys = items.map(.copy())
	order = try prog.sortedOrder(m, keys, compare, options)
	sorted = order.map(items[it].copy())
	if (options & 8) != 0: return Value.Obj(m.newArray(order.map(Value.Num(f64(it)))))
	m.heap[id].items = sorted
	Value.Obj(id)

# sortOn(field, options): by a property of each element
fn sortOn(prog Program, mut m Machine, id Handle<Obj>, args Value[]) Value ? Thrown:
	field = try prog.textArg(m, args, 0)
	options = try prog.intArg(m, args, 1, 0)
	items = m.heap[id].items.copy()
	keys = []
	for v in items:
		keys.push(try prog.getMember(m, v, field))
	order = try prog.sortedOrder(m, keys, .Undefined, options)
	if (options & 8) != 0: return Value.Obj(m.newArray(order.map(Value.Num(f64(it)))))
	m.heap[id].items = order.map(items[it].copy())
	Value.Obj(id)

# the indices of the keys in sorted order
fn sortedOrder(
	prog Program,
	mut m Machine,
	keys Value[],
	compare Value,
	options i64
) i64[] ? Thrown:
	order i64[] = []
	for k in 0..keys.len:
		at = order.len
		while at > 0:
			c = try prog.compareKeys(m, keys[order[at - 1]], keys[k], compare, options)
			if c <= 0: break
			at -= 1
		order.insert(at, k)
	order

fn compareKeys(
	prog Program,
	mut m Machine,
	x Value,
	y Value,
	compare Value,
	options i64
) i64 ? Thrown:
	sign = -1 if (options & 2) != 0 else 1
	if compare is Obj:
		r = try prog.callValue(m, compare, .Undefined, [x.copy(), y.copy()], none)
		d = try prog.toNumber(m, r)
		return sign * (1 if d > 0.0 else -1 if d < 0.0 else 0)
	if (options & 16) != 0:
		p = try prog.toNumber(m, x)
		q = try prog.toNumber(m, y)
		return sign * (1 if p > q else -1 if p < q else 0)
	s = try prog.toText(m, x)
	t = try prog.toText(m, y)
	if (options & 1) != 0: return sign * s.lower().cmp(t.lower())
	sign * s.cmp(t)
