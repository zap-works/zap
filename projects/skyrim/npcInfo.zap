# Prints the NPCs of the Sleeping Giant Inn as the plugin makes them: who the cell places and who
# its packages bring, each with race, sex, outfit, head parts, FaceGen files, packages with their
# schedules and the package a new game runs at an hour; or one NPC (by editor id or name) worn and
# posed on the CPU, drawn from the front and the side.
#
#   zap run projects/skyrim/npcInfo.zap --inn [--hour 12] [--day 0] [--install dir]
#   zap run projects/skyrim/npcInfo.zap Orgnar [--png out.png [--head]] [--anim mt_idle
#       [--frame 0]] [--obj out.obj]

import skyrim
import skyrim.esm
import skyrim.actor
import game.sim

inn = "RiverwoodSleepingGiantInn"

fn editorIdOf(mut plugin esm.Esm, formId i64):
	r = plugin.recordOf(formId) ?? return "{formId:08X}"
	esm.textOf(r.body, r.fields, "EDID")

fn colorText(c esm.Color?):
	x = c ?? return "none"
	"({x.r} {x.g} {x.b})"

fn toneText(t Vec3?):
	x = t ?? return "none"
	"({x.x:.2} {x.y:.2} {x.z:.2})"

fn placeText(mut plugin esm.Esm, p actor.Place?):
	x = p ?? return ""
	kind = actor.locationKinds[x.kind] if x.kind >= 0 and x.kind < actor.locationKinds.len
		else "kind {x.kind}"
	form = "{x.form}" if x.kind == 5 else plugin.editorIdOf(x.form)
	", {kind} {form} radius {x.radius}"

fn packageLine(mut plugin esm.Esm, p actor.Package):
	conditions = "" if p.conditions.isEmpty
		else ", if {p.conditions.map(.conditionText()).join(" and ")}"
	"{p.editorId} [{p.template}: {p.procedures.join(" ")}] {p.schedule.scheduleText()}{plugin.placeText(p.location)}{conditions}"

fn printActor(
	i skyrim.Install,
	mut plugin esm.Esm,
	names skyrim.Strings,
	a sim.CellActor,
	hour f32,
	day i64
):
	npc = plugin.npcOf(a.npc) ?? return print("{a.npc:08X}: {error}")
	look = i.npcLook(plugin, names, npc)
	where = "placed {a.achr?.formId ?? 0:08X}" if a.achr != none
		else "visits by {a.visits.join(", ")}"
	print("{look.name} ({npc.editorId} {npc.formId:08X}), {where}")
	print("  {look.race} {"female" if look.female else "male"}, weight {look.weight:.0}, class {plugin.editorIdOf(npc.class)}, voice {plugin.editorIdOf(npc.voice)}, templates {npc.templates.map("{it:08X}").join(" ")}")
	print("  factions {npc.factions.map("{plugin.editorIdOf(.faction)} {.rank}").join(", ")}")
	print("  outfit {plugin.editorIdOf(npc.outfit)}: {plugin.outfitArmors(npc.outfit).map(plugin.editorIdOf(it)).join(", ")}")
	parts = plugin.npcHeadParts(npc) ?? []
	print(
		"  head parts {parts.map("{.headKind()} {esm.textOf(.body, .fields, "EDID")}").join(", ")}"
	)
	print("  hair color {colorText(look.hairColor)}, skin tone {toneText(look.skinTone)}, tint layers {npc.tints.len}")
	print("  facegeom {"yes" if look.faceGeom != "" else "no"}, facetint {"yes" if look.faceTint != "" else "no"}")
	packages = plugin.packagesOf(npc)
	for p in packages:
		print("  package {plugin.packageLine(p)}")
	match plugin.activePackageAtStart(packages, hour, day, a.location):
		p: print("  at {hour:.1}h of a new game: {p.editorId}")
		none: print("  at {hour:.1}h of a new game: no package")

fn findNpc(mut plugin esm.Esm, names skyrim.Strings, want str) i64?:
	lower = want.lower()
	ids = plugin.formsOfKind("NPC_")
	for id in ids:
		if plugin.editorIdOf(id).lower() == lower: return id
	for id in ids:
		r = plugin.recordOf(id) ?? continue
		if names.localText(r, "FULL").lower() == lower: return id
	none

fn drawNpc(i skyrim.Install, mut plugin esm.Esm, names skyrim.Strings, want str):
	id = plugin.findNpc(names, want) ?? fail("no actor {want}")
	npc = plugin.npcOf(id) ?? fail
	look = i.npcLook(plugin, names, npc)
	skeleton = i.readCharacterSkeleton() ?? fail
	body = i.npcBodyParts(plugin, npc) ?? fail
	print("{look.name}: {look.race} {"female" if look.female else "male"}, weight {look.weight:.0}")
	request = actor.figureRequest(args) ?? fail
	i.showFigure(body, skeleton, request, look.hairColor, look.skinTone) ?? fail

install = skyrim.openInstall(args.option("--install") ?? skyrim.defaultInstall) ?? fail
plugin = esm.openEsm(install.installPlugin("Skyrim.esm")) ?? fail
names = install.readNames("Skyrim.esm") ?? fail
args.options(
	[
		skyrim.installOption,
		ArgOption("--hour", true, "the hour of the day"),
		ArgOption("--day", true, "the day"),
		ArgOption("--png", true, "the picture to write"),
		ArgOption("--anim", true, "the animation to play"),
		ArgOption("--frame", true, "the animation's frame"),
		ArgOption("--obj", true, "the .obj file to write")
	]
)
words = args.positional()
if "--inn" in args:
	hour = f32.parse(args.option("--hour") ?? "12") ?? fail("--hour takes a number")
	day = i64.parse(args.option("--day") ?? "0") ?? fail("--day takes a number")
	for a in plugin.cellActors(inn) ?? fail("no {inn}"):
		install.printActor(plugin, names, a, hour, day)
elif not words.isEmpty:
	install.drawNpc(plugin, names, words[0])
else:
	fail("give --inn or an actor's editor id or name")
