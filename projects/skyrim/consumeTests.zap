# Eating, drinking and the effects that last (game/sim/consume.zap): the formulas on an actor of
# round numbers, then the inn's food and potions as the plugin defines them.

import game.sim
import papyrus

inn = "RiverwoodSleepingGiantInn"
orgnar = 0x1_3486

fn actorOfHundreds():
	a = sim.ActorState(npc = 7, race = 0, level = 1, values = {})
	for name in ["health", "magicka", "stamina"]:
		a.setBaseValue(name, 100.0)
	a

fn effectOf(value str, magnitude f32, duration f32, recover bool, peak bool):
	sim.TimedEffect(
		source = 1,
		effect = 2,
		value = value.copy(),
		magnitude,
		duration,
		recover,
		peak,
		shown = true,
		taperWeight = 0.0,
		taperCurve = 0.0,
		taperDuration = 0.0
	)

# why a consumption was refused, "" when it was not
fn refusal(r sim.Consumed ? str):
	match r:
		error: error
		_: ""

fn near(a f32, b f32):
	(a - b).abs() < 0.001

fn formNamed(w sim.GameWorld, name str):
	w.items.keys().find(w.items[it].name == name) ?? fail("no item {name}")

test "an effect with no duration changes the value once, at its start, and is gone":
	a = actorOfHundreds()
	a.damageValue("health", 60.0)
	a.addEffect(effectOf("health", 25.0, 0.0, false, false))
	expect a.valueOf("health") == 65.0 and a.effects.isEmpty
	a.addEffect(effectOf("stamina", -30.0, 0.0, false, false))
	expect a.valueOf("stamina") == 70.0 and a.effects.isEmpty

test "an effect that lasts gives its magnitude a second for its duration, the last update cut short":
	a = actorOfHundreds()
	a.damageValue("health", 80.0)
	a.addEffect(effectOf("health", 5.0, 10.0, false, false))
	expect a.valueOf("health") == 20.0 and a.effects.len == 1
	a.stepEffects(4.0)
	expect near(a.valueOf("health"), 40.0)
	a.stepEffects(4.0)
	expect near(a.valueOf("health"), 60.0) and a.effects[0].elapsed == 8.0
	a.stepEffects(4.0)
	expect near(a.valueOf("health"), 70.0) and a.effects.isEmpty

test "a harm takes the value down but never below what it has":
	a = actorOfHundreds()
	a.damageValue("stamina", 95.0)
	a.addEffect(effectOf("stamina", -30.0, 0.0, false, false))
	expect a.valueOf("stamina") == 0.0
	a.addEffect(effectOf("magicka", -10.0, 5.0, false, false))
	a.stepEffects(5.0)
	expect near(a.valueOf("magicka"), 50.0) and a.effects.isEmpty

test "a fortify raises the maximum while it lasts and gives it back, whatever its length":
	a = actorOfHundreds()
	a.addEffect(effectOf("health", 50.0, 60.0, true, false))
	expect a.valueOf("health") == 150.0 and a.baseValueOf("health") == 100.0
	a.stepEffects(59.0)
	expect a.valueOf("health") == 150.0 and a.effects.len == 1
	a.stepEffects(2.0)
	expect a.valueOf("health") == 100.0 and a.effects.isEmpty

test "of equal peak effects only the strongest holds, and the weaker takes over when it ends":
	a = actorOfHundreds()
	a.addEffect(effectOf("stamina", 20.0, 60.0, true, true))
	expect a.valueOf("stamina") == 120.0
	a.addEffect(effectOf("stamina", 30.0, 10.0, true, true))
	expect a.valueOf("stamina") == 130.0
	a.stepEffects(11.0)
	expect a.valueOf("stamina") == 120.0 and a.effects.len == 1
	a.stepEffects(50.0)
	expect a.valueOf("stamina") == 100.0 and a.effects.isEmpty
	a.addEffect(effectOf("stamina", 30.0, 60.0, true, true))
	a.addEffect(effectOf("stamina", 20.0, 90.0, true, true))
	expect a.valueOf("stamina") == 130.0
	a.stepEffects(61.0)
	expect a.valueOf("stamina") == 120.0

test "the magnitude tapers in the last seconds of an effect that has a taper":
	t = effectOf("health", -10.0, 1.0, false, false)
	t.taperWeight = 0.3
	t.taperCurve = 2.0
	t.taperDuration = 0.1
	expect t.currentMagnitude() == -10.0
	t.elapsed = 0.95
	expect near(t.currentMagnitude(), -0.75)

test "a dead actor loses its effects, a fortify given back":
	a = actorOfHundreds()
	a.addEffect(effectOf("magicka", 40.0, 60.0, true, false))
	a.addEffect(effectOf("health", 2.0, 60.0, false, false))
	a.kill()
	a.stepEffects(1.0)
	expect a.effects.isEmpty and a.valueOf("magicka") == 100.0

test "food is the food flag without the poison flag":
	_, vm = papyrus.archivesCellVm(inn) ?? return
	w = vm.rt.world
	expect w.items[w.formNamed("Red Apple")].isFood()
	potion = w.items[w.formNamed("Potion of Minor Healing")].copy()
	expect not potion.isFood() and not potion.isPoison()
	potion.flags = 0x2 | 0x2_0000
	expect not potion.isFood() and potion.isPoison()

test "Orgnar eats his apple and drinks his ale: the effects, the sounds and the food gone from his inventory":
	_, vm = papyrus.archivesCellVm(inn) ?? return
	w = vm.rt.world
	apple = w.formNamed("Red Apple")
	ale = w.formNamed("Ale")
	w.actors[orgnar].damageValue("health", 40.0)
	w.actors[orgnar].damageValue("stamina", 40.0)
	before = w.inventories[orgnar].countOf(apple)
	ate = w.consume(orgnar, apple) ?? fail
	expect ate.food and ate.sound == 0xC_AF94
	expect w.actors[orgnar].valueOf("health") == 75.0 - 40.0 + 2.0
	expect w.inventories[orgnar].countOf(apple) == before - 1
	drank = w.consume(orgnar, ale) ?? fail
	expect drank.food and drank.sound == 0xB_6435
	expect w.actors[orgnar].valueOf("stamina") == 60.0 - 40.0 + 15.0
	expect w.actors[orgnar].valueOf("staminaratemult") == -30.0
	lasting = w.activeEffects(orgnar).filter(.spell == ale)
	expect lasting.len == 1 and lasting[0].remaining == 30.0
	w.tickEffects(12.5)
	expect w.activeEffects(orgnar).filter(.spell == ale)[0].remaining == 17.5
	w.tickEffects(30.0)
	expect w.actors[orgnar].valueOf("staminaratemult") == 0.0
	expect w.activeEffects(orgnar).filter(.spell == ale).isEmpty
	expect not w.consume(orgnar, apple).refusal().isEmpty

test "the player's potion restores at once, a refused one costs nothing: a poison, a thing that is no food":
	_, vm = papyrus.archivesCellVm(inn) ?? return
	w = vm.rt.world
	minor = w.formNamed("Potion of Minor Healing")
	player = w.player
	w.actors[player].damageValue("health", 70.0)
	drank = w.consume(player, minor) ?? fail
	expect not drank.food and drank.sound == 0xB_6435 and w.actors[player].valueOf("health") == 55.0
	expect w.inventories[player].countOf(minor) == 4
	venom = w.items[minor].copy()
	venom.formId = 0xDEAD
	venom.flags = 0x2_0000
	w.items[0xDEAD] = venom.copy()
	w.inventories[player].addItem(0xDEAD, 1)
	expect w.consume(player, 0xDEAD).refusal().endsWith("not drunk") and
		w.inventories[player].countOf(0xDEAD) == 1
	expect not w.consume(player, 0xF).refusal().isEmpty
	expect not w.consume(player, 0x1234_5678).refusal().isEmpty

test "the player's fortify potions stack as peak effects, run their minute and show in the active effects":
	_, vm = papyrus.archivesCellVm(inn) ?? return
	w = vm.rt.world
	player = w.player
	fire = w.formNamed("Potion of Resist Fire")
	expect w.inventories[player].countOf(fire) == 2
	before = w.actors[player].valueOf("fireresist")
	w.consume(player, fire) ?? fail
	expect w.actors[player].valueOf("fireresist") == before + 20.0
	expect w.useFavorite(player, fire) == none
	expect w.actors[player].valueOf("fireresist") == before + 20.0 and
		w.actors[player].effects.len == 2
	expect w.activeEffects(player).filter(.spell == fire).len == 2
	w.tickEffects(59.0)
	expect w.actors[player].valueOf("fireresist") == before + 20.0
	w.tickEffects(2.0)
	expect w.actors[player].valueOf("fireresist") == before and w.actors[player].effects.isEmpty
