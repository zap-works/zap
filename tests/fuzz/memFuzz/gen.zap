# The random statements of the memory fuzzer: the statement type, its generator and the forms it may use.

# the random numbers of the programs made, a sequence each run restarts from its seed
pub mut rng = Random(0)

type St:
	kind i64
	a i64
	b i64
	c i64
	x i64   # the forms of the operands, the statement, its exits
	y i64
	z i64
	lit str
	body St[]
	alt St[]

nStr = 4
nList = 3
pub mut scale = 1
pub mut openBugs = false

fn pick(n i64) i64:
	rng.next(0..=n - 1)

fn word() str:
	letters = "abcdefgh"
	out = []
	loop rng.next(1..=3):
		out.push(letters[pick(8)])
	str(move out)

fn cut(s str):
	s[..len.min(12)].copy()

# ---------- programs ----------

pub fn genBlock(depth i64, size i64) St[]:
	out = []
	loop size:
		out.push(genStmt(depth))
	out

fn genStmt(depth i64):
	# half the statements are of the kinds over temporaries (35 and up)
	kind = pick(35) if pick(2) == 0 else 35 + pick(10)
	if (kind == 24 or kind == 25) and depth >= 2:
		kind = 26 + pick(9)
	if kind == 25 and depth == 0:
		kind = 24
	if (kind == 40 or kind == 41) and depth == 0:
		kind = 35 + pick(5)   # break and continue only inside a loop
	if pick(6) == 0:
		kind = 45 + pick(2)   # module variables, values given away in nested expressions
	st = St(
		kind,
		a = pick(nStr),
		b = pick(nStr),
		c = pick(nStr),
		x = 0,
		y = 0,
		z = 0,
		lit = word(),
		body = [],
		alt = []
	)
	if kind == 45 or kind == 46:
		st.x = pick(5)
		if kind == 46 and (st.x == 2 or st.x == 4):
			st.a = pick(nList)   # a list on the left
	elif kind >= 35:
		st.pickForms(depth)
	if kind in [3, 4, 6, 7, 8, 12, 13, 15, 16, 17, 21, 23, 31]:
		st.a = pick(nList)   # a list on the left
	if kind in [4, 6, 7, 8, 13, 16, 17, 32]:
		st.b = pick(nList)   # a list on the right
	if kind == 31 or kind == 32:
		st.c = rng.next(0..=3)   # a count, a length
	if kind == 24:
		st.c = rng.next(1..=3) * scale   # the loop's count
		st.body = genBlock(depth + 1, rng.next(1..=4))
	if kind == 25:
		st.body = genBlock(depth + 1, rng.next(1..=3))
		st.alt = genBlock(depth + 1, rng.next(0..=2))
	st

# the forms of a statement over temporaries: ones the checker accepts, and outside an open hunt
# none that fails today for a known bug
fn pickForms(mut st St, depth i64):
	k = st.kind
	loop 1000:
		st.x = pick([9, 5, 4, 5, 6, 5, 5, 5, 3, 8][k - 35])
		st.y = pick([9, 10, 1, 1, 1, 1, 2, 1, 1, 6][k - 35])
		st.z = pick([3, 3, 1, 1, 3, 2, 6, 3, 3, 1][k - 35])
		if k == 39 and depth == 0:
			st.z = 0   # no break or continue outside a loop
		if k == 40:
			st.z += 1   # always leaves: continue or break
		if st.accepted() and (openBugs or not st.hitsOpenBug()): return
	fail("no forms for kind {k}")

# the operands of ?: and ??: places (s, r.name), windows into temporaries, owned temporaries
# (a call's result, a field or an element of a temporary, an interpolation) and a literal
fn isPlaceForm(f i64):
	f <= 1

fn isWindowForm(f i64):
	f == 2 or f == 3

fn isOwnedForm(f i64):
	f >= 4 and f <= 7

# whether the checker accepts the forms (it rejects a choice that would give a place away, and
# mixes of a borrowed and an owned value)
fn accepted(st St):
	k = st.kind
	x = st.x
	y = st.y
	if k == 35:
		same = isPlaceForm(x) and isPlaceForm(y) or
			not isPlaceForm(x) and not isWindowForm(x) and not isPlaceForm(y) and
			not isWindowForm(y)
		fieldLit = x == 1 and y == 8 or x == 8 and y == 1
		window = isWindowForm(x) and not isOwnedForm(y) or isWindowForm(y) and not isOwnedForm(x)
		return same or fieldLit or window
	if k == 36:
		if x == 0: return isOwnedForm(y) or y == 8 or y == 9
		if x == 3: return y != 1 and y != 9
		return y != 9
	if k == 44:
		return y != 5 or x == 2 or x == 4   # a reference only through a (ref str)[]
	true

# whether the statement fails today for a bug of the board's language cards (each kept in
# tests/memory/openbugs.zap.txt); the fuzzer leaves these out of hunts that are not open
fn hitsOpenBug(st St):
	false   # no bug is open

# what one statement reads and what it overwrites as a whole, for the variables a value can be
# given away from; top: the statement runs whenever the program does (not inside a loop or a
# branch), so its writes always happen
