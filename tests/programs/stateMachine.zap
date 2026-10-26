# A monster's behaviour as a state machine: enum states with data, transitions as a function
# that returns the next state, and a log of what happened each tick.
type State:
	Idle(ticks i64)
	Chasing(target str, distance i64)
	Attacking(target str)
	Fleeing(hp i64)

type Event:
	PlayerSeen(name str, distance i64)
	PlayerGone
	Hit(damage i64)
	Tick

fn stateName(s State):
	match s:
		Idle(t): "idle({t})"
		Chasing(name, d): "chasing {name} at {d}"
		Attacking(name): "attacking {name}"
		Fleeing(hp): "fleeing with {hp} hp"

# the old state is given to step, so its target moves on to the next state; a name seen in an
# event is copied, since the event list keeps its own
fn step(move s State, e Event, hp i64) State:
	match e:
		Hit(dmg):
			if hp < 10: return .Fleeing(hp)
		PlayerGone: return .Idle(0)
		PlayerSeen(name, d):
			match s:
				Fleeing(h): return .Fleeing(h)
				_:
					if d <= 1: return .Attacking(name.copy())
					return .Chasing(name.copy(), d)
		Tick: pass
	match move s:
		Idle(t): return .Idle(t + 1)
		Chasing(name, d):
			if d <= 1: return .Attacking(name)
			return .Chasing(name, d - 1)
		Attacking(name): return .Attacking(name)
		Fleeing(h): return .Fleeing(h)

mut s = State.Idle(0)
mut hp = 30
events = [
	Event.Tick,
	Event.Tick,
	Event.PlayerSeen("ana", 3),
	Event.Tick,
	Event.Tick,
	Event.Hit(12),
	Event.Tick,
	Event.Hit(15),
	Event.PlayerSeen("bo", 1),
	Event.PlayerGone
]
mut log = []
for e in events:
	if e is Hit(d):
		hp -= d
	s = step(s, e, hp)
	log.push(s.stateName())
for line in log:
	print(line)
print("hp {hp}")

test "the monster's state machine logs each tick's transition":
	main()
	prints """
	    idle(1)
	    idle(2)
	    chasing ana at 3
	    chasing ana at 2
	    chasing ana at 1
	    attacking ana
	    attacking ana
	    fleeing with 3 hp
	    fleeing with 3 hp
	    idle(0)
	    hp 3
	    """
