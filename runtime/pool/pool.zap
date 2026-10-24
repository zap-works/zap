# Pool<T>: values at stable places, named by handles. `add` stores a value in a free place (one
# left by `remove`, else a new one at the end) and returns its handle; `remove` moves the value
# out; `get` reads it and `pool[h]` reads or changes it where it is. A handle is plain data that
# names a value without borrowing it: the handle of the MMO's entities and the index of an
# arena's nodes. Each place counts its removals (its generation, from 1: no handle is all zero,
# so a Handle<T>? is the handle alone, 0 for none), so a handle to a removed value finds nothing,
# even after `add` gives the place to another value.
#
# A removed place holds the empty value of T (all zero bytes: an empty str or list, a box or
# map with no block, none, a closure without environment), which every drop accepts, so the
# list of items is dropped like any other.

# The name of a value in a Pool<T>: its place and the generation of the place when it was added.
pub type Handle<T>:
	index n32
	gen n32

# a handle tells a removed value apart from its successor in the same place
pub type Pool<T>:
	items T[] = []
	gens n32[] = []
	alive bool[] = []
	free n32[] = []
	live n64 = 0

	# stores v and returns its handle
	mut fn add(move v T) Handle<T>:
		live += 1
		match free.pop():
			i:
				items[i] = v
				alive[i] = true
				return Handle<T>(index = i, gen = gens[i])
			none:
				items.push(v)
				alive.push(true)
				gens.push(1)
				return Handle<T>(index = n32(items.len - 1), gen = 1)

	# moves the value of h out of the pool; none when h names nothing
	mut fn remove(h Handle<T>) T?:
		if not contains(h): return none
		i = h.index
		alive[i] = false
		gens[i] += 1
		free.push(i)
		live = n64(live - 1)
		move items[i]

	# the value of h, borrowed; none when h names nothing
	fn get(h Handle<T>) ref T?:
		if not contains(h): return none
		items[h.index]

	# pool.get(h) where the program changes what it gives: the value of h to change in place;
	# none when h names nothing
	mut fn getMut(h Handle<T>) mut ref T?:
		if not contains(h): return none
		found = mut ref items[h.index]
		found

	# pool[h]: the value of h; the program stops when h names nothing
	fn index(h Handle<T>) ref T:
		if not contains(h):
			fail("the handle names no value of the pool")
		items[h.index]

	# pool[h] where it changes: the value of h; the program stops when h names nothing
	mut fn indexMut(h Handle<T>) mut ref T:
		if not contains(h):
			fail("the handle names no value of the pool")
		found = mut ref items[h.index]
		found

	# pool[h] in a walk over pool.handles() whose body removes nothing from the pool: h names a
	# value, or of a handle a pool[h] before found with nothing removed since: h names a value, so
	# its count is not checked (the checker writes it: compiler/ownership/poolwalk.zap)
	fn indexLive(h Handle<T>) ref T:
		items[h.index]

	mut fn indexLiveMut(h Handle<T>) mut ref T:
		found = mut ref items[h.index]
		found

	# pool.get(h) of a handle indexLive would take: the value, never none
	fn getLive(h Handle<T>) ref T?:
		items[h.index]

	mut fn getLiveMut(h Handle<T>) mut ref T?:
		found = mut ref items[h.index]
		found

	# the number of places, holding a value or removed: a walk over the handles whose body adds and
	# removes nothing steps over them with liveAt and handleAt (compiler/ownership/poolwalk.zap)
	fn placeCount() i64:
		items.len

	# whether place i holds a value
	fn liveAt(i i64) bool:
		alive[i]

	# the handle of the value at place i
	fn handleAt(i i64) Handle<T>:
		Handle<T>(index = n32(i), gen = gens[i])

	# h in pool: whether h names a value
	fn contains(h Handle<T>) bool:
		h.index < items.len and alive[h.index] and gens[h.index] == h.gen

	# the number of values
	fn len() n64:
		live

	fn isEmpty() bool:
		live == 0

	# the handles of the values, in the order of their places
	fn handles() Handle<T>[]:
		r Handle<T>[] = []
		for i in 0..items.len:
			if alive[i]:
				r.push(handleAt(i))
		r
