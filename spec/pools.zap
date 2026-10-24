# 4.6 Pools and handles
#
# A value named from many places (a player's target, a party's members) lives in a `Pool<T>`
# (`runtime/pool/pool.zap`); the places hold its `Handle<T>`, plain data that borrows nothing.
# `add(v)` stores a value and returns its handle; `remove(h)` moves the value out (`T?`, none when
# `h` names nothing); `get(h)` is a `ref T?` and `pool[h]` reads or changes the value in place;
# `h in pool`, `len` and `handles()` give presence, count and the live handles in order. Each place
# counts its removals (a `Handle<T>?` is 8 bytes, none its `n32` index's -1) and a
# handle carries the count of when it was made, so a handle to a removed value finds nothing even
# after the place is reused. A pool is freed at once; a pool nothing is removed from is an arena.

type Entity:
	name str
	hp i64

fn same<T Copy>(v T) T:
	v

test "a pool names its values by handles":
	pool = Pool<Entity>()
	a = pool.add(Entity(name = "orc", hp = 10))
	b = pool.add(Entity(name = "elf", hp = 7))
	c = pool.add(Entity(name = "imp", hp = 3))
	print("{a.index} {b.index} {c.index} {pool.len}")
	gone = pool.remove(b) ?? Entity(name = "", hp = 0)
	print("{gone.name} {pool.len} {b in pool} {pool.get(b) == none}")
	d = pool.add(Entity(name = "bat", hp = 1))
	print("{d.index} {b in pool} {d in pool} {pool.get(b) == none} {pool.remove(b) == none}")
	match pool.get(same(d)):
		e: print("{e.name} {e.hp}")
		none: print("none")
	total = 0
	for h in pool.handles():
		if pool.get(h) is e:
			total += e.hp
	print(total)
	names = Pool<str>()
	hs = []
	for i in 0..1000:
		hs.push(names.add("n{i}"))
	for i in 0..1000:
		if i % 2 == 0:
			names.remove(hs[i])
	print(names.len)
	for i in 0..500:
		names.add("again{i}")
	print("{names.len} {names.get(hs[0]) ?? "removed"} {names.get(hs[1]) ?? "removed"}")
	prints """
		0 1 2 3
		elf 2 false true
		1 false true true true
		bat 1
		14
		500
		1000 removed n1
		"""

test "handles of different pool types do not mix" refuses ArgumentTypeAt:
	type A:
		x i64
	type B:
		x i64
	mut pa = Pool<A>()
	mut pb = Pool<B>()
	h = pa.add(A(x = 1))
	_ = pb.add(B(x = 2))
	print(pb.get(h))

test "pool[h] reads and changes a value where it is, and so does an arm of pool.get(h)":
	pool = Pool<Entity>()
	h = pool.add(Entity(name = "orc", hp = 10))
	tags = Pool<str[]>()
	t = tags.add([])
	pool[h].hp += 1
	tags[t].push("new")
	print("{pool[h].hp} {tags[t]}")
	if pool.get(h) is mut e:
		e.hp = 50
	print(pool[h].hp)
	pool[h] = Entity(name = "imp", hp = 3)
	pool.remove(h)
	g = pool.add(Entity(name = "bat", hp = 3))
	print("{pool[g].hp} {pool.get(h)}")
	prints """
		11 ["new"]
		50
		3 none
		"""

test "pool[h] stops the program when h names nothing" stops Failure("the handle names no value of the pool"):
	type Entity:
		hp i64

	pool = Pool<Entity>()
	h = pool.add(Entity(hp = 1))
	_ = pool.remove(h)
	print(pool[h].hp)

# A handle known to name a value is not checked: `pool[h]` reads its place and `pool.get(h)` gives
# it. It is known in `for h in pool.handles():` whose body removes nothing from the pool, for the
# walk's own handle, and after a statement that always evaluates `pool[h]` (not on the right of
# `and`, `or` or `??`, in a match's arm or a lambda), `h` an immutable variable, until a statement
# that may remove from the pool. What may remove is judged by what the code says: the pool (a
# local's, not a module variable) is named only to index it, read it or `add` to it; nothing that
# holds it is named on its own, given on or called a method of; no function value is called, no
# `mut ref` is held when it becomes known, and in a method whose pool is a field of `self`, no bare
# call of another method is made. Otherwise each `pool[h]` is checked. A walk whose body adds
# nothing either builds no list of the handles: it steps over the pool's places, skipping the
# removed ones.

# orc and imp, the place of an elf removed between them
fn orcAndImp():
	pool = Pool<Entity>()
	pool.add(Entity(name = "orc", hp = 10))
	gone = pool.add(Entity(name = "elf", hp = 7))
	pool.add(Entity(name = "imp", hp = 3))
	pool.remove(gone)
	pool

test "a walk over pool.handles() reads and changes pool[h] where it is, adding as it goes":
	pool = orcAndImp()
	seen = 0
	for h in pool.handles():
		pool[h].hp += 1
		pool.add(Entity(name = "{pool[h].name}'s pet", hp = 1))
		for k in pool.handles():
			if k in pool:
				seen += pool[k].hp
	for h in pool.handles():
		print("{pool[h].name} {pool[h].hp}")
	print(seen)
	prints """
		orc 11
		orc's pet 1
		imp 4
		imp's pet 1
		32
		"""

test "a walk that removes from the pool still checks pool[h]" stops Failure("the handle names no value of the pool"):
	type Mob:
		hp i64

	pool = Pool<Mob>()
	_ = pool.add(Mob(hp = 1))
	for h in pool.handles():
		_ = pool.remove(h)
		print(pool[h].hp)

test "a walk whose pool's holder is changed by a method still checks pool[h]" stops Failure("the handle names no value of the pool"):
	type Mob:
		hp i64

	type World:
		mobs Pool<Mob>

	fn kill(mut w World, h Handle<Mob>):
		_ = w.mobs.remove(h)

	w = World(mobs = Pool<Mob>())
	_ = w.mobs.add(Mob(hp = 1))
	for h in w.mobs.handles():
		w.kill(h)
		print(w.mobs[h].hp)

test "a walk in a method whose bare call removes still checks pool[h]" stops Failure("the handle names no value of the pool"):
	type Mob:
		hp i64

	type World:
		mobs Pool<Mob>

		fn kill(h Handle<Mob>):
			_ = mobs.remove(h)

		fn sweep():
			for h in mobs.handles():
				kill(h)
				print(mobs[h].hp)

	w = World(mobs = Pool<Mob>())
	_ = w.mobs.add(Mob(hp = 1))
	w.sweep()

test "a walk with a mut ref to the pool still checks pool[h]" stops Failure("the handle names no value of the pool"):
	type Mob:
		hp i64

	pool = Pool<Mob>()
	_ = pool.add(Mob(hp = 1))
	other = mut ref pool
	for h in pool.handles():
		_ = other.remove(h)
		print(pool[h].hp)

test "a walk reads and changes the value pool.get(h) gives, stepping over the places":
	pool = orcAndImp()
	for h in pool.handles():
		if pool.get(h) is mut e:
			e.hp += 1
	names = []
	for h in pool.handles():
		if pool[h].hp > 10: continue
		names.push("{pool[h].name} {pool.get(h) == none}")
	print(names)
	prints """
		["imp false"]
		"""

test "a second pool[h] finds what the first found":
	pool = Pool<Entity>()
	h = pool.add(Entity(name = "orc", hp = 10))
	pool[h].hp += 1
	pool.add(Entity(name = "elf", hp = 7))
	print("{pool[h].name} {pool[h].hp}")
	if pool.get(h) is mut e:
		e.hp = 2
	print(pool[h].hp)
	prints """
		orc 11
		2
		"""

test "pool[h] after a removal is checked again" stops Failure("the handle names no value of the pool"):
	type Mob:
		hp i64

	pool = Pool<Mob>()
	h = pool.add(Mob(hp = 1))
	print(pool[h].hp)
	if pool[h].hp > 0:
		_ = pool.remove(h)
	print(pool[h].hp)

test "pool[h] on the right of and is not known after it" stops Failure("the handle names no value of the pool"):
	pool = Pool<str>()
	h = pool.add("orc")
	_ = pool.remove(h)
	print(h in pool and pool[h].len > 0)
	print(pool[h])
