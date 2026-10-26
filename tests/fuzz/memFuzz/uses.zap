# What each statement reads and writes, for deciding which values may be moved away.

type Use:
	reads str[]
	writes str[]
	top bool

fn usesOf(st St, top bool):
	k = st.kind
	a = sv(st.a)
	b = sv(st.b)
	c = sv(st.c)
	la = lv(st.a)
	lb = lv(st.b)
	u = Use(reads = [], writes = [], top)
	if k == 0:
		u.writes = [a]
	elif k == 1 or k == 5:
		u.reads = [b]
		u.writes = [a]
	elif k in [2, 14, 19]:
		u.reads = [b, c]
		u.writes = [a]
	elif k in [3, 15, 31]:
		u.reads = [la, b]
	elif k in [4, 7, 8, 17]:
		u.reads = [lb]
		u.writes = [la]
	elif k == 6 or k == 13:
		u.reads = [lb]
	elif k in [9, 10, 28, 29, 33]:
		u.reads = [b]
	elif k == 16 or k == 32:
		u.reads = [lb]
		u.writes = [c if k == 16 else a]
	elif k == 18:
		u.reads = [a, b]
	elif k == 21:
		u.reads = [b, c]
		u.writes = [la]
	elif k == 22 or k == 26:
		u.reads = [b, c]
	elif k == 23:
		u.reads = [la]
	elif k in [11, 20, 30, 34]:
		u.writes = [a]
	elif k == 12:
		u.writes = [la]
	elif k == 27:
		u.reads = [b]
		u.writes = [a]
	elif k == 45:
		u.reads = [b] if st.x in [0, 2, 4] else []
		u.writes = [a] if st.x == 1 or st.x == 3 else []
	elif k == 46:
		u.reads = [b] if st.x == 2 or st.x == 4 else [a.copy(), b]
		u.writes = [la if st.x == 2 or st.x == 4 else a]
	elif k >= 35:
		# over temporaries: every variable the forms may read (a by ?:'s condition)
		u.reads = [a.copy(), b, c, lv(st.b % nList), lv(st.c % nList)]
		if k in [35, 36, 39, 44] or k == 37 and st.x != 2 or k == 38 and st.x != 3:
			u.writes = [lv(st.a % nList) if k == 44 and st.y == 2 else a]
	u

# the uses of every statement in the order emit visits them (a loop or branch, then its body)
fn flatten(sts St[], top bool, mut out Use[]):
	for st in sts:
		out.push(st.usesOf(top))
		flatten(st.body, false, out)
		flatten(st.alt, false, out)

# whether the variable is never read after statement i before a statement that always runs
# gives it a new value (the end of the program prints every variable)
fn deadAfter(flat Use[], i i64, v str):
	for j in (i + 1)..flat.len:
		if v in flat[j].reads: return false
		if flat[j].top and v in flat[j].writes: return true
	false

# the expression that gives away the value of variable v at statement i: the variable itself
# when nothing reads it again (it moves), a copy otherwise (and always inside a loop, whose next
# iteration may read it)
fn give(flat Use[], i i64, loops i64, move v str):
	if loops == 0 and deadAfter(flat, i, v): return v
	"{v}.copy()"

fn sv(i i64):
	"s{i}"

fn lv(i i64):
	"l{i}"

# returns the index in flat of the statement after the last one emitted
