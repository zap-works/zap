# Choosing a perk in a skill's constellation, as the stats menu does (reference/exe/README.md,
# "Perks and their entry points"). Each skill's AVIF holds the nodes of its tree; a node names a
# perk, the first of a chain whose next records NNAM gives (each rank of a perk is a record of its
# own). The perk a node offers is the first perk of its chain the character does not have
# (0x1409790a0, 0x14097f8b0), and it can be chosen when the character has a perk point and the
# conditions of that perk's record hold for him (the skill's level, the perks before it, the
# character's level). Choosing takes the perk (Actor::AddPerk with rank 1) and a perk point
# (0x14097e820) and plays UISkillsPerkSelect2D.

import skyrim
import skyrim.esm

# the sound a chosen perk plays
pub perkSelectSound = "UISkillsPerkSelect2D"

# Learns the skill's perk tree and the perks of its nodes (with the chains they lead to) from the
# plugin; whether the skill has a tree.
pub fn learnSkillTree(
	mut w GameWorld,
	mut plugin esm.Esm,
	names skyrim.Strings,
	skill str
) bool:
	if w.skillTrees.get(skill) != none: return true
	for id in plugin.formsOfKind("AVIF"):
		r = plugin.recordOf(id) ?? continue
		if skillOfEditorId(esm.textOf(r.body, r.fields, "EDID")) != skill: continue
		tree = plugin.skillTreeOf(id) ?? continue
		for node in tree.nodes:
			at = node.perk
			guard = 0
			while at != 0 and guard < 16:
				p = w.learnPerk(plugin, names, at) ?? break
				at = p.next
				guard += 1
		w.skillTrees[skill.copy()] = tree
		return true
	false

# the node of the skill's tree with this index
pub fn nodeOf(w GameWorld, skill str, index i64) esm.SkillNode?:
	tree = try w.skillTrees.get(skill)
	n = try tree.nodes.find(.index == index)
	n.copy()

# The perk a node offers and how many of its chain the actor has: the first perk the actor does
# not have, none when it has them all (0x1409790a0).
pub fn nextInChain(w GameWorld, refId i64, node esm.SkillNode) (i64?, i64):
	at = node.perk
	owned = 0
	guard = 0
	while at != 0 and guard < 16:
		if not w.hasPerk(refId, at): return (at, owned)
		owned += 1
		at = (w.perks.get(at)?.next) ?? 0
		guard += 1
	(none, owned)

# why the player cannot choose the node's perk, none when he can (0x14097f8b0 and the perk points,
# 0x14097e710)
pub fn whyNotChoose(w GameWorld, skill str, index i64) str?:
	node = w.nodeOf(skill, index) ?? return "{skill} has no node {index}"
	if node.perk == 0: return "node {index} of {skill} offers no perk"
	if w.progress.perkPoints <= 0: return "no perk point to spend"
	next, _ = w.nextInChain(w.player, node)
	perk = next ?? return "the character has every rank of this perk"
	record = w.perks.get(perk) ?? return "the perk {perk:08X} is not known to the world"
	if not w.perkConditionsHold(record.conditions, w.player):
		return "the character does not meet the requirements of {record.editorId}"
	none

# The player chooses the perk of the node: he takes it and spends a perk point; why not when he
# cannot (0x1409790a0).
pub fn choosePerk(mut w GameWorld, skill str, index i64) str?:
	if w.whyNotChoose(skill, index) is why: return why
	node = w.nodeOf(skill, index) ?? return "no such node"
	next, _ = w.nextInChain(w.player, node)
	perk = next ?? return "no perk"
	w.addPerk(w.player, perk)
	w.progress.perkPoints -= 1
	w.record("perk {w.perks[perk].editorId} chosen, {w.progress.perkPoints} perk points left")
	none
