# A small server-side game simulation: entities in a map, a grid, movement and combat per tick.

import fs

type Vec2:
	x i64
	y i64

	fn distanceTo(other Vec2):
		(x - other.x).abs() + (y - other.y).abs()

type Kind:
	Player
	Monster

type Entity:
	id i64
	kind Kind
	name str
	pos Vec2
	hp i64
	attack i64

type World:
	width i64
	height i64
	entities {i64: Entity}
	nextId i64
	log str[]

	fn addEntity(kind Kind, move name str, x i64, y i64, hp i64, attack i64):
		id = nextId
		nextId += 1
		entities[id] = Entity(id, kind, name, pos = Vec2(x, y), hp, attack)
		id

	fn inBounds(p Vec2):
		p.x >= 0 and p.y >= 0 and p.x < width and p.y < height

	fn walk(id i64, dx i64, dy i64):
		match entities.get(id):
			e:
				target = Vec2(x = e.pos.x + dx, y = e.pos.y + dy)
				if not inBounds(target):
					log.push("{e.name} bumps into the wall")
					return false
				moved = e.copy()
				moved.pos = target
				entities[id] = moved
				return true
			none: return false

	fn nearestEnemy(id i64):
		best i64? = none
		bestDist = 999_999
		match entities.get(id):
			me:
				for oid in entities.keys().sorted():   # in id order: a tie goes to the first
					other = entities[oid]
					if other.id == id or other.kind == me.kind: continue
					d = me.pos.distanceTo(other.pos)
					if d < bestDist:
						bestDist = d
						best = other.id
			none: return none
		best

	fn attack(attackerId i64, targetId i64):
		attacker = entities.get(attackerId)
		target = entities.get(targetId)
		match attacker:
			a: match target:
				t:
					if a.pos.distanceTo(t.pos) > 1:
						log.push("{a.name} is too far from {t.name}")
						return
					hurt = t.copy()
					hurt.hp -= a.attack
					log.push("{a.name} hits {t.name} for {a.attack}")
					if hurt.hp <= 0:
						log.push("{t.name} dies")
						entities.remove(targetId)
					else:
						entities[targetId] = hurt
				none: return
			none: return

	fn count(kind Kind):
		n = 0
		for e in entities.values():
			if e.kind == kind:
				n += 1
		n

fn stepTowards(start Vec2, goal Vec2):
	d = Vec2(x = 0, y = 0)
	if goal.x > start.x:
		d.x = 1
	elif goal.x < start.x:
		d.x = -1
	elif goal.y > start.y:
		d.y = 1
	elif goal.y < start.y:
		d.y = -1
	d

# One tick: every monster, in id order, walks toward the nearest player and attacks when
# adjacent.
fn tick(mut w World):
	for id in w.entities.keys().sorted():
		match w.entities.get(id):
			e:
				if e.kind != .Monster: continue
				targetId = w.nearestEnemy(id)
				match targetId:
					tid:
						match w.entities.get(tid):
							t:
								if e.pos.distanceTo(t.pos) <= 1:
									w.attack(id, tid)
								else:
									d = e.pos.stepTowards(t.pos)
									w.walk(id, d.x, d.y)
							none: continue
					none: continue
			none: continue

mut w = World(width = 8, height = 8, entities = {}, nextId = 1, log = [])
ana = w.addEntity(.Player, "Ana", 1, 1, 30, 7)
w.addEntity(.Monster, "Poring", 5, 1, 12, 3)
w.addEntity(.Monster, "Lunatic", 1, 6, 9, 2)

print(w.walk(ana, -5, 0))   # false: wall
print(w.walk(ana, 1, 0))   # true

for round in 1..6:
	w.tick()
	print("round {round}: players={w.count(.Player)} monsters={w.count(.Monster)}")
# the player fights back
match w.nearestEnemy(ana):
	enemy:
		w.attack(ana, enemy)
		w.attack(ana, enemy)
	none: print("no enemies")
for line in w.log:
	print(line)
match w.entities.get(ana):
	e: print("Ana hp={e.hp} at {e.pos.x},{e.pos.y}")
	none: print("Ana died")

test "each tick moves the entities and settles their fights":
	main()
	prints fs.readFile("tests/programs/gameLoop.expected") ?? ""
