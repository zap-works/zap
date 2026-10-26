# The combat of the Sleeping Giant Inn as the game computes it, headless (game/combat). Run from
# the repository root:
#
#   zap run projects/skyrim/combatInfo.zap --stats <name> [--vs <name>]   an actor's values, its
#       weapon's damage (against the other's armor)
#   zap run projects/skyrim/combatInfo.zap --fight <attacker> <target>    a fight of two actors
#   zap run projects/skyrim/combatInfo.zap --player-vs Orgnar [--weapon IronDagger]
#       the player attacking, with fists unless a weapon of its inventory is drawn
#   ... [--seconds 60] [--seed 1] [--install dir]

import skyrim
import skyrim.esm
import game
import game.sim
import game.combat

inn = "RiverwoodSleepingGiantInn"

fn fighterOrFail(f combat.Fight, name str):
	f.fighterNamed(name) ?? fail("no actor {name} in the inn ({f.fighters.map(.name).join(", ")})")

fn flagsText(x combat.Fighter):
	if x.essential: return "essential"
	if x.protected: return "protected"
	"mortal"

fn printStats(f combat.Fight, k i64, other i64?):
	x = f.fighters[k]
	a = f.w.actors[x.refId]
	s = f.w.settings
	print("{x.name} ({x.refId:08X}) level {a.level}, {x.flagsText()}")
	for name in ["health", "magicka", "stamina"]:
		print("  {name} {a.valueOf(name)}, regenerates {a.valueOf("{name.replace("health", "heal")}rate")}% a second")
	print("  skills {sim.skillNames.map("{it} {a.valueOf(it)}").join(", ")}")
	ai = x.ai
	print("  AIDT aggression {ai.aggression} confidence {ai.confidence} morality {ai.morality} mood {ai.mood} assistance {ai.assistance}")
	st = x.style
	print("  style {st.editorId}: offensive {st.offensive} defensive {st.defensive} circle {st.circle} fallback {st.fallback} bash {st.bash}")
	skill = a.valueOf(x.skill) if x.weapon != 0 else 0.0
	raw = s.weaponDamage(x.baseDamage, skill, x.player) if x.weapon != 0 else x.baseDamage
	print("  {x.weaponName}: base {x.baseDamage}, {x.skill} {skill}: damage {raw:.2} (shown {i64(raw.round())}), power {raw * s.strikeMultiplier(.Power, x.weapon == 0):.2} for {s.powerAttackStamina(x.weight):.0} stamina, reach {x.reach:.1}, speed {x.speed}")
	print("  sneak attack x{s.sneakMultiplier(x.animation)}; armor {x.armorRating} in {x.armorPieces} pieces: {s.armorReduction(x.armorRating, x.armorPieces) * 100.0:.1}% off")
	j = other ?? return
	t = f.fighters[j]
	off = s.armorReduction(t.armorRating, t.armorPieces)
	print("  against {t.name} (armor {t.armorRating}, {t.armorPieces} pieces): {combat.damageTaken(raw, off, 0.0):.2} a hit")

fn printFight(mut f combat.Fight, seconds f32):
	ran = f.run(seconds)
	for line in f.lines:
		print(line)
	print("after {ran:.2} s:")
	for x in f.fighters:
		print("  {x.name}: {x.mode}, health {f.health(x.refId):.1}")
	print("bounty to CrimeFactionWhiterun: {f.w.bountyOf(whiterun)}")

whiterun = 0x2_67EA

# draws the weapon of this editor id from the player's inventory
fn drawWeapon(mut plugin esm.Esm, mut w sim.GameWorld, names skyrim.Strings, editorId str):
	form = plugin.formByEditorId("WEAP", editorId) ?? fail("no weapon {editorId}")
	w.learnItem(plugin, names, form)
	if w.inventories[w.player].countOf(form) == 0: w.inventories[w.player].addItem(form, 1)
	w.inventories[w.player].equip(w.items, form, false) ?? fail

fn runTool():
	install = skyrim.openInstall(args.option("--install") ?? skyrim.defaultInstall) ?? fail
	plugin = esm.openEsm(install.installPlugin("Skyrim.esm")) ?? fail
	names = install.readNames("Skyrim.esm") ?? fail
	w = install.worldOfCell(plugin, names, inn) ?? fail
	if args.option("--weapon") is weapon: plugin.drawWeapon(w, names, weapon)
	seed = i64.parse(args.option("--seed") ?? "1") ?? fail("--seed takes a number")
	seconds = f32(f64.parse(args.option("--seconds") ?? "60") ?? fail("--seconds takes a number"))
	f = plugin.sceneFight(w, install.timingsOf() ?? fail, seed) ?? fail
	args.options(
		[
			skyrim.installOption,
			ArgOption("--weapon", true, "the weapon to draw"),
			ArgOption("--seed", true, "the fight's random seed"),
			ArgOption("--seconds", true, "how long the fight lasts"),
			ArgOption("--stats", true, "the fighter whose stats to print"),
			ArgOption("--vs", true, "the fighter it faces"),
			ArgOption("--player-vs", true, "the player against this fighter"),
			ArgOption("--fight", true, "the two fighters to run")
		]
	)
	words = args.positional()
	if args.option("--stats") is name:
		other i64? = none
		if args.option("--vs") is o: other = f.fighterOrFail(o)
		f.printStats(f.fighterOrFail(name), other)
	elif args.option("--player-vs") is name:
		f.engage(f.fighterOrFail("Player"), f.fighters[f.fighterOrFail(name)].refId)
		f.printFight(seconds)
	elif args.option("--fight") is attacker:
		if words.isEmpty: fail("--fight takes an attacker and a target")
		f.engage(f.fighterOrFail(attacker), f.fighters[f.fighterOrFail(words[0])].refId)
		f.printFight(seconds)
	else:
		fail("give --stats <name>, --fight <attacker> <target> or --player-vs <name>")

runTool()
