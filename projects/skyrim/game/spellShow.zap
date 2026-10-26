# The player's spells shown in the scene: while a spell is held in a hand and the hands are up, the
# casting art of its effect (the light it gives the hand) over that hand; while it is cast, its
# projectile's model (a flame's fire along the way the stream goes, as long as it reaches) at the
# hand. The art is what the cell prepared of the spells (game/spellArt.zap), the hand where the
# casting pose holds it, approximated from the feet and the way the body faces (the arm's bones
# are not followed).

import math
import game.sim
import world

# where a hand is over the feet: its height, how far in front and to which side
handHeight f32 = 95.0
handReach f32 = 30.0
handSide f32 = 14.0
# the length of the flame model's stream, along its y, which the cast stretches to its reach
streamLength f32 = 190.0

# where a hand is (Z up)
fn handAt(p Player, left bool):
	h = p.heading
	side = Vec3(h.cos(), -h.sin(), 0.0) * (-handSide if left else handSide)
	p.feetOf() + Vec3(0.0, 0.0, handHeight) + facing(h) * handReach + side

# a model standing at `at` (Z up) facing `heading`, stretched along its y, in the cell's space
fn standAt(at Vec3, heading f32, stretch f32):
	yUp @ Mat4.translation(at) @ Mat4.rotationZ(-heading) @ Mat4.scaling(Vec3(1.0, stretch, 1.0))

# the effects of the spell, with their magic effects
fn effectsOf(w sim.GameWorld, form i64):
	s = w.spells.get(form) ?? return []
	s.effects.filter(w.magicEffects.get(.effect) != none).map(w.magicEffects[.effect].copy())

# the art of the record shown at `place`, when the scene has it
fn show(mut scene world.CellScene, form i64, place Mat4):
	if form == 0: return
	if scene.artOf(form) is art: scene.showArt(art, place)

# What the player's spells show this frame: the casting art over the hands that hold a spell with
# the hands up, the projectile of the spell being cast.
pub fn showSpells(s FightScene, mut scene world.CellScene, p Player):
	w = s.fight.w
	x = s.fight.fighters[s.player]
	if s.drawn:
		for left in [false, true]:
			for m in w.effectsOf(w.spellIn(x.refId, left)):
				scene.show(m.castingArt, p.handAt(left).standAt(p.heading, 1.0))
	if x.casting is c:
		stretch = (c.reach / streamLength).clamp(0.5, 3.0)
		for m in w.effectsOf(c.spell):
			scene.show(m.projectile, p.handAt(c.left).standAt(p.heading, stretch))
