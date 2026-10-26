# The player's magic as the plugin has it: the records of spells, magic effects, projectiles and
# the effect art. Run from the repository root:
#
#   zap run projects/skyrim/magicInfo.zap --record Flames    every field of the record of this
#                                                            editor id (SPEL, MGEF, PROJ, EFSH...)
#   zap run projects/skyrim/magicInfo.zap --form 12FCD       the same by form id (hex)
#   zap run projects/skyrim/magicInfo.zap --spells           every spell with its cost, school,
#                                                            cast type and effects
#   zap run projects/skyrim/magicInfo.zap --shouts           every shout with its words, their
#                                                            spells and recoveries
#   zap run projects/skyrim/magicInfo.zap --settings fmagic  the game settings by name prefix
#   zap run projects/skyrim/magicInfo.zap --translations magic  the interface's texts naming a word
#   zap run projects/skyrim/magicInfo.zap --install D:/Data ...  another install

import skyrim
import skyrim.esm
import game.sim
import interface

fn hexOf(d u8[]):
	d.map("{it:02X}").join(" ")

fn printRecord(r esm.Record):
	print("{r.kind} {r.formId:08X}")
	for f in r.fields:
		body = r.body[f.at..f.at + f.size]
		text = ""
		if f.size > 1 and f.size < 80 and body[f.size - 1] == 0 and body[0] >= 32:
			text = "  \"{str(body[..f.size - 1])}\""
		print("  {f.tag} {f.size}: {body[..f.size.min(100)].hexOf()}{text}")

install = skyrim.openInstall(args.option("--install") ?? skyrim.defaultInstall) ?? fail
mut plugin = esm.openEsm(install.installPlugin("Skyrim.esm")) ?? fail
if args.option("--record") is name:
	for kind in ["SPEL", "MGEF", "PROJ", "EFSH", "ARTO", "ENCH"]:
		id = plugin.formByEditorId(kind, name) ?? continue
		if plugin.recordOf(id) is r: r.printRecord()
if args.option("--form") is hex:
	if plugin.recordOf(i64.parse("0x{hex}") ?? 0) is r: r.printRecord()
if args.option("--settings") is prefix:
	settings = plugin.gameSettings()
	for k in settings.keys().sorted():
		if k.startsWith(prefix.lower()): print("{k} = {settings[k]}")

fn spellLine(w sim.GameWorld, s sim.Spell):
	parts = s.effects.map(
		"{(w.magicEffects.get(.effect)?.editorId ?? "?")} flags {.magnitude} x{.duration} a{.area}"
	)
	"{s.formId:08X} {s.editorId} kind {s.kind} cost {s.cost} charge {s.chargeTime} cast {s.castDuration} school {s.school} {s.castType} {s.target} [{parts.join("; ")}]"

if "--spells" in args:
	names = install.readNames("Skyrim.esm") ?? fail
	w = sim.newWorld()
	for id in plugin.formsOfKind("SPEL"):
		w.learnSpell(plugin, names, id)
	for id in w.spells.keys().sorted():
		print(w.spellLine(w.spells[id]))
if "--shouts" in args:
	names = install.readNames("Skyrim.esm") ?? fail
	w = sim.newWorld()
	for id in plugin.formsOfKind("SHOU"):
		w.learnShout(plugin, names, id)
	for id in w.shouts.keys().sorted():
		s = w.shouts[id]
		words = s.words.map(
			"{.dragon}={.translation} {w.spells.get(.spell)?.editorId ?? "?"} {.recovery}"
		)
		print("{id:08X} {s.editorId} {s.name}: {words.join("; ")}")
if args.option("--translations") is word:
	for k, v in install.readTranslations():
		if word.lower() in k.lower() or word.lower() in v.lower(): print("{k} = {v}")
