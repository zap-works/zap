# An NPC put together as the game does from its record: below the head its outfit's armor addons
# and its race's skin where no armor covers it, at its weight; its head the baked FaceGen model
# when the install has it (every NPC of the base game), else its head parts morphed.

import skyrim
import skyrim.esm

# what an NPC looks like, beyond its models
pub type NpcLook:
	name str
	editorId str
	race str   # the race's editor id
	female bool
	weight f32   # 0 thin to 100 heavy
	hairColor esm.Color?
	skinTone Vec3?
	faceGeom str   # the baked head's archive key, "" when the install lacks it
	faceTint str   # the baked tint's archive key, "" when the install lacks it

# the plugin's file name ("Skyrim.esm"), which the FaceGen paths name
pub fn pluginName(plugin esm.Esm) str:
	parts = plugin.path.replace("\\", "/").split("/")
	parts[len - 1].copy()

fn editorIdOf(mut plugin esm.Esm, formId i64):
	r = plugin.recordOf(formId) ?? return ""
	esm.textOf(r.body, r.fields, "EDID")

# the CNAM color of a form (a hair color's, CLFM), none when there is none
pub fn colorOf(mut plugin esm.Esm, form i64) esm.Color?:
	r = try plugin.recordOf(form)
	at = try esm.dataOf(r.fields, "CNAM")
	esm.colorAt(r.body, at)

fn keyIfThere(i skyrim.Install, key str):
	key.copy() if i.installHas(key) else ""

pub fn npcLook(i skyrim.Install, mut plugin esm.Esm, names skyrim.Strings, npc Npc) NpcLook:
	file = plugin.pluginName()
	NpcLook(
		name = (names.texts.get(npc.nameId) ?? npc.editorId).copy(),
		editorId = npc.editorId.copy(),
		race = plugin.editorIdOf(npc.race),
		female = npc.female,
		weight = npc.weight,
		hairColor = plugin.colorOf(npc.hairColor),
		skinTone = npc.skinTone,
		faceGeom = i.keyIfThere(faceGeomKey(file, npc.faceNpc)),
		faceTint = i.keyIfThere(faceTintKey(file, npc.faceNpc))
	)

# The head parts the NPC wears, its own in place of its race's, or why the plugin cannot say.
pub fn npcHeadParts(mut plugin esm.Esm, npc Npc) esm.Record[] ? str:
	race = try plugin.needRecord(npc.race)
	plugin.chosenHeadParts(npc.headParts, race, npc.female)

# The models an NPC wears, read: the body's at its weight, then its head; or why one cannot be.
pub fn npcBodyParts(i skyrim.Install, mut plugin esm.Esm, npc Npc) BodyPart[] ? str:
	out = []
	armors = plugin.outfitArmors(npc.outfit)
	for w in try plugin.bodyModels(npc.race, npc.female, npc.skin, armors):
		out.push(try i.readBodyPart(w.slot, w.key, npc.weight / 100.0))
	geom = faceGeomKey(plugin.pluginName(), npc.faceNpc)
	if i.installHas(geom):
		out.push(try i.readBodyPart("FaceGen", geom, 1.0))
		return out
	weights = npc.faceMorphWeights(plugin.editorIdOf(npc.race))
	out.extend(try i.morphedHead(try plugin.npcHeadParts(npc), weights))
	out

# The models the actor a placed actor (ACHR) is of wears, read; or why one cannot be.
pub fn npcParts(i skyrim.Install, mut plugin esm.Esm, achr esm.Record) BodyPart[] ? str:
	npc = try plugin.npcOf(achr.achrBase())
	i.npcBodyParts(plugin, npc)

# The archive keys of what an NPC wears, for a copy of the files: its body's models (both ends of
# each weighted pair), its baked head and tint, its head parts' models; or why the plugin cannot
# say.
pub fn npcFileKeys(mut plugin esm.Esm, npc Npc) str[] ? str:
	out = []
	for w in try plugin.bodyModels(npc.race, npc.female, npc.skin, plugin.outfitArmors(npc.outfit)):
		out.extend(w.key.weightedKeys())
	file = plugin.pluginName()
	out.push(faceGeomKey(file, npc.faceNpc))
	out.push(faceTintKey(file, npc.faceNpc))
	out.extend(headModels(try plugin.npcHeadParts(npc)).map(.key.copy()))
	out
