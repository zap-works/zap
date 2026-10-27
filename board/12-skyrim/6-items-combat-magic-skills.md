---
size: XL
---
# Skyrim's combat, magic, stealth, consumables and skills follow the game's (milestone 10)

Everything the inn's mechanics do not hit is not modelled yet. Code is under
`projects/skyrim/game` and its subdirectories (`combat`, `stealth`); the tests are `combatTests.zap`,
`magicTests.zap`, `stealthTests.zap`, `consumeTests.zap`, `skillTests.zap` and `perkTests.zap`. The
executable's code is read from the export at `C:/tools/skyrim-decomp`
(`projects/recomp/tools/decompInfo.zap`). Each task is done when its rule is ported from the
executable and a test shows the game's numbers.

- [ ] combat AI: special attacks, block attack, backoff, the target selector's scoring (only its 1 s
  and 3 s timers exist), the flight decision (the confidence thresholds stay approximate),
  `CombatState`'s random confidence modifier (`fCombatConfidenceModifierMin` and `Max`), cover,
  flanking, and ranged and magic nodes. An Idle child's weight 1 in the behavior tree is an
  assumption to check
- [ ] magic is not drawn: the casting art's billboard glow and every particle system of the spell
  models (their birth rates are blends of the controller sequences, which the NIF loader does not
  play), the impact and hit effects, the light's shadow. The hand's light stands at an approximate
  place (feet, facing) because the arm's bones are not followed. Not modelled: summons, wards,
  invisibility and the rest of the archetypes, dual casting, charge time, perks, and the hands'
  magic for the NPCs
- [ ] stealth: the perks of detection, combat stealth points, race sizes, a weapon's own sound
  level, and the sneak animation when the prepared cast lacks the sneak clips (the walk's plays).
  Detection events: the explosions', impacts' and summons' events (there are no projectiles in
  flight or explosions), a weapon's sound level, where the executable sends a heard actor (its
  search package), the reaction of the hostile among the heard, and the events of NPC casters heard
  by NPCs
- [ ] eating and drinking: an ingredient eaten (first effect only); a poison applied to a weapon
  (the case is refused); the effects of other archetypes (absorb, cure, invisibility and others);
  the Alchemy skill and perks that scale a potion when it is brewed (a perk's entry points 0x1d,
  0x1e, 0x29 and 0x2a do change one drunk); the AI's choice to eat or drink (NPCs consume through
  the same call but no package calls it); the quest-item refusal ("You can not eat quest items");
  Survival mode hunger; the executable's rule at the end of a Fortify Health (read, its effect at
  low health unverified); effects carried between the menus' world and the fight's copy of the
  actors (the fight gets the values back, not the effects); addiction (`ENIT`'s addiction fields).
  An actor's (Orgnar's) use sound is not played, and the executable's site that plays it is not
  found
- [ ] skills and perks: the entry points the inn does not hit (critical hits, armor and resistance,
  detection 0x2f, 0x30, 0x39 and 0xf whose formulas take no world, lockpicking, smithing,
  enchanting, alchemy at the table); the leveled-list, spell and text functions; the
  constellations' 3D scene and a perk node's description card; the legendary skill reset; a skill's
  description card (`SetDescriptionCard`); the "Level up available." HUD reminder
  (`iLevelUpReminder`); lockpicking, smithing, enchanting and alchemy experience (the sites are
  listed in the "Skills, levels and the stats menu" section of `reference/exe/README.md`); the skill
  order of the constellations (the AVIF perk tree's, taken as the actor value order); a spell's cost
  taken from its record where the executable takes its costliest effect's (the same for one
  effect); the unarmed hit's Block experience when a weapon bashes; and the rare event the game
  fires on a skill increase (recorded as a line of `GameWorld.events`)
- [ ] the perks no inn mechanic hits (critical, armor, detection)
- [ ] load the Creation Club plugins (Survival's ALCH overrides), which are not loaded today
