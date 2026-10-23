# What the executable says

Text derived from the player's own `SkyrimSE.exe` with REA (github.com/morluto/rea) over Ghidra
12.1.4, one section a theme, each fact with the address it was read at. Nothing of the game is
copied here: only names, numbers and shapes we need to write Zap. Addresses are the image's
(base 0x140000000) and hold only for this build.

| | |
|---|---|
| file | `C:/games/Skyrim Anniversary Edition/SkyrimSE.exe`, 37,910,440 bytes |
| sha256 | 2c9cb9d61f3721ffb43a234764fe112864a89f4d63579c31fd028a3720047679 |
| version | 1.7.104.0 (the PE version resource; the SE build 1.6.1170 was once assumed for this AE install) |
| format | PE32+ x86_64, no PDB (Ghidra's symbol lookup finds none: GUID ae3f5f99-472e-44ce-9d81-6030f9c7b5c3, age 1) |
| no Address Library | the ids of SKSE's Address Library do not apply; functions here are found by their strings, their settings and their RTTI |

How to read it: the whole analysis was exported once to text outside the repository, so no
disassembler needs to run again (`C:/tools/ghidra-scripts/ExportAll.java`, run headless by
`run-skyrim-export.cmd` there, which also keeps the Ghidra project `C:/tools/ghidra-projects/skyrim.gpr`):

| `C:/tools/skyrim-decomp/` | what |
|---|---|
| `functions/<1 MB block>.c` | the pseudocode of every function (175,999), each under `// ==== 0x<entry> <name> ====`, by address |
| `index.tsv` | entry, name, size, block of each function |
| `calls.tsv` | caller, callee, call site |
| `strings.tsv` | each defined string's address, the functions that read it, its text |
| `datarefs.tsv` | every reference from code to data: the address, the instruction, its function |

So a setting's readers are `awk -F'	' '$1=="<value address>"' datarefs.tsv` (the value is the
`SettingT`'s address plus 8, the settings sections' tables give it), a string's are in `strings.tsv`, a
function's body is the block's `// ==== 0x<entry>` section. REA (the MCP server, `REA_ANALYSIS_PROVIDER=ghidra`)
is for what the text cannot answer (bytes, decoded instructions).

Sections: each was one file of this directory named after its heading (`gmst-combat.md` is the
section "Game settings: combat (fCombat*)"), so an old reference such as
`reference/exe/gmst-combat.md`, or a mention of `menus.md` inside a section, reads as the section.
In order: the game settings, the ini settings, the classes, then the rest alphabetically by the old
file name.

| old file | section |
|---|---|
| `gmst-ai.md` | Game settings: AI, sandbox, detection, sneak, crime, dialogue |
| `gmst-combat.md` | Game settings: combat (fCombat*) |
| `gmst-floats-a-l.md` | Game settings: the other floats, A to L |
| `gmst-floats-m-z.md` | Game settings: the other floats, M to Z |
| `gmst-ints.md` | Game settings: the integers (i*, b*) |
| `gmst-magic.md` | Game settings: magic, spells, enchanting, alchemy |
| `gmst-strings.md` | Game settings: the strings (s*) |
| `ini-audio.md` | Ini settings: [Audio] |
| `ini-combat-animation.md` | Ini settings: [Combat], [Animation], [RagdollAnim], the IK sections, [HAVOK], [Verlet], [GamePlay] |
| `ini-controls-camera.md` | Ini settings: [Controls], [Camera], [VATS], [Cart], [MapMenu], [Menu] |
| `ini-display.md` | Ini settings: [Display] |
| `ini-general.md` | Ini settings: [General], [Archive], [Language], [Messages], [Papyrus], [SaveGame] and the rest without a section |
| `ini-interface.md` | Ini settings: [Interface] |
| `ini-pathfinding.md` | Ini settings: [Pathfinding] and navmesh |
| `ini-prefs.md` | Ini pref settings (SkyrimPrefs.ini's own class, INIPrefSettingCollection) |
| `ini-render.md` | Ini settings: [Water], [LOD], [Grass], [Trees], [Landscape], [Weather], [LightingShader], [Decals], [BudgetCaps] and the other render sections |
| `classes-actors.md` | Actors and the player (55 classes, 1 template classes left out) |
| `classes-animation.md` | Animation (the behavior graph) (224 classes, 5 template classes left out) |
| `classes-combat.md` | Combat (118 classes, 265 template classes left out) |
| `classes-dialogue-ai.md` | Dialogue, scenes, packages and AI (188 classes, 1 template classes left out) |
| `classes-havok.md` | Havok (the physics) (473 classes, 0 template classes left out) |
| `classes-items.md` | Items and inventory (39 classes, 5 template classes left out) |
| `classes-menus.md` | Menus and the UI (100 classes, 0 template classes left out) |
| `animation.md` | Animation: the names the executable uses with the behavior graph |
| `combat.md` | Combat: what the executable computes that the records do not say |
| `consume.md` | Eating, drinking and active effects in SkyrimSE.exe |
| `dialogue.md` | The dialogue: MenuTopicManager and the dialogue menu |
| `havok.md` | Havok: the collision filter the executable builds |
| `havok-solver.md` | Havok: the constraint solver (hk_2010.2.0-r1, SkyrimSE.exe 1.7.104) |
| `menus.md` | The menus: how the executable drives the Scaleform movies |
| `perks.md` | Perks and their entry points |
| `render-captures.md` | Render captures: what SkyrimSE.exe draws in the inn, read from RenderDoc |
| `skills.md` | Skills, levels and the stats menu |
| `stealth.md` | Stealth: sneaking, detection and pickpocketing |

## Game settings: AI, sandbox, detection, sneak, crime, dialogue

The value compiled into `SkyrimSE.exe` for each game setting (GMST) it knows: what the game uses when `Skyrim.esm` has no record of that name (the plugin's record wins). `game/sim/settings.zap` keeps the few the port reads; this is the whole table.

Read from the static `SettingT<GameSettingCollection>` objects in `.data` (24 bytes: the vtable, the value, the pointer to the name; the vtable's RTTI names the class), found by scanning `.data` for pointers to names and checked against REA's `read_bytes` at 0x1420d9078 (fShadowBiasScale:Display). The address is the object's; the value is decoded by the name's type letter (f float, i int, u unsigned, b bool, s string, r and a 32-bit colors).

| address | setting | value |
|---|---|---|
| 0x14209fd80 | fCrimeAlarmRespMult | 1.7 |
| 0x1420a8df0 | fCrimeDispAttack | -10.0 |
| 0x1420a8e08 | fCrimeDispMurder | -50.0 |
| 0x1420a8e68 | fCrimeDispPersonal | 2.0 |
| 0x1420a8e38 | fCrimeDispPickpocket | -25.0 |
| 0x1420a8e20 | fCrimeDispSteal | -0.5 |
| 0x1420a8e50 | fCrimeDispTresspass | -20.0 |
| 0x14209f408 | fCrimeFavorMult | 1.0 |
| 0x1420a8dd8 | fCrimeGoldSkillPenaltyMult | 0.1 |
| 0x1420a8d48 | fCrimeGoldSteal | 0.5 |
| 0x14209f450 | fCrimePersonalRegardMult | 1.0 |
| 0x14209f420 | fCrimeRegardMult | 0.25 |
| 0x14209f198 | fCrimeSoundBase | 1.0 |
| 0x14209f1b0 | fCrimeSoundMult | 1.0 |
| 0x14209f468 | fCrimeWitnessRegardMult | 0.25 |
| 0x1420a05a8 | fDetectionActionTimer | 1.2 |
| 0x14209f0f0 | fDetectionCombatNonTargetDistanceMult | 0.75 |
| 0x14209fa38 | fDetectionCommentTimer | 20.0 |
| 0x1420a44d0 | fDetectionEventExpireTime | 5.0 |
| 0x14209ee08 | fDetectionLargeActorSizeMult | 1.0 |
| 0x14209f0a8 | fDetectionLOSDistanceAngle | 60.0 |
| 0x14209f0c0 | fDetectionLOSDistanceMultExterior | 0.5 |
| 0x14209f0d8 | fDetectionLOSDistanceMultInterior | 0.75 |
| 0x1420a9330 | fDetectionNightEyeBonus | 3.0 |
| 0x14209ecb8 | fDetectionSneakLightMod | 0.0 |
| 0x14209f090 | fDetectionStateExpireTime | 30.0 |
| 0x14209f048 | fDetectionUpdateTimeMax | 2.0 |
| 0x14209f078 | fDetectionUpdateTimeMaxComplex | 5.0 |
| 0x14209f030 | fDetectionUpdateTimeMin | 1.0 |
| 0x14209f060 | fDetectionUpdateTimeMinComplex | 2.5 |
| 0x14209ee20 | fDetectionViewCone | 190.0 |
| 0x1420a7f98 | fPersAdmireAggr | -5.0 |
| 0x1420a7fb0 | fPersAdmireConf | 1.0 |
| 0x1420a7fc8 | fPersAdmireEner | -2.0 |
| 0x1420a8010 | fPersAdmireIntel | -1.0 |
| 0x1420a8040 | fPersAdmirePers | -1.0 |
| 0x1420a7fe0 | fPersAdmireResp | 2.0 |
| 0x1420a7ff8 | fPersAdmireStre | 1.0 |
| 0x1420a8028 | fPersAdmireWillp | -2.0 |
| 0x1420a81d8 | fPersBoastAggr | 10.0 |
| 0x1420a81f0 | fPersBoastConf | -2.0 |
| 0x1420a8208 | fPersBoastEner | -1.0 |
| 0x1420a8250 | fPersBoastIntel | 2.0 |
| 0x1420a8280 | fPersBoastPers | -2.0 |
| 0x1420a8220 | fPersBoastResp | 1.0 |
| 0x1420a8238 | fPersBoastStre | 1.0 |
| 0x1420a8268 | fPersBoastWillp | -1.0 |
| 0x1420a8118 | fPersBullyAggr | -10.0 |
| 0x1420a8130 | fPersBullyConf | 2.0 |
| 0x1420a8148 | fPersBullyEner | 1.0 |
| 0x1420a8190 | fPersBullyIntel | -1.0 |
| 0x1420a81c0 | fPersBullyPers | -2.0 |
| 0x1420a8160 | fPersBullyResp | -1.0 |
| 0x1420a8178 | fPersBullyStre | 2.0 |
| 0x1420a81a8 | fPersBullyWillp | 1.0 |
| 0x1420a8058 | fPersJokeAggr | 5.0 |
| 0x1420a8070 | fPersJokeConf | -1.0 |
| 0x1420a8088 | fPersJokeEner | 2.0 |
| 0x1420a80d0 | fPersJokeIntel | -2.0 |
| 0x1420a8100 | fPersJokePers | 1.0 |
| 0x1420a80a0 | fPersJokeResp | -2.0 |
| 0x1420a80b8 | fPersJokeStre | 1.0 |
| 0x1420a80e8 | fPersJokeWillp | 2.0 |
| 0x1420a09f8 | fSandboxBreakfastMax | 9.0 |
| 0x1420a09e0 | fSandboxBreakfastMin | 6.0 |
| 0x1420a08d8 | fSandboxCylinderBottom | -50.0 |
| 0x1420a08c0 | fSandboxCylinderTop | 150.0 |
| 0x1420a0a58 | fSandboxDinnerMax | 19.0 |
| 0x1420a0a40 | fSandboxDinnerMin | 18.0 |
| 0x1420a0aa0 | fSandboxDurationBase | 0.02 |
| 0x1420a0b18 | fSandboxDurationMultEatSitting | 0.75 |
| 0x1420a0b30 | fSandboxDurationMultEatStanding | 0.75 |
| 0x1420a0ae8 | fSandboxDurationMultFurniture | 2.0 |
| 0x1420a0b00 | fSandboxDurationMultIdleMarker | 1.0 |
| 0x1420a0ab8 | fSandboxDurationMultSitting | 2.0 |
| 0x1420a0ad0 | fSandboxDurationMultSleeping | 2.0 |
| 0x1420a0b48 | fSandboxDurationMultWandering | 0.5 |
| 0x1420a0c20 | fSandboxDurationRangeMult | 0.25 |
| 0x1420a0b60 | fSandboxEnergyMult | 0.05 |
| 0x1420a0bd8 | fSandboxEnergyMultEatSitting | -0.05 |
| 0x1420a0bf0 | fSandboxEnergyMultEatStanding | -0.05 |
| 0x1420a0ba8 | fSandboxEnergyMultFurniture | -0.1 |
| 0x1420a0bc0 | fSandboxEnergyMultIdleMarker | 0.05 |
| 0x1420a0b78 | fSandboxEnergyMultSitting | -0.1 |
| 0x1420a0b90 | fSandboxEnergyMultSleeping | -0.1 |
| 0x1420a0c08 | fSandboxEnergyMultWandering | 0.2 |
| 0x1420a0a28 | fSandboxLunchMax | 12.5 |
| 0x1420a0a10 | fSandboxLunchMin | 11.5 |
| 0x1420a0a88 | fSandboxMealDurationMax | 0.25 |
| 0x1420a0a70 | fSandboxMealDurationMin | 0.1 |
| 0x1420a09c8 | fSandboxSleepDurationMax | 10.0 |
| 0x1420a09b0 | fSandboxSleepDurationMin | 6.0 |
| 0x1420a0998 | fSandboxSleepStartMax | 1.0 |
| 0x1420a0980 | fSandboxSleepStartMin | 19.0 |
| 0x14209eca0 | fSneakActionMult | 1.0 |
| 0x14209ed48 | fSneakAlertMod | 0.2 |
| 0x14209fac8 | fSneakAmbushNonTargetMod | -0.25 |
| 0x14209fab0 | fSneakAmbushTargetMod | 2.5 |
| 0x1420a6f00 | fSneakAttackSkillUsageMelee | 20.0 |
| 0x1420a6ee8 | fSneakAttackSkillUsageRanged | 2.5 |
| 0x14209eb50 | fSneakBaseValue | -25.0 |
| 0x14209fa98 | fSneakCombatMod | -0.4 |
| 0x14209ee68 | fSneakDetectionSizeLarge | 1.5 |
| 0x14209ee50 | fSneakDetectionSizeNormal | 1.0 |
| 0x14209ee38 | fSneakDetectionSizeSmall | 0.5 |
| 0x14209ee80 | fSneakDetectionSizeVeryLarge | 2.0 |
| 0x14209edc0 | fSneakDistanceAttenuationExponent | 2.0 |
| 0x14209eb80 | fSneakEquippedWeightBase | 12.0 |
| 0x14209eb98 | fSneakEquippedWeightMult | 0.5 |
| 0x14209ed90 | fSneakExteriorDistanceMult | 2.0 |
| 0x14209eda8 | fSneakFlyingDistanceMult | 2.0 |
| 0x14209ec10 | fSneakLightExteriorMult | 1.0 |
| 0x14209ecd0 | fSneakLightMoveMult | 0.01 |
| 0x14209ebf8 | fSneakLightMult | 1.4 |
| 0x14209ece8 | fSneakLightRunMult | 0.2 |
| 0x14209eb68 | fSneakMaxDistance | 1500.0 |
| 0x1420adce0 | fSneakNoticeMin | -20.0 |
| 0x14209ed78 | fSneakPerceptionSkillMax | 90.0 |
| 0x14209ed60 | fSneakPerceptionSkillMin | 10.0 |
| 0x14209ebe0 | fSneakRunningMult | 2.0 |
| 0x14209ec88 | fSneakSizeBase | 20.0 |
| 0x14209ebb0 | fSneakSkillMult | 0.5 |
| 0x14209edf0 | fSneakSleepBonus | -0.5 |
| 0x14209ed30 | fSneakSleepMod | -0.2 |
| 0x14209ebc8 | fSneakSoundLosMult | 0.25 |
| 0x14209ec28 | fSneakSoundsMult | 1.6 |
| 0x14209edd8 | fSneakStealthBoyMult | 0.0 |
| 0x14209fd68 | iCrimeAlarmLowRecDistance | 2000 |
| 0x14209fd50 | iCrimeAlarmRecDistance | 4000 |
| 0x14209f1c8 | iCrimeCommentNumber | 2 |
| 0x1420a8e80 | iCrimeDaysInPrisonMod | 100 |
| 0x1420a0830 | iCrimeEnemyCoolDownTimer | 24 |
| 0x14209f3f0 | iCrimeFavorBaseValue | 0 |
| 0x1420a8d18 | iCrimeGoldAttack | 40 |
| 0x1420a8da8 | iCrimeGoldEscape | 100 |
| 0x1420a8d90 | iCrimeGoldMinValue | 10 |
| 0x1420a8d30 | iCrimeGoldMurder | 1000 |
| 0x1420a8d60 | iCrimeGoldPickpocket | 25 |
| 0x1420a8538 | iCrimeGoldStealHorse | 25 |
| 0x1420a8d78 | iCrimeGoldTrespass | 5 |
| 0x1420a8dc0 | iCrimeGoldWerewolf | 100 |
| 0x1420a8e98 | iCrimeMaxNumberofDaysinJail | 7 |
| 0x14209f438 | iCrimeRegardBaseValue | 0 |
| 0x1420a8eb0 | iCrimeValueAttackValue | 100 |
| 0x1420a8700 | iDialogueDispositionFriendValue | 50 |
| 0x14209f1e0 | iSneakSkillUseDistance | 1000 |
| 0x1420b2c18 | sCrimeTypeAttack | "Attack" |
| 0x1420b2c48 | sCrimeTypeEscape | "Escape Jail" |
| 0x1420b2c30 | sCrimeTypeMurder | "Murder" |
| 0x1420b2be8 | sCrimeTypePickpocket | "Pickpocket" |
| 0x1420b2bd0 | sCrimeTypeSteal | "Steal" |
| 0x1420b2c00 | sCrimeTypeTrespass | "Trespass" |
| 0x1420b2c60 | sCrimeTypeWerewolf | "Werewolf Transformation" |
| 0x1420af6d8 | sSneakAttack | "Sneak Attack on" |
| 0x1420add28 | sSneakCaution | "[CAUTION]" |
| 0x1420add40 | sSneakDanger | "[DANGER]" |
| 0x1420add10 | sSneakDetected | "[DETECTED]" |
| 0x1420adcf8 | sSneakHidden | "[HIDDEN]" |

## Game settings: combat (fCombat*)

The value compiled into `SkyrimSE.exe` for each game setting (GMST) it knows: what the game uses when `Skyrim.esm` has no record of that name (the plugin's record wins). `game/sim/settings.zap` keeps the few the port reads; this is the whole table.

Read from the static `SettingT<GameSettingCollection>` objects in `.data` (24 bytes: the vtable, the value, the pointer to the name; the vtable's RTTI names the class), found by scanning `.data` for pointers to names and checked against REA's `read_bytes` at 0x1420d9078 (fShadowBiasScale:Display). The address is the object's; the value is decoded by the name's type letter (f float, i int, u unsigned, b bool, s string, r and a 32-bit colors).

| address | setting | value |
|---|---|---|
| 0x1420a4a40 | fCombatAbsoluteMaxRangeMult | 1.5 |
| 0x1420a4148 | fCombatAcquirePickupAnimationDelay | 1.0 |
| 0x1420a4088 | fCombatAcquireWeaponAmmoMinimumScoreMult | 1.5 |
| 0x1420a4118 | fCombatAcquireWeaponAvoidTargetRadius | 256.0 |
| 0x1420a3f50 | fCombatAcquireWeaponCloseDistanceMax | 768.0 |
| 0x1420a3f38 | fCombatAcquireWeaponCloseDistanceMin | 256.0 |
| 0x1420a3fe0 | fCombatAcquireWeaponDisarmedAcquireTime | 0.5 |
| 0x1420a3fb0 | fCombatAcquireWeaponDisarmedDistanceMax | 2048.0 |
| 0x1420a3f98 | fCombatAcquireWeaponDisarmedDistanceMin | 512.0 |
| 0x1420a3fc8 | fCombatAcquireWeaponDisarmedTime | 2.0 |
| 0x1420a4130 | fCombatAcquireWeaponEnchantmentChargeMult | 3.0 |
| 0x1420a4010 | fCombatAcquireWeaponFindAmmoDistance | 384.0 |
| 0x1420a4058 | fCombatAcquireWeaponMeleeScoreMult | 0.5 |
| 0x1420a4070 | fCombatAcquireWeaponMinimumScoreMult | 1.5 |
| 0x1420a40a0 | fCombatAcquireWeaponMinimumTargetDistance | 384.0 |
| 0x1420a3f20 | fCombatAcquireWeaponRangedDistanceMax | 2048.0 |
| 0x1420a3f08 | fCombatAcquireWeaponRangedDistanceMin | 512.0 |
| 0x1420a4028 | fCombatAcquireWeaponReachDistance | 48.0 |
| 0x1420a3ff8 | fCombatAcquireWeaponScoreCostMult | 4096.0 |
| 0x1420a40d0 | fCombatAcquireWeaponScoreRatioMax | 5.0 |
| 0x1420a40e8 | fCombatAcquireWeaponSearchFailedDelay | 5.0 |
| 0x1420a4040 | fCombatAcquireWeaponSearchRadiusBuffer | 384.0 |
| 0x1420a4100 | fCombatAcquireWeaponSearchSuccessDelay | 15.0 |
| 0x1420a40b8 | fCombatAcquireWeaponTargetDistanceCheck | 256.0 |
| 0x1420a3f80 | fCombatAcquireWeaponUnarmedDistanceMax | 2048.0 |
| 0x1420a3f68 | fCombatAcquireWeaponUnarmedDistanceMin | 256.0 |
| 0x1420a4530 | fCombatActiveCombatantAttackRangeDistance | 512.0 |
| 0x1420a4518 | fCombatActiveCombatantLastSeenTime | 5.0 |
| 0x1420a1c40 | fCombatAdvanceInnerRadiusMax | 512.0 |
| 0x1420a1c28 | fCombatAdvanceInnerRadiusMid | 0.0 |
| 0x1420a1c10 | fCombatAdvanceInnerRadiusMin | 0.0 |
| 0x1420a1cb8 | fCombatAdvanceLastDamagedThreshold | 10.0 |
| 0x1420a5dc0 | fCombatAdvanceNormalAttackChance | 0.0 |
| 0x1420a1c88 | fCombatAdvanceOuterRadiusMax | 1024.0 |
| 0x1420a1c70 | fCombatAdvanceOuterRadiusMid | 512.0 |
| 0x1420a1c58 | fCombatAdvanceOuterRadiusMin | 256.0 |
| 0x1420a1cd0 | fCombatAdvancePathRetryTime | 1.0 |
| 0x1420a1ca0 | fCombatAdvanceRadiusStaggerMult | 0.0 |
| 0x1420a3098 | fCombatAimDeltaThreshold | 0.05 |
| 0x1420a30b0 | fCombatAimLastSeenLocationTimeLimit | 30.0 |
| 0x1420a30f8 | fCombatAimMeleeHighPriorityUpdateTime | 0.1 |
| 0x1420a30e0 | fCombatAimMeleeUpdateTime | 0.25 |
| 0x1420a3110 | fCombatAimProjectileBlockedTime | 1.5 |
| 0x1420a3128 | fCombatAimProjectileGroundMinRadius | 128.0 |
| 0x1420a3140 | fCombatAimProjectileRandomOffset | 16.0 |
| 0x1420a3158 | fCombatAimProjectileUpdateTime | 0.25 |
| 0x1420a30c8 | fCombatAimTrackTargetUpdateTime | 0.33 |
| 0x1420a0e78 | fCombatAngleTolerance | 1.0 |
| 0x1420a1688 | fCombatAnticipatedLocationCheckDistance | 32.0 |
| 0x1420a15b0 | fCombatAnticipateTime | 0.5 |
| 0x1420a3ef0 | fCombatApproachTargetSlowdownDecelerationMult | 10.0 |
| 0x1420a3e90 | fCombatApproachTargetSlowdownDistance | 96.0 |
| 0x1420a3ec0 | fCombatApproachTargetSlowdownUpdateTime | 0.05 |
| 0x1420a3ed8 | fCombatApproachTargetSlowdownVelocityAngle | 135.0 |
| 0x1420a3e78 | fCombatApproachTargetSprintStopMovingRange | 0.0 |
| 0x1420a3e60 | fCombatApproachTargetSprintStopRange | 768.0 |
| 0x1420a3ea8 | fCombatApproachTargetUpdateTime | 0.25 |
| 0x1420a4160 | fCombatAreaHoldPositionMinimumRadius | 256.0 |
| 0x1420a4190 | fCombatAreaStandardAttackedRadius | 8192.0 |
| 0x1420a41c0 | fCombatAreaStandardAttackedTime | 1000.0 |
| 0x1420a41f0 | fCombatAreaStandardCheckViewConeDistanceMax | 4096.0 |
| 0x1420a41d8 | fCombatAreaStandardCheckViewConeDistanceMin | 1024.0 |
| 0x1420a41a8 | fCombatAreaStandardFlyingRadiusMult | 2.0 |
| 0x1420a4178 | fCombatAreaStandardRadius | 4096.0 |
| 0x1420a1820 | fCombatAttackAllowedOverrunDistance | 128.0 |
| 0x1420a1928 | fCombatAttackAnimationDrivenDelayTime | 1.5 |
| 0x1420a1808 | fCombatAttackAnticipatedDistanceMin | -64.0 |
| 0x1420a18f8 | fCombatAttackChanceBlockingMultMax | 0.67 |
| 0x1420a18e0 | fCombatAttackChanceBlockingMultMin | 0.2 |
| 0x1420a1910 | fCombatAttackChanceBlockingSwingMult | 0.0 |
| 0x1420a17d8 | fCombatAttackChanceLastAttackBonus | 1.5 |
| 0x1420a17f0 | fCombatAttackChanceLastAttackBonusTime | 5.0 |
| 0x1420a1748 | fCombatAttackChanceMax | 1.0 |
| 0x1420a1730 | fCombatAttackChanceMin | 0.05 |
| 0x1420a1838 | fCombatAttackCheckTargetRangeDistance | 512.0 |
| 0x1420a1880 | fCombatAttackMovingAttackDistance | 32.0 |
| 0x1420a1898 | fCombatAttackMovingAttackReachMult | 0.9 |
| 0x1420a1868 | fCombatAttackMovingStrikeAngleMult | 1.5 |
| 0x1420a18c8 | fCombatAttackPlayerAnticipateMult | 0.5 |
| 0x1420a18b0 | fCombatAttackStationaryAttackDistance | 5.0 |
| 0x1420a1850 | fCombatAttackStrikeAngleMult | 0.67 |
| 0x1420a4620 | fCombatAvoidThreatsChance | 0.5 |
| 0x1420a1ec8 | fCombatBackoffChance | 0.25 |
| 0x1420a1ee0 | fCombatBackoffMinDistanceMult | 0.75 |
| 0x1420a1778 | fCombatBashChanceMax | 0.2 |
| 0x1420a1760 | fCombatBashChanceMin | 0.025 |
| 0x1420a57a8 | fCombatBashReach | 128.0 |
| 0x1420a1790 | fCombatBashTargetBlockingMult | 0.0 |
| 0x1420a5dd8 | fCombatBetweenAdvanceTimer | 2.0 |
| 0x1420a19b8 | fCombatBlockAttackChanceMax | 1.0 |
| 0x1420a19a0 | fCombatBlockAttackChanceMin | 0.0 |
| 0x1420a19e8 | fCombatBlockAttackReachMult | 1.5 |
| 0x1420a19d0 | fCombatBlockAttackStrikeAngleMult | 1.25 |
| 0x1420a1a18 | fCombatBlockChanceMax | 1.0 |
| 0x1420a1a00 | fCombatBlockChanceMin | 0.0 |
| 0x1420a1a30 | fCombatBlockChanceWeaponMult | 0.25 |
| 0x1420a1a48 | fCombatBlockMaxTargetRetreatVelocity | 128.0 |
| 0x1420a1ac0 | fCombatBlockStartDistanceMax | 192.0 |
| 0x1420a1aa8 | fCombatBlockStartDistanceMin | 32.0 |
| 0x1420a1af0 | fCombatBlockStopDistanceMax | 384.0 |
| 0x1420a1ad8 | fCombatBlockStopDistanceMin | 128.0 |
| 0x1420a1a90 | fCombatBlockTimeMax | 10000.0 |
| 0x1420a1a78 | fCombatBlockTimeMid | 8.0 |
| 0x1420a1a60 | fCombatBlockTimeMin | 4.0 |
| 0x1420a4ab8 | fCombatBoltStickDepth | 5.0 |
| 0x1420a7c20 | fCombatBoundWeaponDPSBonus | 100000.0 |
| 0x1420a6978 | fCombatBuffMaxTimer | 6.0 |
| 0x1420a6960 | fCombatBuffStandoffTimer | 3.0 |
| 0x1420a2c18 | fCombatCastConcentrationOffensiveMagicCastTimeMax | 10.0 |
| 0x1420a2c00 | fCombatCastConcentrationOffensiveMagicCastTimeMin | 4.0 |
| 0x1420a2be8 | fCombatCastConcentrationOffensiveMagicChanceMax | 1.0 |
| 0x1420a2bd0 | fCombatCastConcentrationOffensiveMagicChanceMin | 0.25 |
| 0x1420a2c48 | fCombatCastConcentrationOffensiveMagicWaitTimeMax | 2.5 |
| 0x1420a2c30 | fCombatCastConcentrationOffensiveMagicWaitTimeMin | 0.5 |
| 0x1420a2b58 | fCombatCastImmediateOffensiveMagicChanceMax | 0.75 |
| 0x1420a2b40 | fCombatCastImmediateOffensiveMagicChanceMin | 0.05 |
| 0x1420a2ba0 | fCombatCastImmediateOffensiveMagicHoldTimeAbsoluteMin | 0.1 |
| 0x1420a2b88 | fCombatCastImmediateOffensiveMagicHoldTimeMax | 1.5 |
| 0x1420a2b70 | fCombatCastImmediateOffensiveMagicHoldTimeMin | 0.5 |
| 0x1420a2bb8 | fCombatCastImmediateOffensiveMagicHoldTimeMinDistance | 256.0 |
| 0x1420a1718 | fCombatChangeProcessFaceTargetDistance | 256.0 |
| 0x1420a1df0 | fCombatCircleAngleMax | 90.0 |
| 0x1420a1dd8 | fCombatCircleAngleMin | 30.0 |
| 0x1420a1e08 | fCombatCircleAnglePlayerMult | 0.75 |
| 0x1420a1dc0 | fCombatCircleChanceMax | 0.75 |
| 0x1420a1da8 | fCombatCircleChanceMin | 0.0 |
| 0x1420a1e20 | fCombatCircleDistanceMax | 1024.0 |
| 0x1420a1eb0 | fCombatCircleDistantChanceMax | 0.75 |
| 0x1420a1e98 | fCombatCircleDistantChanceMin | 0.25 |
| 0x1420a1e50 | fCombatCircleMinDistanceMult | 0.5 |
| 0x1420a1e80 | fCombatCircleMinDistanceRadiusMult | 3.0 |
| 0x1420a1e68 | fCombatCircleMinMovementDistance | 64.0 |
| 0x1420a1e38 | fCombatCircleViewConeAngle | 150.0 |
| 0x1420a1ef8 | fCombatCloseRangeTrackTargetDistance | 768.0 |
| 0x1420a5130 | fCombatClusterUpdateTime | 1.0 |
| 0x1420a6918 | fCombatCollectAlliesTimer | 1.0 |
| 0x1420a51d8 | fCombatConfidenceModifierMax | 0.5 |
| 0x1420a51c0 | fCombatConfidenceModifierMin | -0.5 |
| 0x1420a26f0 | fCombatCoverAttackMaxWaitTime | 10.0 |
| 0x1420a24e0 | fCombatCoverAttackOffsetDistance | 16.0 |
| 0x1420a26d8 | fCombatCoverAttackTimeMax | 8.0 |
| 0x1420a26c0 | fCombatCoverAttackTimeMid | 4.0 |
| 0x1420a26a8 | fCombatCoverAttackTimeMin | 2.0 |
| 0x1420a2720 | fCombatCoverAvoidTargetRadius | 256.0 |
| 0x1420a2510 | fCombatCoverCheckCoverHeightMin | 64.0 |
| 0x1420a24f8 | fCombatCoverCheckCoverHeightOffset | 32.0 |
| 0x1420a24b0 | fCombatCoverEdgeOffsetDistance | 16.0 |
| 0x1420a24c8 | fCombatCoverLedgeOffsetDistance | 128.0 |
| 0x1420a4a88 | fCombatCoverMaxRangeMult | 1.5 |
| 0x1420a2528 | fCombatCoverMidPointMaxRangeBuffer | 256.0 |
| 0x1420a2600 | fCombatCoverMinimumActiveRange | 512.0 |
| 0x1420a25e8 | fCombatCoverMinimumRange | 768.0 |
| 0x1420a2540 | fCombatCoverObstacleMovedTime | 1.0 |
| 0x1420a25d0 | fCombatCoverRangeMaxActiveMult | 1.25 |
| 0x1420a25a0 | fCombatCoverRangeMaxBufferDistance | 768.0 |
| 0x1420a25b8 | fCombatCoverRangeMinActiveMult | 0.5 |
| 0x1420a2588 | fCombatCoverRangeMinBufferDistance | 512.0 |
| 0x1420a2498 | fCombatCoverReservationWidthMult | 2.0 |
| 0x1420a2630 | fCombatCoverSearchDistanceMax | 3072.0 |
| 0x1420a2618 | fCombatCoverSearchDistanceMin | 1536.0 |
| 0x1420a2708 | fCombatCoverSearchFailedDelay | 5.0 |
| 0x1420a2570 | fCombatCoverSecondaryThreatLastSeenTime | 5.0 |
| 0x1420a2558 | fCombatCoverSecondaryThreatMinDistance | 512.0 |
| 0x1420a2690 | fCombatCoverWaitLookOffsetDistance | 32.0 |
| 0x1420a2678 | fCombatCoverWaitTimeMax | 5.0 |
| 0x1420a2660 | fCombatCoverWaitTimeMid | 2.5 |
| 0x1420a2648 | fCombatCoverWaitTimeMin | 1.5 |
| 0x1420a4a58 | fCombatCurrentWeaponAbsoluteMaxRangeMult | 1.5 |
| 0x1420a6ed0 | fCombatDamageBonusMeleeSneakingMult | 5.0 |
| 0x1420a6eb8 | fCombatDamageBonusSneakingMult | 1.0 |
| 0x1420a4350 | fCombatDamageScale | 0.5 |
| 0x1420a5d00 | fCombatDeadActorHitConeMult | 2.0 |
| 0x1420a4e30 | fCombatDetectionDialogueIdleMaxElapsedTime | 10.0 |
| 0x1420a4e18 | fCombatDetectionDialogueIdleMinElapsedTime | 3.0 |
| 0x1420a4e00 | fCombatDetectionDialogueMaxElapsedTime | 3.0 |
| 0x1420a4de8 | fCombatDetectionDialogueMinElapsedTime | 1.0 |
| 0x1420a3968 | fCombatDetectionFleeingLostRemoveTime | 30.0 |
| 0x1420a3950 | fCombatDetectionLostCheckNoticedDistance | 256.0 |
| 0x1420a39b0 | fCombatDetectionLostRemoveDistance | 4096.0 |
| 0x1420a3998 | fCombatDetectionLostRemoveDistanceTime | 60.0 |
| 0x1420a3980 | fCombatDetectionLostRemoveTime | 30.0 |
| 0x1420a3938 | fCombatDetectionLostTimeLimit | 10.0 |
| 0x1420a39c8 | fCombatDetectionLowDetectionDistance | 4096.0 |
| 0x1420a39e0 | fCombatDetectionLowPriorityDistance | 2048.0 |
| 0x1420a3920 | fCombatDetectionNoticedDistanceLimit | 768.0 |
| 0x1420a3908 | fCombatDetectionNoticedTimeLimit | 10.0 |
| 0x1420a39f8 | fCombatDetectionVeryLowPriorityDistance | 4096.0 |
| 0x1420a4f50 | fCombatDialogueAllyKilledDistanceMult | 0.75 |
| 0x1420a4dd0 | fCombatDialogueAllyKilledMaxElapsedTime | 5.0 |
| 0x1420a4db8 | fCombatDialogueAllyKilledMinElapsedTime | 3.0 |
| 0x1420a4e48 | fCombatDialogueAttackDistanceMult | 0.33 |
| 0x1420a4ce0 | fCombatDialogueAttackMaxElapsedTime | 5.0 |
| 0x1420a4cc8 | fCombatDialogueAttackMinElapsedTime | 1.0 |
| 0x1420a4ed8 | fCombatDialogueAvoidThreatDistanceMult | 1.0 |
| 0x1420a4d70 | fCombatDialogueAvoidThreatMaxElapsedTime | 5.0 |
| 0x1420a4d58 | fCombatDialogueAvoidThreatMinElapsedTime | 3.0 |
| 0x1420a4e78 | fCombatDialogueBashDistanceMult | 0.33 |
| 0x1420a4ec0 | fCombatDialogueBleedoutDistanceMult | 0.75 |
| 0x1420a4d40 | fCombatDialogueBleedOutMaxElapsedTime | 5.0 |
| 0x1420a4d28 | fCombatDialogueBleedOutMinElapsedTime | 1.0 |
| 0x1420a4f20 | fCombatDialogueBlockDistanceMult | 0.33 |
| 0x1420a4ef0 | fCombatDialogueDeathDistanceMult | 1.0 |
| 0x1420a4ea8 | fCombatDialogueFleeDistanceMult | 1.0 |
| 0x1420a4da0 | fCombatDialogueFleeMaxElapsedTime | 5.0 |
| 0x1420a4d88 | fCombatDialogueFleeMinElapsedTime | 3.0 |
| 0x1420a4f08 | fCombatDialogueGroupStrategyDistanceMult | 1.0 |
| 0x1420a4e90 | fCombatDialogueHitDistanceMult | 0.5 |
| 0x1420a4e60 | fCombatDialoguePowerAttackDistanceMult | 0.5 |
| 0x1420a4f38 | fCombatDialogueTauntDistanceMult | 0.75 |
| 0x1420a4d10 | fCombatDialogueTauntMaxElapsedTime | 10.0 |
| 0x1420a4cf8 | fCombatDialogueTauntMinElapsedTime | 3.0 |
| 0x1420a4698 | fCombatDisarmedFindBetterWeaponInitialTime | 1.0 |
| 0x1420a4680 | fCombatDisarmedFindBetterWeaponTime | 2.5 |
| 0x1420a6f48 | fCombatDismemberedLimbVelocity | 10.0 |
| 0x1420a71e8 | fCombatDistance | 128.0 |
| 0x1420a7638 | fCombatDistanceMin | 400.0 |
| 0x1420a27c8 | fCombatDiveBombChanceMax | 1.0 |
| 0x1420a27b0 | fCombatDiveBombChanceMin | 0.0 |
| 0x1420a2750 | fCombatDiveBombOffsetPercent | 0.1 |
| 0x1420a2738 | fCombatDiveBombSlowDownDistance | 4096.0 |
| 0x1420a3680 | fCombatDodgeAccelerationMult | 10.0 |
| 0x1420a3710 | fCombatDodgeAcceptableThreatScoreMult | 0.5 |
| 0x1420a36b0 | fCombatDodgeAnticipateThreatTime | 2.0 |
| 0x1420a36f8 | fCombatDodgeBufferDistance | 64.0 |
| 0x1420a3740 | fCombatDodgeChanceMax | 1.0 |
| 0x1420a3728 | fCombatDodgeChanceMin | 0.0 |
| 0x1420a3698 | fCombatDodgeDecelerationMult | 10.0 |
| 0x1420a36e0 | fCombatDodgeMovingReactionTime | 0.25 |
| 0x1420a36c8 | fCombatDodgeReactionTime | 0.15 |
| 0x1420a7c08 | fCombatDPSBowSpeedMult | 0.2 |
| 0x1420a7bf0 | fCombatDPSMeleeSpeedMult | 1.0 |
| 0x1420a1670 | fCombatEffectiveDistanceAnticipateTime | 1.0 |
| 0x1420a6e88 | fCombatEnvironmentBloodChance | 0.75 |
| 0x1420a1d00 | fCombatFallbackChanceMax | 0.5 |
| 0x1420a1ce8 | fCombatFallbackChanceMin | 0.0 |
| 0x1420a1d30 | fCombatFallbackDistanceMax | 256.0 |
| 0x1420a1d18 | fCombatFallbackDistanceMin | 96.0 |
| 0x1420a1d60 | fCombatFallbackMaxAngle | 20.0 |
| 0x1420a1d48 | fCombatFallbackMinMovementDistance | 64.0 |
| 0x1420a1d90 | fCombatFallbackWaitTimeMax | 1.5 |
| 0x1420a1d78 | fCombatFallbackWaitTimeMin | 0.75 |
| 0x1420a3248 | fCombatFindAllyAttackLocationAllyRadius | 64.0 |
| 0x1420a3230 | fCombatFindAllyAttackLocationDistanceMax | 4096.0 |
| 0x1420a3218 | fCombatFindAllyAttackLocationDistanceMin | 256.0 |
| 0x1420a31d0 | fCombatFindAttackLocationAvoidTargetRadius | 384.0 |
| 0x1420a31b8 | fCombatFindAttackLocationDistance | 1024.0 |
| 0x1420a31e8 | fCombatFindAttackLocationKeyAngle | 5.0 |
| 0x1420a3200 | fCombatFindAttackLocationKeyHeight | 128.0 |
| 0x1420a4668 | fCombatFindBetterWeaponTime | 5.0 |
| 0x1420a31a0 | fCombatFindLateralAttackLocationDistance | 512.0 |
| 0x1420a3188 | fCombatFindLateralAttackLocationIntervalMax | 128.0 |
| 0x1420a3170 | fCombatFindLateralAttackLocationIntervalMin | 64.0 |
| 0x1420a4c80 | fCombatFiringArcStationaryTurnMult | 0.75 |
| 0x1420a2120 | fCombatFlankingAngleOffset | 22.5 |
| 0x1420a20d8 | fCombatFlankingAngleOffsetCostMult | 10.0 |
| 0x1420a2138 | fCombatFlankingAngleOffsetMax | 30.0 |
| 0x1420a2108 | fCombatFlankingDirectionDistanceMult | 0.2 |
| 0x1420a2198 | fCombatFlankingDirectionGoalAngleOffset | 15.0 |
| 0x1420a20c0 | fCombatFlankingDirectionOffsetCostMult | 5.0 |
| 0x1420a21b0 | fCombatFlankingDirectionRotateAngleOffset | 15.0 |
| 0x1420a20a8 | fCombatFlankingDistanceMax | 1024.0 |
| 0x1420a2090 | fCombatFlankingDistanceMin | 0.0 |
| 0x1420a21e0 | fCombatFlankingGoalAngleFarMax | 30.0 |
| 0x1420a2210 | fCombatFlankingGoalAngleFarMaxDistance | 1024.0 |
| 0x1420a21c8 | fCombatFlankingGoalAngleFarMin | 10.0 |
| 0x1420a21f8 | fCombatFlankingGoalAngleFarMinDistance | 384.0 |
| 0x1420a2228 | fCombatFlankingGoalAngleNear | 180.0 |
| 0x1420a22d0 | fCombatFlankingGoalCheckDistanceMax | 512.0 |
| 0x1420a22b8 | fCombatFlankingGoalCheckDistanceMin | 256.0 |
| 0x1420a22a0 | fCombatFlankingGoalCheckDistanceMult | 0.75 |
| 0x1420a20f0 | fCombatFlankingLocationGridSize | 32.0 |
| 0x1420a2300 | fCombatFlankingMaxTurnAngle | 45.0 |
| 0x1420a2318 | fCombatFlankingMaxTurnAngleGoal | 75.0 |
| 0x1420a2240 | fCombatFlankingNearDistance | 384.0 |
| 0x1420a22e8 | fCombatFlankingRotateAngle | 135.0 |
| 0x1420a2330 | fCombatFlankingStalkRange | 256.0 |
| 0x1420a2360 | fCombatFlankingStalkTimeMax | 10.0 |
| 0x1420a2348 | fCombatFlankingStalkTimeMin | 0.01 |
| 0x1420a2288 | fCombatFlankingStepDistanceMax | 384.0 |
| 0x1420a2270 | fCombatFlankingStepDistanceMin | 96.0 |
| 0x1420a2258 | fCombatFlankingStepDistanceMult | 0.33 |
| 0x1420a3500 | fCombatFleeAllyDistanceMax | 4096.0 |
| 0x1420a34e8 | fCombatFleeAllyDistanceMin | 1536.0 |
| 0x1420a3518 | fCombatFleeAllyRadius | 64.0 |
| 0x1420a3578 | fCombatFleeCoverMinDistance | 1024.0 |
| 0x1420a3590 | fCombatFleeCoverSearchRadius | 3072.0 |
| 0x1420a35c0 | fCombatFleeDistanceExterior | 4096.0 |
| 0x1420a35a8 | fCombatFleeDistanceInterior | 2048.0 |
| 0x1420a3548 | fCombatFleeDoorDistanceMax | 1024.0 |
| 0x1420a3560 | fCombatFleeDoorTargetCheckDistance | 128.0 |
| 0x1420a3668 | fCombatFleeInitialDoorRestrictChance | 0.75 |
| 0x1420a3638 | fCombatFleeLastDoorRestrictTime | 30.0 |
| 0x1420a3608 | fCombatFleeTargetAvoidRadius | 256.0 |
| 0x1420a3620 | fCombatFleeTargetGatherRadius | 3072.0 |
| 0x1420a3530 | fCombatFleeUseDoorChance | 0.33 |
| 0x1420a3650 | fCombatFleeUseDoorRestrictTime | 15.0 |
| 0x1420a1628 | fCombatFlightEffectiveDistance | 512.0 |
| 0x1420a1610 | fCombatFlightMinimumRange | 1536.0 |
| 0x1420a29d8 | fCombatFlyingAttackChanceMax | 1.0 |
| 0x1420a29c0 | fCombatFlyingAttackChanceMin | 0.0 |
| 0x1420a29f0 | fCombatFlyingAttackTargetDistanceThreshold | 256.0 |
| 0x1420a4b78 | fCombatFollowRadiusBase | 512.0 |
| 0x1420a4b60 | fCombatFollowRadiusMin | 512.0 |
| 0x1420a4b48 | fCombatFollowRadiusMult | 3.0 |
| 0x1420a4b30 | fCombatFollowSneakFollowRadius | 512.0 |
| 0x1420a5da8 | fCombatForwardAttackChance | 0.25 |
| 0x1420a68b8 | fCombatGiantCreatureReachMult | 2.0 |
| 0x1420a7cb0 | fCombatGrenadeBounceTimeMax | 5.0 |
| 0x1420a7c98 | fCombatGrenadeBounceTimeMin | 0.5 |
| 0x1420a28b8 | fCombatGroundAttackChanceMax | 1.0 |
| 0x1420a28a0 | fCombatGroundAttackChanceMin | 0.0 |
| 0x1420a28e8 | fCombatGroundAttackTimeMax | 15.0 |
| 0x1420a28d0 | fCombatGroundAttackTimeMin | 7.5 |
| 0x1420a51a8 | fCombatGroupCombatStrengthUpdateTime | 2.0 |
| 0x1420a1598 | fCombatGroupOffensiveMultMin | 0.1 |
| 0x1420a4c20 | fCombatGuardFollowBufferDistance | 384.0 |
| 0x1420a4bf0 | fCombatGuardRadiusMin | 384.0 |
| 0x1420a4bd8 | fCombatGuardRadiusMult | 1.5 |
| 0x1420a1310 | fCombatHealthRegenRateMult | 0.75 |
| 0x1420a16b8 | fCombatHideCheckViewConeDistanceMax | 4096.0 |
| 0x1420a16a0 | fCombatHideCheckViewConeDistanceMin | 1024.0 |
| 0x1420a35d8 | fCombatHideFailedTargetDistance | 128.0 |
| 0x1420a35f0 | fCombatHideFailedTargetLOSDistance | 384.0 |
| 0x1420a5ce8 | fCombatHitConeAngle | 35.0 |
| 0x1420a2870 | fCombatHoverAngleLimit | 35.0 |
| 0x1420a2858 | fCombatHoverAngleMax | 20.0 |
| 0x1420a2840 | fCombatHoverAngleMin | 0.0 |
| 0x1420a2828 | fCombatHoverChanceMax | 1.0 |
| 0x1420a2810 | fCombatHoverChanceMin | 0.0 |
| 0x1420a27f8 | fCombatHoverTimeMax | 15.0 |
| 0x1420a27e0 | fCombatHoverTimeMin | 7.5 |
| 0x1420a6948 | fCombatInTheWayTimer | 1.0 |
| 0x1420a33f8 | fCombatInventoryDesiredRangeScoreMultMax | 10.0 |
| 0x1420a33e0 | fCombatInventoryDesiredRangeScoreMultMid | 2.0 |
| 0x1420a33c8 | fCombatInventoryDesiredRangeScoreMultMin | 1.5 |
| 0x1420a34d0 | fCombatInventoryDualWieldScorePenalty | 0.01 |
| 0x1420a3428 | fCombatInventoryEquipmentMinScoreMult | 0.1 |
| 0x1420a34b8 | fCombatInventoryEquippedScoreBonus | 0.1 |
| 0x1420a3380 | fCombatInventoryMaxRangeEquippedBonus | 384.0 |
| 0x1420a3398 | fCombatInventoryMaxRangeScoreMult | 0.1 |
| 0x1420a3308 | fCombatInventoryMeleeEquipRange | 256.0 |
| 0x1420a3290 | fCombatInventoryMinEquipTimeBlock | 5.0 |
| 0x1420a3260 | fCombatInventoryMinEquipTimeDefault | 0.0 |
| 0x1420a32a8 | fCombatInventoryMinEquipTimeMagic | 3.0 |
| 0x1420a32c0 | fCombatInventoryMinEquipTimeShout | 3.0 |
| 0x1420a32d8 | fCombatInventoryMinEquipTimeStaff | 5.0 |
| 0x1420a32f0 | fCombatInventoryMinEquipTimeTorch | 5.0 |
| 0x1420a3278 | fCombatInventoryMinEquipTimeWeapon | 5.0 |
| 0x1420a33b0 | fCombatInventoryMinRangeScoreMult | 0.1 |
| 0x1420a3368 | fCombatInventoryMinRangeUnequippedBonus | 256.0 |
| 0x1420a3410 | fCombatInventoryOptimalRangePercent | 0.75 |
| 0x1420a34a0 | fCombatInventoryRangedScoreMult | 2.0 |
| 0x1420a3470 | fCombatInventoryResourceCurrentRequiredMult | 1.0 |
| 0x1420a3458 | fCombatInventoryResourceDesiredRequiredMult | 2.0 |
| 0x1420a3488 | fCombatInventoryResourceRegenTime | 3.0 |
| 0x1420a3320 | fCombatInventoryShieldEquipRange | 256.0 |
| 0x1420a3350 | fCombatInventoryShoutMaxRecoveryTime | 5.0 |
| 0x1420a3338 | fCombatInventoryTorchEquipRange | 256.0 |
| 0x1420a4c68 | fCombatInventoryUpdateTimer | 5.0 |
| 0x1420a4908 | fCombatIronSightsDistance | 512.0 |
| 0x1420a4920 | fCombatIronSightsRangeMult | 5.0 |
| 0x1420a4c50 | fCombatItemBuffTimer | 45.0 |
| 0x1420a4c38 | fCombatItemRestoreTimer | 30.0 |
| 0x1420a6f78 | fCombatKillMoveDamageMult | 10.0 |
| 0x1420a29a8 | fCombatLandingAvoidActorRadius | 64.0 |
| 0x1420a2990 | fCombatLandingSearchDistance | 6000.0 |
| 0x1420a2978 | fCombatLandingZoneDistance | 6000.0 |
| 0x1420a6900 | fCombatLineOfSightTimer | 0.25 |
| 0x1420a4c08 | fCombatLocationTargetRadiusMin | 10.0 |
| 0x1420a5208 | fCombatLowFleeingTargetHitPercent | 0.25 |
| 0x1420a5220 | fCombatLowMaxAttackDistance | 2048.0 |
| 0x1420a51f0 | fCombatLowTargetHitPercent | 0.5 |
| 0x1420a2f00 | fCombatMagicArmorDistanceMax | 512.0 |
| 0x1420a2ee8 | fCombatMagicArmorDistanceMin | 256.0 |
| 0x1420a2ed0 | fCombatMagicArmorMinCastTime | 15.0 |
| 0x1420a2eb8 | fCombatMagicBoundItemDistance | 1024.0 |
| 0x1420a2a98 | fCombatMagicBuffDuration | 30.0 |
| 0x1420a2e58 | fCombatMagicCloakDistanceMax | 384.0 |
| 0x1420a2e40 | fCombatMagicCloakDistanceMin | 128.0 |
| 0x1420a2e28 | fCombatMagicCloakMinCastTime | 5.0 |
| 0x1420a2b10 | fCombatMagicConcentrationAimVariance | 0.0 |
| 0x1420a2b28 | fCombatMagicConcentrationFiringArcMult | 1.5 |
| 0x1420a2a50 | fCombatMagicConcentrationMinCastTime | 2.0 |
| 0x1420a2ae0 | fCombatMagicConcentrationScoreDuration | 3.0 |
| 0x1420a2a20 | fCombatMagicDefaultLongDuration | 30.0 |
| 0x1420a2a08 | fCombatMagicDefaultMinCastTime | 1.0 |
| 0x1420a2a38 | fCombatMagicDefaultShortDuration | 15.0 |
| 0x1420a2df8 | fCombatMagicDisarmDistance | 256.0 |
| 0x1420a2e10 | fCombatMagicDisarmRestrictTime | 30.0 |
| 0x1420a2fd8 | fCombatMagicDrinkPotionWaitTime | 3.0 |
| 0x1420a2ac8 | fCombatMagicDualCastChance | 0.33 |
| 0x1420a2ab0 | fCombatMagicDualCastInterruptTime | 2.5 |
| 0x1420a2af8 | fCombatMagicImmediateAimVariance | 0.5 |
| 0x1420a2ea0 | fCombatMagicInvisibilityDistance | 1024.0 |
| 0x1420a2e88 | fCombatMagicInvisibilityMinCastTime | 15.0 |
| 0x1420a1328 | fCombatMagickaRegenRateMult | 0.75 |
| 0x1420a2e70 | fCombatMagicLightMinCastTime | 10.0 |
| 0x1420a2c60 | fCombatMagicOffensiveMinCastTime | 3.0 |
| 0x1420a2f90 | fCombatMagicParalyzeDistance | 384.0 |
| 0x1420a2f78 | fCombatMagicParalyzeMinCastTime | 2.0 |
| 0x1420a2fa8 | fCombatMagicParalyzeRestrictTime | 30.0 |
| 0x1420a2a68 | fCombatMagicProjectileFiringArc | 30.0 |
| 0x1420a2f48 | fCombatMagicReanimateDistance | 1024.0 |
| 0x1420a2f30 | fCombatMagicReanimateMinCastTime | 15.0 |
| 0x1420a2f60 | fCombatMagicReanimateRestrictTime | 30.0 |
| 0x1420a2de0 | fCombatMagicStaggerDistance | 256.0 |
| 0x1420a2d08 | fCombatMagicSummonMinCastTime | 15.0 |
| 0x1420a2d20 | fCombatMagicSummonRestrictTime | 30.0 |
| 0x1420a2a80 | fCombatMagicTacticalDuration | 30.0 |
| 0x1420a2f18 | fCombatMagicTargetEffectMinCastTime | 10.0 |
| 0x1420a2cd8 | fCombatMagicWardAttackRangeDistance | 384.0 |
| 0x1420a2cf0 | fCombatMagicWardAttackReachMult | 1.5 |
| 0x1420a2c90 | fCombatMagicWardCooldownTime | 1.0 |
| 0x1420a2cc0 | fCombatMagicWardMagickaCastLimit | 0.25 |
| 0x1420a2ca8 | fCombatMagicWardMagickaEquipLimit | 0.5 |
| 0x1420a2c78 | fCombatMagicWardMinCastTime | 1.5 |
| 0x1420a2018 | fCombatMaintainOptimalDistanceMaxAngle | 20.0 |
| 0x1420a2030 | fCombatMaintainRangeDistanceMin | 64.0 |
| 0x1420a6630 | fCombatMaxHoldScore | 30.0 |
| 0x1420a2078 | fCombatMaximumOptimalRangeMax | 1536.0 |
| 0x1420a2060 | fCombatMaximumOptimalRangeMid | 1280.0 |
| 0x1420a2048 | fCombatMaximumOptimalRangeMin | 1024.0 |
| 0x1420a15c8 | fCombatMaximumProjectileRange | 4096.0 |
| 0x1420a15e0 | fCombatMaximumRange | 4096.0 |
| 0x1420a1988 | fCombatMeleeTrackTargetDistanceMax | 512.0 |
| 0x1420a1970 | fCombatMeleeTrackTargetDistanceMin | 128.0 |
| 0x1420a5cd0 | fCombatMinEngageDistance | 64.0 |
| 0x1420a4ad0 | fCombatMissileImpaleDepth | 12.0 |
| 0x1420a4aa0 | fCombatMissileStickDepth | 10.0 |
| 0x1420a6930 | fCombatMonitorBuffsTimer | 3.0 |
| 0x1420a4cb0 | fCombatMoveToActorBufferDistance | 64.0 |
| 0x1420a50e8 | fCombatMusicGroupThreatRatioMax | 2.0 |
| 0x1420a50d0 | fCombatMusicGroupThreatRatioMin | 0.5 |
| 0x1420a50b8 | fCombatMusicGroupThreatRatioTimer | 1.0 |
| 0x1420a5070 | fCombatMusicNearCombatInnerRadius | 2500.0 |
| 0x1420a5088 | fCombatMusicNearCombatOuterRadius | 3500.0 |
| 0x1420a5118 | fCombatMusicPlayerCombatStrengthCap | 35000.0 |
| 0x1420a5100 | fCombatMusicPlayerNearStrengthMult | 1.0 |
| 0x1420a50a0 | fCombatMusicPlayerTargetedThreatRatio | 2.0 |
| 0x1420a5058 | fCombatMusicStopTime | 5.0 |
| 0x1420a5040 | fCombatMusicUpdateTime | 1.0 |
| 0x1420a17c0 | fCombatOffensiveBashChanceMax | 0.05 |
| 0x1420a17a8 | fCombatOffensiveBashChanceMin | 0.0 |
| 0x1420a1f88 | fCombatOptimalRangeMaxBufferDistance | 512.0 |
| 0x1420a1f70 | fCombatOptimalRangeMinBufferDistance | 256.0 |
| 0x1420a2768 | fCombatOrbitDistance | 6000.0 |
| 0x1420a2798 | fCombatOrbitTimeMax | 12.0 |
| 0x1420a2780 | fCombatOrbitTimeMin | 3.0 |
| 0x1420a2fc0 | fCombatParalyzeTacticalDuration | 10.0 |
| 0x1420a3d40 | fCombatPathingAccelerationMult | 2.0 |
| 0x1420a3ce0 | fCombatPathingCurvedPathSmoothingMult | 0.1 |
| 0x1420a3d58 | fCombatPathingDecelerationMult | 2.0 |
| 0x1420a3e30 | fCombatPathingGoalRayCastPathDistance | 512.0 |
| 0x1420a3d10 | fCombatPathingIncompletePathMinDistance | 64.0 |
| 0x1420a3cc8 | fCombatPathingLocationCenterOffsetMult | 0.02 |
| 0x1420a4ae8 | fCombatPathingLookAheadDelta | 0.5 |
| 0x1420a3d28 | fCombatPathingNormalizedRotationSpeed | 2.25 |
| 0x1420a3e00 | fCombatPathingRefLocationUpdateDistance | 32.0 |
| 0x1420a3de8 | fCombatPathingRefLocationUpdateTimeDistanceMax | 4096.0 |
| 0x1420a3dd0 | fCombatPathingRefLocationUpdateTimeDistanceMin | 1024.0 |
| 0x1420a3db8 | fCombatPathingRefLocationUpdateTimeMax | 2.5 |
| 0x1420a3da0 | fCombatPathingRefLocationUpdateTimeMin | 0.25 |
| 0x1420a3d88 | fCombatPathingRetryWaitTime | 0.25 |
| 0x1420a3d70 | fCombatPathingRotationAccelerationMult | 2.0 |
| 0x1420a3e18 | fCombatPathingStartRayCastPathDistance | 512.0 |
| 0x1420a3e48 | fCombatPathingStraightPathCheckDistance | 384.0 |
| 0x1420a3cb0 | fCombatPathingStraightRayCastPathDistance | 1024.0 |
| 0x1420a3cf8 | fCombatPathingUpdatePathCostMult | 0.67 |
| 0x1420a2918 | fCombatPerchAttackChanceMax | 1.0 |
| 0x1420a2900 | fCombatPerchAttackChanceMin | 0.0 |
| 0x1420a2948 | fCombatPerchAttackTimeMax | 15.0 |
| 0x1420a2930 | fCombatPerchAttackTimeMin | 7.5 |
| 0x1420a2960 | fCombatPerchMaxTargetAngle | 75.0 |
| 0x1420a7c50 | fCombatPlayerBleedoutHealthDamageMult | 1.0 |
| 0x1420a6f30 | fCombatPlayerLimbDamageMult | 0.5 |
| 0x1420a15f8 | fCombatProjectileMaxRangeMult | 0.9 |
| 0x1420a4a70 | fCombatProjectileMaxRangeOptimalMult | 0.85 |
| 0x1420a4c98 | fCombatRadiusMinMult | 0.9 |
| 0x1420a1bf8 | fCombatRangedAimVariance | 0.9 |
| 0x1420a1b50 | fCombatRangedAttackChanceLastAttackBonus | 0.5 |
| 0x1420a1b38 | fCombatRangedAttackChanceLastAttackBonusTime | 10.0 |
| 0x1420a1b20 | fCombatRangedAttackChanceMax | 1.0 |
| 0x1420a1b08 | fCombatRangedAttackChanceMin | 0.05 |
| 0x1420a1b98 | fCombatRangedAttackHoldTimeAbsoluteMin | 0.1 |
| 0x1420a1b80 | fCombatRangedAttackHoldTimeMax | 1.5 |
| 0x1420a1b68 | fCombatRangedAttackHoldTimeMin | 0.25 |
| 0x1420a1bb0 | fCombatRangedAttackHoldTimeMinDistance | 256.0 |
| 0x1420a1bc8 | fCombatRangedAttackMaximumHoldTime | 10.0 |
| 0x1420a1f40 | fCombatRangedDistance | 1024.0 |
| 0x1420a1f58 | fCombatRangedMinimumRange | 256.0 |
| 0x1420a1be0 | fCombatRangedProjectileFiringArc | 30.0 |
| 0x1420a6990 | fCombatRangedStandoffTimer | 6.0 |
| 0x1420a7620 | fCombatRelativeDamageMod | 100.0 |
| 0x1420a2d68 | fCombatRestoreHealthPercentMax | 0.5 |
| 0x1420a2d50 | fCombatRestoreHealthPercentMin | 0.0 |
| 0x1420a2db0 | fCombatRestoreHealthRestrictTime | 15.0 |
| 0x1420a2d98 | fCombatRestoreMagickaPercentMax | 0.4 |
| 0x1420a2d80 | fCombatRestoreMagickaPercentMin | 0.25 |
| 0x1420a2dc8 | fCombatRestoreMagickaRestrictTime | 10.0 |
| 0x1420a2d38 | fCombatRestoreStopCastThreshold | 0.25 |
| 0x14209eaa8 | fCombatRoundAmount | 3.0 |
| 0x1420a3a28 | fCombatSearchAreaUpdateTime | 5.0 |
| 0x1420a3c08 | fCombatSearchCenterRadius | 128.0 |
| 0x1420a3b30 | fCombatSearchCheckDestinationDistanceMax | 512.0 |
| 0x1420a3b18 | fCombatSearchCheckDestinationDistanceMid | 384.0 |
| 0x1420a3b00 | fCombatSearchCheckDestinationDistanceMin | 256.0 |
| 0x1420a3b48 | fCombatSearchCheckDestinationTime | 1.0 |
| 0x1420a3c50 | fCombatSearchDoorDistance | 384.0 |
| 0x1420a3c68 | fCombatSearchDoorDistanceLow | 4096.0 |
| 0x1420a3c80 | fCombatSearchDoorSearchRadius | 512.0 |
| 0x1420a3a70 | fCombatSearchExteriorRadiusMax | 2048.0 |
| 0x1420a3a58 | fCombatSearchExteriorRadiusMin | 1280.0 |
| 0x1420a3b60 | fCombatSearchIgnoreLocationRadius | 384.0 |
| 0x1420a3aa0 | fCombatSearchInteriorRadiusMax | 1280.0 |
| 0x1420a3a88 | fCombatSearchInteriorRadiusMin | 768.0 |
| 0x1420a3c20 | fCombatSearchInvestigateTime | 2.5 |
| 0x1420a3b90 | fCombatSearchLocationCheckDistance | 512.0 |
| 0x1420a3ba8 | fCombatSearchLocationCheckTime | 1.0 |
| 0x1420a3bc0 | fCombatSearchLocationInitialCheckTime | 2.0 |
| 0x1420a3bd8 | fCombatSearchLocationInvestigateDistance | 256.0 |
| 0x1420a3bf0 | fCombatSearchLocationRadius | 128.0 |
| 0x1420a3c38 | fCombatSearchLookTime | 1.0 |
| 0x1420a3ab8 | fCombatSearchRadiusBufferDistance | 256.0 |
| 0x1420a3ad0 | fCombatSearchRadiusMemberDistance | 4096.0 |
| 0x1420a3a40 | fCombatSearchSightRadius | 1536.0 |
| 0x1420a3ae8 | fCombatSearchStartWaitTime | 1.0 |
| 0x1420a3a10 | fCombatSearchUpdateTime | 1.0 |
| 0x1420a3b78 | fCombatSearchWanderDistance | 512.0 |
| 0x1420a16e8 | fCombatSelectTargetSwitchUpdateTime | 3.0 |
| 0x1420a16d0 | fCombatSelectTargetUpdateTime | 1.0 |
| 0x1420a3008 | fCombatShoutHeadTrackingAngleMovingMult | 0.5 |
| 0x1420a2ff0 | fCombatShoutHeadTrackingAngleMult | 0.9 |
| 0x1420a3068 | fCombatShoutLongRecoveryTime | 60.0 |
| 0x1420a3020 | fCombatShoutMaxHeadTrackingAngle | 180.0 |
| 0x1420a3038 | fCombatShoutReleaseTime | 0.5 |
| 0x1420a3050 | fCombatShoutShortRecoveryTime | 10.0 |
| 0x14207b3d8 | fCombatSneak1HAxeMult | 2.0 |
| 0x14207b3c0 | fCombatSneak1HDaggerMult | 2.0 |
| 0x14207b3f0 | fCombatSneak1HMaceMult | 2.0 |
| 0x14207b3a8 | fCombatSneak1HSwordMult | 2.0 |
| 0x14207b420 | fCombatSneak2HAxeMult | 1.0 |
| 0x14207b408 | fCombatSneak2HSwordMult | 1.0 |
| 0x1420a6ea0 | fCombatSneakAttackBonusMult | 3.0 |
| 0x14207b438 | fCombatSneakBowMult | 2.0 |
| 0x14207b468 | fCombatSneakCrossbowMult | 2.0 |
| 0x14207b390 | fCombatSneakHandMult | 1.0 |
| 0x14207b450 | fCombatSneakStaffMult | 1.0 |
| 0x1420a5d30 | fCombatSpeakAttackChance | 0.1 |
| 0x1420a5d78 | fCombatSpeakHitChance | 0.35 |
| 0x1420a5d90 | fCombatSpeakHitThreshold | 0.1 |
| 0x1420a5d48 | fCombatSpeakPowerAttackChance | 0.5 |
| 0x1420a5d60 | fCombatSpeakTauntChance | 0.01 |
| 0x1420a1958 | fCombatSpecialAttackChanceMax | 1.0 |
| 0x1420a1940 | fCombatSpecialAttackChanceMin | 0.0 |
| 0x1420b9f10 | fCombatSpeedValueFastWalk | 1.33 |
| 0x1420b9f28 | fCombatSpeedValueJog | 1.66 |
| 0x1420b9f40 | fCombatSpeedValueRun | 2.0 |
| 0x1420b9ef8 | fCombatSpeedValueWalk | 1.0 |
| 0x1420a4590 | fCombatSplashDamageMaxSpeed | 3000.0 |
| 0x1420a4578 | fCombatSplashDamageMinDamage | 20.0 |
| 0x1420a4560 | fCombatSplashDamageMinRadius | 128.0 |
| 0x1420a5df0 | fCombatStaffTimer | 2.0 |
| 0x1420a1340 | fCombatStaminaRegenRateMult | 0.75 |
| 0x1420a3830 | fCombatStealthPointAttackedMaxValue | 50.0 |
| 0x1420a3848 | fCombatStealthPointDetectedEventMaxValue | 75.0 |
| 0x1420a38c0 | fCombatStealthPointDrainMult | 0.5 |
| 0x1420a37e8 | fCombatStealthPointMax | 100.0 |
| 0x1420a3890 | fCombatStealthPointRegenAlertWaitTime | 10.0 |
| 0x1420a3860 | fCombatStealthPointRegenAttackedWaitTime | 25.0 |
| 0x1420a3878 | fCombatStealthPointRegenDetectedEventWaitTime | 20.0 |
| 0x1420a38a8 | fCombatStealthPointRegenLostWaitTime | 10.0 |
| 0x1420a38f0 | fCombatStealthPointRegenMin | 3.0 |
| 0x1420a38d8 | fCombatStealthPointRegenMult | 0.2 |
| 0x1420a5d18 | fCombatStepAdvanceDistance | 128.0 |
| 0x1420a1fe8 | fCombatStrafeChanceMax | 0.75 |
| 0x1420a1fd0 | fCombatStrafeChanceMin | 0.0 |
| 0x1420a1fb8 | fCombatStrafeDistanceMax | 256.0 |
| 0x1420a1fa0 | fCombatStrafeDistanceMin | 96.0 |
| 0x1420a2000 | fCombatStrafeMinDistanceRadiusMult | 3.0 |
| 0x1420a5178 | fCombatStrengthUpdateTime | 1.0 |
| 0x1420a1f28 | fCombatSurroundDistanceMax | 384.0 |
| 0x1420a1f10 | fCombatSurroundDistanceMin | 128.0 |
| 0x1420a1640 | fCombatTargetEngagedLastSeenTime | 3.0 |
| 0x1420a2480 | fCombatTargetLocationAvoidNodeRadiusOffset | -16.0 |
| 0x1420a2438 | fCombatTargetLocationCurrentReservationDistanceMult | 0.75 |
| 0x1420a2420 | fCombatTargetLocationMaxDistance | 2048.0 |
| 0x1420a23f0 | fCombatTargetLocationMinDistanceMult | 0.67 |
| 0x1420a2450 | fCombatTargetLocationPathingRadius | 10.0 |
| 0x1420a2378 | fCombatTargetLocationRadiusSizeMult | 1.25 |
| 0x1420a2408 | fCombatTargetLocationRepositionAngleMult | 0.67 |
| 0x1420a2468 | fCombatTargetLocationSwimmingOffset | 64.0 |
| 0x1420a23c0 | fCombatTargetLocationWidthMax | 180.0 |
| 0x1420a23a8 | fCombatTargetLocationWidthMin | 10.0 |
| 0x1420a2390 | fCombatTargetLocationWidthSizeMult | 2.0 |
| 0x1420a4bc0 | fCombatTeammateFollowRadiusBase | 512.0 |
| 0x1420a4ba8 | fCombatTeammateFollowRadiusMin | 512.0 |
| 0x1420a4b90 | fCombatTeammateFollowRadiusMult | 3.0 |
| 0x1420a3788 | fCombatThreatAnticipateTime | 1.0 |
| 0x1420a5010 | fCombatThreatAvoidCost | 1.0 |
| 0x1420a37d0 | fCombatThreatBufferRadius | 16.0 |
| 0x1420a3770 | fCombatThreatCacheVelocityTime | 0.33 |
| 0x1420a4fe0 | fCombatThreatDangerousObjectHealth | 30.0 |
| 0x1420a4fc8 | fCombatThreatExplosiveObjectThreatTime | 3.0 |
| 0x1420a4f80 | fCombatThreatExtrudeTime | 2.0 |
| 0x1420a4f68 | fCombatThreatExtrudeVelocityThreshold | 2.0 |
| 0x1420a4f98 | fCombatThreatNegativeExtrudeTime | 0.5 |
| 0x1420a5028 | fCombatThreatProximityExplosionAvoidTime | 10.0 |
| 0x1420a5190 | fCombatThreatRatioUpdateTime | 5.0 |
| 0x1420a4ff8 | fCombatThreatSignificantScore | 0.05 |
| 0x1420a4fb0 | fCombatThreatTimedExplosionLength | 5.0 |
| 0x1420a37b8 | fCombatThreatUpdateTimeMax | 0.25 |
| 0x1420a37a0 | fCombatThreatUpdateTimeMin | 0.125 |
| 0x1420a3758 | fCombatThreatViewCone | 120.0 |
| 0x1420a6f60 | fCombatUnarmedCritDamageMult | 0.5 |
| 0x1420a1658 | fCombatUnreachableTargetCheckTime | 3.0 |
| 0x1420a7608 | fCombatVulnerabilityMod | 0.1 |
| 0x1420a5160 | fCombatYieldRetryTime | 600.0 |
| 0x1420a5148 | fCombatYieldTime | 10.0 |
| 0x1420a3080 | iCombatAimMaxIterations | 10 |
| 0x1420a68e8 | iCombatCastDrainMinimumValue | 1 |
| 0x1420a6c48 | iCombatCrippledTorsoHitStaggerChance | 50 |
| 0x1420a7968 | iCombatDismemberPartChance | 25 |
| 0x1420a7980 | iCombatExplodePartChance | 5 |
| 0x1420a2150 | iCombatFlankingAngleOffsetCount | 2 |
| 0x1420a2168 | iCombatFlankingAngleOffsetGoalCount | 2 |
| 0x1420a2180 | iCombatFlankingDirectionOffsetCount | 2 |
| 0x1420a67b0 | iCombatHighPriorityModifier | 100 |
| 0x1420a2888 | iCombatHoverLocationCount | 4 |
| 0x1420a3c98 | iCombatSearchDoorFailureMax | 3 |
| 0x1420a3818 | iCombatStealthPointDetectionThreshold | 25 |
| 0x1420a3800 | iCombatStealthPointSneakDetectionThreshold | 70 |
| 0x1420a23d8 | iCombatTargetLocationCount | 24 |
| 0x1420a4548 | iCombatTargetPlayerSoftCap | 15 |
| 0x1420a1700 | iCombatUnloadedActorLastSeenTimeLimit | 6 |
| 0x1420af630 | sCombatCannotActivate | "You cannot use this while in combat." |

## Game settings: the other floats, A to L

The value compiled into `SkyrimSE.exe` for each game setting (GMST) it knows: what the game uses when `Skyrim.esm` has no record of that name (the plugin's record wins). `game/sim/settings.zap` keeps the few the port reads; this is the whole table.

Read from the static `SettingT<GameSettingCollection>` objects in `.data` (24 bytes: the vtable, the value, the pointer to the name; the vtable's RTTI names the class), found by scanning `.data` for pointers to names and checked against REA's `read_bytes` at 0x1420d9078 (fShadowBiasScale:Display). The address is the object's; the value is decoded by the name's type letter (f float, i int, u unsigned, b bool, s string, r and a 32-bit colors).

| address | setting | value |
|---|---|---|
| 0x1420b0d58 | fActionPointsAimAdjustment | 2.0 |
| 0x1420b0ae8 | fActionPointsAttackMagic | 1.0 |
| 0x1420b0ab8 | fActionPointsAttackOneHandMelee | 1.0 |
| 0x1420b0b00 | fActionPointsAttackRanged | 1.0 |
| 0x1420b0ad0 | fActionPointsAttackTwoHandMelee | 1.0 |
| 0x1420b0aa0 | fActionPointsAttackUnarmed | 1.0 |
| 0x1420b0b30 | fActionPointsCrouch | 1.0 |
| 0x1420b0d40 | fActionPointsFOVBase | 0.0 |
| 0x1420b0c68 | fActionPointsFOVMult | 1.0 |
| 0x1420b0b90 | fActionPointsHeal | 1.0 |
| 0x1420b0d70 | fActionPointsPowerAttackMult | 1.5 |
| 0x1420b0b18 | fActionPointsReload | 1.0 |
| 0x1420b0db8 | fActionPointsRestoreRate | 1.0 |
| 0x1420b0d88 | fActionPointsRunAndGunMult | 0.5 |
| 0x1420b0b48 | fActionPointsStand | 1.0 |
| 0x1420b0b60 | fActionPointsSwitchWeapon | 1.0 |
| 0x1420b0b78 | fActionPointsToggleWeaponDrawn | 1.0 |
| 0x1420b0da0 | fActionPointsVATSMeleeMult | 5.0 |
| 0x1420ab898 | fActiveEffectConditionUpdateInterval | 1.0 |
| 0x14209eec8 | fActorAlertSoundTimer | 5.0 |
| 0x14209f240 | fActorAlphaFadeSeconds | 1.0 |
| 0x1420a9c00 | fActorAnimZAdjust | 1.8 |
| 0x1420a8838 | fActorArmorDesirabilityDamageMult | 0.5 |
| 0x1420a8850 | fActorArmorDesirabilitySkillMult | 10.0 |
| 0x1420a03b0 | fActorDefaultTurningSpeed | 6.2831855 |
| 0x1420a8c28 | fActorLeaveWaterBreathTimer | 4.0 |
| 0x1420a87d8 | fActorLuckSkillMult | 0.4 |
| 0x1420a8bc8 | fActorStrengthEncumbranceMult | 5.0 |
| 0x1420a8be0 | fActorSwimBreathBase | 10.0 |
| 0x1420a8c10 | fActorSwimBreathDamage | 0.2 |
| 0x1420a8bf8 | fActorSwimBreathMult | 0.5 |
| 0x14209f210 | fActorTeleportFadeSeconds | 0.5 |
| 0x1420a8808 | fActorWeaponDesirabilityDamageMult | 0.5 |
| 0x1420a8820 | fActorWeaponDesirabilitySkillMult | 10.0 |
| 0x1420ab8f8 | fAddictionUsageMonitorThreshold | 25.0 |
| 0x14209f7b0 | fAiAcquireKillBase | 50.0 |
| 0x14209f7c8 | fAiAcquireKillMult | -1.0 |
| 0x14209f870 | fAIAcquireObjectDistance | 4000.0 |
| 0x14209f780 | fAiAcquirePickBase | 0.0 |
| 0x14209f798 | fAiAcquirePickMult | -1.0 |
| 0x14209f750 | fAiAcquireStealBase | 0.0 |
| 0x14209f768 | fAiAcquireStealMult | -1.0 |
| 0x14209f9a8 | fAIActivateHeight | 200.0 |
| 0x14209f990 | fAIActivateReach | 300.0 |
| 0x14209ff90 | fAIActorPackTargetHeadTrackMod | 2.0 |
| 0x1420a06e0 | fAIAimBlockedHalfCircleRadius | 250.0 |
| 0x1420a06c8 | fAIAimBlockedToleranceDegrees | 10.0 |
| 0x1420a02f0 | fAIAwareofPlayerTimer | 5.0 |
| 0x14209ff30 | fAIBestHeadTrackDistance | 500.0 |
| 0x1420a5e68 | fAICombatFleeScoreThreshold | 10.0 |
| 0x1420a69c0 | fAICombatNoAreaEffectAllyDistance | 350.0 |
| 0x1420a67e0 | fAICombatNoTargetLOSPriorityMult | 1.0 |
| 0x1420a6ab0 | fAICombatSlopeDifference | 48.0 |
| 0x1420a69d8 | fAICombatTargetUnreachablePriorityMult | 0.25 |
| 0x1420a67c8 | fAICombatUnreachableTargetPriorityMult | 0.9 |
| 0x14209fae0 | fAICommentTimeWindow | 1.0 |
| 0x1420a0338 | fAIConversationExploreTime | 0.25 |
| 0x1420a0038 | fAIDefaultSpeechMult | 0.05 |
| 0x1420a0350 | fAIDialogueDistance | 170.0 |
| 0x1420a0278 | fAIDistanceRadiusMinLocation | 100.0 |
| 0x14209fde0 | fAIDistanceTeammateDrawWeapon | 2000.0 |
| 0x1420a4488 | fAIDodgeDecisionBase | 10.0 |
| 0x1420a4470 | fAIDodgeFavorLeftRightMult | 2.0 |
| 0x1420a44b8 | fAIDodgeVerticalRangedAttackMult | 0.1 |
| 0x1420a44a0 | fAIDodgeWalkChance | 75.0 |
| 0x14209faf8 | fAIEnergyLevelBase | 0.0 |
| 0x14209fb10 | fAIEngergyLevelMult | 1.0 |
| 0x14209fed0 | fAIEscortFastTravelMaxDistFromPath | 5000.0 |
| 0x14209fea0 | fAIEscortHysteresisWidth | 50.0 |
| 0x14209feb8 | fAIEscortStartStopDelayTime | 1.0 |
| 0x14209fe70 | fAIEscortWaitDistanceExterior | 2.0 |
| 0x14209fe88 | fAIEscortWaitDistanceInterior | 512.0 |
| 0x1420a0020 | fAIExclusiveGreetingTimer | 2.0 |
| 0x1420a7c68 | fAIExplosiveWeaponDamageMult | 1.0 |
| 0x1420a7c80 | fAIExplosiveWeaponRangeMult | 1.0 |
| 0x1420a01b8 | fAIExteriorSpectatorDetection | 1000.0 |
| 0x1420a01d0 | fAIExteriorSpectatorDistance | 450.0 |
| 0x1420a44e8 | fAIFaceTargetAnimationAngle | 35.0 |
| 0x14209f888 | fAIFindBedChairsDistance | 8000.0 |
| 0x1420a4410 | fAIFleeConfBase | 40.0 |
| 0x1420a4428 | fAIFleeConfMult | -0.5 |
| 0x1420a43f8 | fAIFleeHealthMult | 20.0 |
| 0x1420a4458 | fAIFleeSuccessTimeout | 120.0 |
| 0x1420a0008 | fAIForceGreetingTimer | 3.0 |
| 0x14209f9c0 | fAIFurnitureDestinationRadius | 25.0 |
| 0x14209fff0 | fAIGreetingTimer | 20.0 |
| 0x1420a0140 | fAIHeadTrackDialogueOffsetRandomValue | 30.0 |
| 0x1420a00e0 | fAIHeadTrackDialoguePickNewOffsetTimer | 5.0 |
| 0x1420a00f8 | fAIHeadTrackDialogueResetPositionTimer | 10.0 |
| 0x1420a0128 | fAIHeadTrackDialogueStayInOffsetMax | 4.0 |
| 0x1420a0110 | fAIHeadTrackDialogueStayInOffsetMin | 1.0 |
| 0x1420a00c8 | fAIHeadTrackOffsetRandomValueMax | 60.0 |
| 0x1420a00b0 | fAIHeadTrackOffsetRandomValueMin | 30.0 |
| 0x1420a0050 | fAIHeadTrackPickNewOffsetTimer | 2.0 |
| 0x1420a0068 | fAIHeadTrackResetPositionTimer | 10.0 |
| 0x1420a0098 | fAIHeadTrackStayInOffsetMax | 6.0 |
| 0x1420a0080 | fAIHeadTrackStayInOffsetMin | 3.0 |
| 0x14209eb38 | fAIHoldDefaultHeadTrackTimer | 5.0 |
| 0x1420a0f98 | fAIHorseSearchDistance | 3000.0 |
| 0x1420a05f0 | fAIIdleAnimationDistance | 2000.0 |
| 0x1420a0608 | fAIIdleAnimationLargeCreatureDistanceMult | 3.0 |
| 0x14209fb58 | fAIIdleWaitTime | 1.0 |
| 0x14209fb70 | fAIIdleWaitTimeComplexScene | 3.0 |
| 0x1420a0320 | fAIInDialogueModeWithPlayerDistance | 500.0 |
| 0x1420a0308 | fAIInDialogueModewithPlayerTimer | 30.0 |
| 0x14209ffa8 | fAIInteriorHeadTrackMult | 0.5 |
| 0x1420a01e8 | fAIInteriorSpectatorDetection | 600.0 |
| 0x1420a0200 | fAIInteriorSpectatorDistance | 200.0 |
| 0x1420a02a8 | fAILockDoorsSeenRecentlySeconds | 5.0 |
| 0x1420a43c8 | fAIMagicSpellMult | 3.0 |
| 0x1420a6a38 | fAIMagicTimer | 3.0 |
| 0x14209f9d8 | fAIMarkerDestinationRadius | 25.0 |
| 0x14209ff78 | fAIMaxAngleRangeMovingToStartSceneDialogue | 80.0 |
| 0x14209ff18 | fAIMaxHeadTrackDistance | 400.0 |
| 0x14209ff00 | fAIMaxHeadTrackDistanceFromPC | 2000.0 |
| 0x14209ff48 | fAIMaxLargeCreatureHeadTrackDistance | 12000.0 |
| 0x14209ffd8 | fAIMaxSmileDistance | 200.0 |
| 0x14209fb28 | fAIMaxWanderTime | 100.0 |
| 0x1420a4380 | fAIMeleeArmorMult | 1.0 |
| 0x1420a4398 | fAIMeleeHandMult | 1.3 |
| 0x1420a4368 | fAIMeleeWeaponMult | 2.0 |
| 0x14209ff60 | fAIMinAngleRangeToStartSceneDialogue | 20.0 |
| 0x14209ffc0 | fAIMinGreetingDistance | 150.0 |
| 0x1420a0290 | fAIMinLocationHeight | 100.0 |
| 0x14209fe40 | fAIMoveDistanceToRecalcFollowPath | 300.0 |
| 0x14209fe10 | fAIMoveDistanceToRecalcTravelPath | 300.0 |
| 0x14209fdf8 | fAIMoveDistanceToRecalcTravelToActor | 100.0 |
| 0x1420a0f68 | fAIPatrolHysteresisWidth | 50.0 |
| 0x1420a0f80 | fAIPatrolMinSecondsAtNormalFurniture | 30.0 |
| 0x1420a5238 | fAIPowerAttackCreatureChance | 75.0 |
| 0x1420a5280 | fAIPowerAttackKnockdownBonus | 15.0 |
| 0x1420a5250 | fAIPowerAttackNPCChance | 20.0 |
| 0x1420a5268 | fAIPowerAttackRecoilBonus | 10.0 |
| 0x14209fe58 | fAIPursueDistanceLineOfSight | 2500.0 |
| 0x14209fe28 | fAIRandomizeInitialLocationMinRadius | 200.0 |
| 0x1420a43b0 | fAIRangedWeaponMult | 5.0 |
| 0x1420a43e0 | fAIRangMagicSpellMult | 5.0 |
| 0x1420a1010 | fAIRevertToScriptTracking | -3.0 |
| 0x1420a0698 | fAIShoutMinAimSeconds | 2.0 |
| 0x1420a06b0 | fAIShoutRetryDelaySeconds | 4.0 |
| 0x1420a0680 | fAIShoutToleranceDegrees | 5.0 |
| 0x14209f8b8 | fAISocialchanceForConversation | 60.0 |
| 0x14209ea48 | fAISocialchanceForConversationInterior | 25.0 |
| 0x14209f8a0 | fAISocialRadiusToTriggerConversation | 900.0 |
| 0x14209ea30 | fAISocialRadiusToTriggerConversationInterior | 500.0 |
| 0x14209f8d0 | fAISocialTimerForConversationsMax | 30.0 |
| 0x14209f8e8 | fAISocialTimerForConversationsMin | 5.0 |
| 0x14209f930 | fAISocialTimerToWaitForEvent | 20.0 |
| 0x14209f9f0 | fAISpectatorCommentTimer | 20.0 |
| 0x14209fa08 | fAISpectatorRememberThreatTimer | 20.0 |
| 0x14209fa20 | fAISpectatorShutdownDistance | 1000.0 |
| 0x1420a0248 | fAISpectatorThreatDistExplosion | 512.0 |
| 0x1420a0218 | fAISpectatorThreatDistMelee | 512.0 |
| 0x1420a0260 | fAISpectatorThreatDistMine | 256.0 |
| 0x1420a0230 | fAISpectatorThreatDistRanged | 256.0 |
| 0x1420a1028 | fAIStayonScriptHeadtrack | 20.0 |
| 0x14209ea60 | fAItalktoNPCtimer | 60.0 |
| 0x14209fee8 | fAItalktosameNPCtimer | 120.0 |
| 0x1420a02c0 | fAITrespassWarningTimer | 10.0 |
| 0x1420a69f0 | fAIUpdateMovementRestrictionsDistance | 48.0 |
| 0x1420a0668 | fAIUseMagicToleranceDegrees | 5.0 |
| 0x1420a0620 | fAIUseWeaponAnimationTimeoutSeconds | 10.0 |
| 0x1420a0638 | fAIUseWeaponDistance | 5000.0 |
| 0x1420a0650 | fAIUseWeaponToleranceDegrees | 10.0 |
| 0x1420a02d8 | fAIWaitingforScriptCallback | 5.0 |
| 0x14209f948 | fAIWalkAwayTimerForConversation | 2.0 |
| 0x14209fb40 | fAIWanderDefaultMinDist | 200.0 |
| 0x1420780a8 | fAlignEvilMaxKarma | -250.0 |
| 0x1420780c0 | fAlignGoodMinKarma | 250.0 |
| 0x142078120 | fAlignMaxKarma | 1000.0 |
| 0x142078108 | fAlignMinKarma | -1000.0 |
| 0x142078090 | fAlignVeryEvilMaxKarma | -750.0 |
| 0x1420780d8 | fAlignVeryGoodMinKarma | 750.0 |
| 0x1420a0878 | fAmbushOverRideRadiusforPlayerDetection | 1000.0 |
| 0x1420a7d58 | fArmorBaseFactor | 0.02 |
| 0x1420a7da0 | fArmorRatingBase | 1.0 |
| 0x1420a7d88 | fArmorRatingMax | 2.5 |
| 0x1420a7dd0 | fArmorRatingPCBase | 1.0 |
| 0x1420a7db8 | fArmorRatingPCMax | 2.5 |
| 0x1420a7d70 | fArmorScalingFactor | 0.15 |
| 0x1420a8790 | fArmorWeightLightMaxMod | 0.6 |
| 0x1420a7368 | fArrowBounceBlockPercentage | 0.95 |
| 0x1420a7350 | fArrowBounceLinearSpeed | 0.1 |
| 0x1420a7338 | fArrowBounceRotateSpeed | 7.5 |
| 0x1420a73e0 | fArrowBowFastMult | 1.0 |
| 0x1420a73c8 | fArrowBowMinTime | 0.8 |
| 0x1420a73f8 | fArrowBowSlowMult | 0.5 |
| 0x1420a6408 | fArrowFakeMass | 0.25 |
| 0x1420a7380 | fArrowGravityBase | 0.3 |
| 0x1420a73b0 | fArrowGravityMin | 0.05 |
| 0x1420a7398 | fArrowGravityMult | 0.002 |
| 0x1420a64f8 | fArrowMaxDistance | 2000.0 |
| 0x1420a7458 | fArrowMinBowVelocity | 0.7 |
| 0x1420a74a0 | fArrowMinDistanceForTrails | 300.0 |
| 0x1420a7428 | fArrowMinPower | 0.35 |
| 0x1420a7488 | fArrowMinSpeedForTrails | 1500.0 |
| 0x1420a7440 | fArrowMinVelocity | 0.2 |
| 0x1420a64e0 | fArrowOptimalDistance | 1000.0 |
| 0x1420a7308 | fArrowSpeedMult | 1500.0 |
| 0x1420a7470 | fArrowWeakGravity | 1.75 |
| 0x14207a900 | fArrowWobbleAmplitude | 0.1 |
| 0x14207a8d0 | fArrowWobbleCurve | 1.0 |
| 0x14207a8e8 | fArrowWobbleDuration | 1.0 |
| 0x14207a918 | fArrowWobblePeriod | 0.05 |
| 0x142077620 | fAttachedArrowAgeMax | 30.0 |
| 0x14209ca30 | fAttributeClassPrimaryBonus | 5.0 |
| 0x14209ca48 | fAttributeClassSecondaryBonus | 5.0 |
| 0x14209e7d8 | fAuroraFadeInStart | 19.5 |
| 0x14209e808 | fAuroraFadeOutStart | 5.0 |
| 0x1420a52f8 | fAutoAimMaxDegrees | 1.2 |
| 0x1420a5310 | fAutoAimMaxDegrees3rdPerson | 1.5 |
| 0x1420a5340 | fAutoAimMaxDegreesMelee | 90.0 |
| 0x1420a5328 | fAutoAimMaxDegreesVATS | 15.0 |
| 0x1420a52c8 | fAutoAimMaxDistance | 2500.0 |
| 0x1420a52e0 | fAutoAimScreenPercentage | 7.0 |
| 0x14207b090 | fAutoDoorActivateDistance | 350.0 |
| 0x14207b0a8 | fAutoDoorDisplayDistance | 700.0 |
| 0x1420a7158 | fAutomaticWeaponBurstCooldownTime | 1.0 |
| 0x1420a7140 | fAutomaticWeaponBurstFireTime | 1.0 |
| 0x14209e7f0 | fAutoraFadeIn | 20.0 |
| 0x14209e820 | fAutoraFadeOut | 5.5 |
| 0x14209ee98 | fAvoidPlayerDistance | 100.0 |
| 0x1420a8c70 | fBarterBuyMin | 1.05 |
| 0x1420a8c58 | fBarterMax | 2.4 |
| 0x1420a8c40 | fBarterMin | 1.4 |
| 0x1420a8c88 | fBarterSellMax | 0.95 |
| 0x1420a6bb8 | fBeamWidthDefault | 5.0 |
| 0x14209ef40 | fBigBumpSpeed | 600.0 |
| 0x1420a13e8 | fBleedoutCheck | 1.0 |
| 0x1420a13a0 | fBleedoutDefault | 0.2 |
| 0x1420a13d0 | fBleedoutMin | 5.0 |
| 0x1420a13b8 | fBleedoutRate | 15.0 |
| 0x1420a1388 | fBleedoutRecover | 0.0 |
| 0x1420b0388 | fBlinkDelayMax | 4.0 |
| 0x1420b0370 | fBlinkDelayMin | 1.5 |
| 0x1420b0340 | fBlinkDownTime | 0.2 |
| 0x1420b0358 | fBlinkUpTime | 0.17 |
| 0x1420a71d0 | fBlockAmountHandToHandMult | 0.25 |
| 0x1420a71b8 | fBlockAmountWeaponMult | 0.5 |
| 0x1420a71a0 | fBlockMax | 0.75 |
| 0x1420a7e78 | fBlockPowerAttackMult | 0.75 |
| 0x1420a5cb8 | fBlockScoreNoShieldMult | 0.5 |
| 0x1420a7170 | fBlockSkillBase | 0.0 |
| 0x1420a7188 | fBlockSkillMult | 1.0 |
| 0x1420a7e48 | fBlockWeaponBase | 0.05 |
| 0x1420a7e60 | fBlockWeaponScaling | 0.05 |
| 0x1420a6e28 | fBloodSplatterCountBase | 2.0 |
| 0x1420a6e40 | fBloodSplatterCountDamageBase | 0.0 |
| 0x1420a6e58 | fBloodSplatterCountDamageMult | 0.1 |
| 0x1420a6e70 | fBloodSplatterCountRandomMargin | 1.0 |
| 0x1420a6ca8 | fBloodSplatterDuration | 5.0 |
| 0x1420a6cc0 | fBloodSplatterFadeStart | 0.8 |
| 0x1420a6db0 | fBloodSplatterFlareMult | 1.0 |
| 0x1420a6d80 | fBloodSplatterFlareOffsetScale | 0.43 |
| 0x1420a6d98 | fBloodSplatterFlareSize | 0.065 |
| 0x1420a6d20 | fBloodSplatterMaxOpacity | 1.0 |
| 0x1420a6d50 | fBloodSplatterMaxOpacity2 | 1.0 |
| 0x1420a6cf0 | fBloodSplatterMaxSize | 0.125 |
| 0x1420a6d08 | fBloodSplatterMinOpacity | 0.1 |
| 0x1420a6d38 | fBloodSplatterMinOpacity2 | 0.1 |
| 0x1420a6cd8 | fBloodSplatterMinSize | 0.025 |
| 0x1420a6d68 | fBloodSplatterOpacityChance | 0.8 |
| 0x142079d78 | fBodyMorphWeaponAdjustMult | 0.5 |
| 0x1420a7410 | fBowDrawTime | 1.6667 |
| 0x1420a04e8 | fBowHoldTimer | 0.8 |
| 0x1420a74e8 | fBowNPCSpreadAngle | 5.0 |
| 0x1420a8b98 | fBowZoomStaminaDrainMult | 15.0 |
| 0x1420a8bb0 | fBowZoomStaminaRegenDelay | 3.0 |
| 0x1420a83b8 | fBribeBase | 10.0 |
| 0x14209f678 | fBribeCostCurve | 1.5 |
| 0x14209f6a8 | fBribeMoralityMult | 1.0 |
| 0x1420a83d0 | fBribeMult | 0.3 |
| 0x14209f648 | fBribeNPCLevelMult | 0.1 |
| 0x14209f660 | fBribeScale | 1.0 |
| 0x14209f690 | fBribeSpeechcraftMult | 0.03 |
| 0x1420a87a8 | fBSUnitsPerFoot | 22.0 |
| 0x1420a0f08 | fBumpReactionIdealMoveDist | 100.0 |
| 0x1420a0ef0 | fBumpReactionMinMoveDist | 50.0 |
| 0x1420a0f20 | fBumpReactionSmallDelayTime | 5.0 |
| 0x1420a0f38 | fBumpReactionSmallWaitTimer | 5.0 |
| 0x1420a9390 | fBuoyancyMultBody | 1.0 |
| 0x1420a93a8 | fBuoyancyMultExtremity | -0.3 |
| 0x1420aa218 | fCameraShakeDistFadeDelta | 2500.0 |
| 0x1420aa200 | fCameraShakeDistFadeStart | 2000.0 |
| 0x1420aa1e8 | fCameraShakeDistMin | 300.0 |
| 0x1420aa230 | fCameraShakeExplosionDistMult | 0.001 |
| 0x1420aa1b8 | fCameraShakeFadeTime | 0.25 |
| 0x1420aa1d0 | fCameraShakeMultMin | 0.0 |
| 0x1420aa1a0 | fCameraShakeTime | 1.25 |
| 0x1420779d0 | fCharacterControllerMultipleStepSpeed | 25.0 |
| 0x1420a8fd0 | fChaseDetectionTimerSetting | 3.0 |
| 0x1420a05c0 | fCheckDeadBodyTimer | 20.0 |
| 0x1420a6a98 | fCheckPositionFallDistance | 72.0 |
| 0x1420a0710 | fClosetoPlayerDistance | 800.0 |
| 0x1420a8640 | fClothingArmorBase | 0.0 |
| 0x1420a8628 | fClothingArmorScale | 0.25 |
| 0x1420a85f8 | fClothingBase | 0.0 |
| 0x1420a8610 | fClothingClassScale | 2.0 |
| 0x1420a85c8 | fClothingJewelryBase | 5.0 |
| 0x1420a85e0 | fClothingJewelryScale | 0.05 |
| 0x1420a8718 | fCommentOnPlayerActionsTimer | 10.0 |
| 0x1420aa188 | fCommentOnPlayerKnockingThings | 20.0 |
| 0x1420ab8b0 | fConcussionTimer | 15.0 |
| 0x1420a9df8 | fConeProjectileEnvironmentDistance | 500.0 |
| 0x1420a9de0 | fConeProjectileEnvironmentTimer | 0.1 |
| 0x1420a9d80 | fConeProjectileForceBase | 0.5 |
| 0x1420a9d98 | fConeProjectileForceMult | 1.0 |
| 0x1420a9dc8 | fConeProjectileForceMultAngular | 0.5 |
| 0x1420a9db0 | fConeProjectileForceMultLinear | 1.0 |
| 0x1420a9e10 | fConeProjectileWaterScaleMult | 100.0 |
| 0x1420781a0 | fConfidenceAverage | 1.0 |
| 0x142078188 | fConfidenceBrave | 0.5 |
| 0x1420781b8 | fConfidenceCautious | 2.0 |
| 0x1420781d0 | fConfidenceCowardly | 1000.0 |
| 0x142078170 | fConfidenceFoolhardy | 0.0 |
| 0x1420aac08 | fConstructibleSkillUseConst | 0.0 |
| 0x1420aabf0 | fConstructibleSkilluseExp | 0.5 |
| 0x1420aabd8 | fConstructibleSkillUseMult | 1.0 |
| 0x1420a4b18 | fCoveredAdvanceMinAdvanceDistanceMax | 512.0 |
| 0x1420a4b00 | fCoveredAdvanceMinAdvanceDistanceMin | 256.0 |
| 0x1420a4800 | fCoverEvaluationLastSeenExpireTime | 5.0 |
| 0x1420a4818 | fCoverFiredProjectileExpireTime | 5.0 |
| 0x1420a4848 | fCoverFiringReloadClipPercent | 0.25 |
| 0x1420a4830 | fCoverWaitReloadClipPercent | 0.33 |
| 0x1420a68d0 | fCreatureDefaultTurningSpeed | 45.0 |
| 0x1420af270 | fCreditsScrollSpeed | 1.0 |
| 0x1420a7128 | fDamageArmConditionBase | 0.2 |
| 0x1420a7110 | fDamageArmConditionMult | 0.8 |
| 0x1420a96a8 | fDamagedAVRegenDelay | 1.0 |
| 0x1420a96c0 | fDamagedHealthRegenDelay | 1.0 |
| 0x1420a96d8 | fDamagedMagickaRegenDelay | 1.0 |
| 0x1420a96f0 | fDamagedStaminaRegenDelay | 1.0 |
| 0x1420a7038 | fDamageGunWeapCondBase | 0.0 |
| 0x1420a7050 | fDamageGunWeapCondMult | 1.0 |
| 0x1420a7068 | fDamageMeleeWeapCondBase | 0.0 |
| 0x1420a7080 | fDamageMeleeWeapCondMult | 1.0 |
| 0x1420a7020 | fDamagePCSkillMax | 3.0 |
| 0x1420a7008 | fDamagePCSkillMin | 1.0 |
| 0x1420a6ff0 | fDamageSkillMax | 3.0 |
| 0x1420a6fd8 | fDamageSkillMin | 1.0 |
| 0x1420a70e0 | fDamageSneakAttackMult | 4.0 |
| 0x1420a7098 | fDamageStrengthBase | 0.5 |
| 0x1420a70b0 | fDamageStrengthMult | 1.0 |
| 0x1420a70c8 | fDamageToArmorPercentage | 0.5 |
| 0x1420a78f0 | fDamageToWeaponEnergyMult | 0.01 |
| 0x1420a78d8 | fDamageToWeaponGunMult | 0.01 |
| 0x1420a7908 | fDamageToWeaponLauncherMult | 0.01 |
| 0x1420a7920 | fDamageToWeaponMeleeMult | 0.01 |
| 0x1420a70f8 | fDamageUnarmedPenalty | 0.2 |
| 0x1420a6fc0 | fDamageWeaponMult | 1.0 |
| 0x1420a45f0 | fDangerousObjectExplosionDamage | 25.0 |
| 0x1420a4608 | fDangerousObjectExplosionRadius | 100.0 |
| 0x1420a45c0 | fDangerousProjectileExplosionDamage | 5.0 |
| 0x1420a45d8 | fDangerousProjectileExplosionRadius | 30.0 |
| 0x14209e598 | fDaytimeColorExtension | 0.5 |
| 0x1420a05d8 | fDeadReactionDistance | 400.0 |
| 0x1420a7548 | fDeathForceDamageMax | 50.0 |
| 0x1420a7530 | fDeathForceDamageMin | 0.0 |
| 0x1420a7518 | fDeathForceForceMax | 85.0 |
| 0x1420a7500 | fDeathForceForceMin | 35.0 |
| 0x1420a75d8 | fDeathForceMassBase | 3.0 |
| 0x1420a75f0 | fDeathForceMassMult | 0.15 |
| 0x1420a75a8 | fDeathForceRangedDamageMax | 10.0 |
| 0x1420a7590 | fDeathForceRangedDamageMin | 0.1 |
| 0x1420a7578 | fDeathForceRangedForceMax | 40.0 |
| 0x1420a7560 | fDeathForceRangedForceMin | 20.0 |
| 0x1420a75c0 | fDeathForceSpellImpactMult | 2.0 |
| 0x1420a9c18 | fDeathSoundMaxDistance | 1000.0 |
| 0x1420a6018 | fDebrisFadeTime | 1.0 |
| 0x1420778c8 | fDebrisMaxVelocity | 25.0 |
| 0x1420778b0 | fDebrisMinExtent | 2.0 |
| 0x1420a6768 | fDecapitateBloodTime | 5.0 |
| 0x14207a990 | fDefAmmoWeight | 0.1 |
| 0x1420a0e90 | fDefaultAngleTolerance | 5.0 |
| 0x1420a1400 | fDefaultBowSpeedBonus | 0.5 |
| 0x14209cce8 | fDefaultHealth | 50.0 |
| 0x1420766f8 | fDefaultIngredientSkillUseModifier | 1.0 |
| 0x14209cd00 | fDefaultMagicka | 50.0 |
| 0x14209cd30 | fDefaultMass | 1.0 |
| 0x14207a8b8 | fDefaultRelaunchInterval | 0.25 |
| 0x14209cd18 | fDefaultStamina | 50.0 |
| 0x1420a83e8 | fDemandBase | 10.0 |
| 0x1420a8400 | fDemandMult | 0.3 |
| 0x14209ef88 | fDetectEventDistanceNPC | 512.0 |
| 0x14209ef70 | fDetectEventDistancePlayer | 1536.0 |
| 0x14209efa0 | fDetectEventDistanceVeryLoudMult | 2.0 |
| 0x14209efb8 | fDetectEventSneakDistanceVeryLoud | 3072.0 |
| 0x14209f018 | fDetectProjectileDistanceNPC | 512.0 |
| 0x14209f000 | fDetectProjectileDistancePlayer | 1024.0 |
| 0x1420ad9c8 | fDialogFocalDepthRange | 300.0 |
| 0x1420ad9e0 | fDialogFocalDepthStrength | 0.65 |
| 0x1420ad9b0 | fDialogSpeechDelaySeconds | 2.0 |
| 0x1420ad980 | fDialogZoomInSeconds | 1.5 |
| 0x1420ad998 | fDialogZoomOutSeconds | 0.5 |
| 0x1420a9600 | fDifficultyDamageMultiplier | 10.0 |
| 0x1420a95e8 | fDifficultyDefaultValue | 0.0 |
| 0x1420a95d0 | fDifficultyMaxValue | 2.0 |
| 0x1420a95b8 | fDifficultyMinValue | -2.0 |
| 0x1420aa620 | fDiffMultHPByPCE | 1.5 |
| 0x1420aa650 | fDiffMultHPByPCH | 0.75 |
| 0x1420aa680 | fDiffMultHPByPCL | 0.25 |
| 0x1420aa638 | fDiffMultHPByPCN | 1.0 |
| 0x1420aa608 | fDiffMultHPByPCVE | 2.0 |
| 0x1420aa668 | fDiffMultHPByPCVH | 0.5 |
| 0x1420aa590 | fDiffMultHPToPCE | 0.75 |
| 0x1420aa5c0 | fDiffMultHPToPCH | 1.5 |
| 0x1420aa5f0 | fDiffMultHPToPCL | 2.5 |
| 0x1420aa5a8 | fDiffMultHPToPCN | 1.0 |
| 0x1420aa578 | fDiffMultHPToPCVE | 0.5 |
| 0x1420aa5d8 | fDiffMultHPToPCVH | 2.0 |
| 0x1420aa6b0 | fDiffMultXPH | 0.0 |
| 0x1420aa698 | fDiffMultXPVH | 0.0 |
| 0x1420a4758 | fDisarmedPickupWeaponDistanceMult | 2.0 |
| 0x1420a9378 | fDisenchantSkillUse | 6.0 |
| 0x1420aa2d8 | fDistanceAutomaticallyActivateDoor | 250.0 |
| 0x1420a04a0 | fDistanceExteriorReactCombat | 600.0 |
| 0x1420aa2f0 | fDistanceFadeActorAutoLoadDoor | 150.0 |
| 0x1420a04b8 | fDistanceInteriorReactCombat | 300.0 |
| 0x14209fa80 | fDistanceProjectileExplosionDetection | 400.0 |
| 0x14209ea78 | fDistancetoPlayerforConversations | 3000.0 |
| 0x1420a5358 | fDOFDistanceMult | 5.0 |
| 0x1420bace0 | fDoorMarkerDisplayHeight:Interface | 64.0 |
| 0x14207bdf0 | fDragonLandingZoneClearRadius | 256.0 |
| 0x1420b3ec8 | fDragonMaxUpwardPitch | 45.0 |
| 0x1420b32c8 | fDragonRiderLandingZoneClearRadius | 200.0 |
| 0x14209f270 | fDrinkRepeatRate | 1.0 |
| 0x1420a0518 | fDyingTimer | 2.0 |
| 0x14207abe0 | fEffectShaderFillEdgeMinFadeRate | 0.05 |
| 0x14207abc8 | fEffectShaderParticleMinFadeRate | 0.33 |
| 0x1420a4860 | fEmbeddedWeaponSwitchChance | 0.5 |
| 0x1420a4878 | fEmbeddedWeaponSwitchTime | 5.0 |
| 0x1420aaaa0 | fEnchantingCostExponent | 1.1 |
| 0x1420baae0 | fEnchantingRuleOfFive | 60.0 |
| 0x1420baaf8 | fEnchantingRuleOfTen | 120.0 |
| 0x1420baac8 | fEnchantingRuleOfTwo | 30.0 |
| 0x1420aaa58 | fEnchantingSkillCostBase | 0.005 |
| 0x1420aaa70 | fEnchantingSkillCostMult | 3.0 |
| 0x1420aaa88 | fEnchantingSkillCostScale | 0.5 |
| 0x1420aaa40 | fEnchantingSkillFactor | 3.0 |
| 0x1420a9360 | fEnchantmentEffectPointsMult | 0.4 |
| 0x1420aac38 | fEnchantmentGoldMult | 1.0 |
| 0x1420a9348 | fEnchantmentPointsMult | 0.4 |
| 0x1420a6618 | fEnemyHealthBarTimer | 5.5 |
| 0x1420a9a98 | fEssentialDeathTime | 30.0 |
| 0x1420a1358 | fEssentialDownCombatHealthRegenMult | 0.75 |
| 0x1420a9ab0 | fEssentialHealthPercentReGain | 0.3 |
| 0x1420a0ff8 | fEssentialNonCombatHealRateBonus | 5.0 |
| 0x1420a0fe0 | fEssentialNPCMinimumHealth | -30.0 |
| 0x1420a0ea8 | fEvaluatePackageTimer | 15.0 |
| 0x1420a0ec0 | fEvaluateProcedureTimer | 3.0 |
| 0x1420a6c78 | fExplodeLimbRemovalDelay | 0.25 |
| 0x1420a6c90 | fExplodeLimbRemovalDelayVATS | 0.25 |
| 0x1420a9c60 | fExplosionForceClutterUpBias | 0.5 |
| 0x1420a9c48 | fExplosionForceKnockdownMinimum | 0.15 |
| 0x1420a9c90 | fExplosionForceMultAngular | 1.0 |
| 0x1420a9c78 | fExplosionForceMultLinear | 1.0 |
| 0x1420a9cc0 | fExplosionImageSpaceSwapPower | 0.6 |
| 0x1420a9c30 | fExplosionKnockStateExplodeDownTime | 15.0 |
| 0x1420a9ca8 | fExplosionLOSBuffer | 3.0 |
| 0x1420a9d20 | fExplosionLOSBufferDistance | 24.0 |
| 0x1420a9d08 | fExplosionMaxImpulse | 8000.0 |
| 0x1420a9d50 | fExplosionSourceRefMult | 1.0 |
| 0x1420a9cf0 | fExplosionSplashRadius | 1.0 |
| 0x1420a9d38 | fExplosionWaterRadiusRatio | 0.75 |
| 0x1420a4650 | fExplosiveProjectileBlockedResetTime | 5.0 |
| 0x1420a4638 | fExplosiveProjectileBlockedWaitTime | 2.5 |
| 0x1420b02f8 | fExpressionChangePerSec | 2.0 |
| 0x1420b0310 | fExpressionStrengthAdd | 1.0 |
| 0x1420b05b0 | fEyeHeadingMaxOffsetEmotionAngry | 0.1 |
| 0x1420b0610 | fEyeHeadingMaxOffsetEmotionFear | 0.5 |
| 0x1420b04f0 | fEyeHeadingMaxOffsetEmotionHappy | 0.2 |
| 0x1420b0670 | fEyeHeadingMaxOffsetEmotionNeutral | 0.2 |
| 0x1420b0550 | fEyeHeadingMaxOffsetEmotionSad | 0.4 |
| 0x1420b05c8 | fEyeHeadingMinOffsetEmotionAngry | -0.1 |
| 0x1420b0628 | fEyeHeadingMinOffsetEmotionFear | -0.5 |
| 0x1420b0508 | fEyeHeadingMinOffsetEmotionHappy | -0.2 |
| 0x1420b0688 | fEyeHeadingMinOffsetEmotionNeutral | -0.2 |
| 0x1420b0568 | fEyeHeadingMinOffsetEmotionSad | -0.4 |
| 0x1420b0580 | fEyePitchMaxOffsetEmotionAngry | 0.15 |
| 0x1420b05e0 | fEyePitchMaxOffsetEmotionFear | 0.0 |
| 0x1420b04c0 | fEyePitchMaxOffsetEmotionHappy | 0.15 |
| 0x1420b0640 | fEyePitchMaxOffsetEmotionNeutral | 0.15 |
| 0x1420b0520 | fEyePitchMaxOffsetEmotionSad | -0.05 |
| 0x1420b0598 | fEyePitchMinOffsetEmotionAngry | -0.05 |
| 0x1420b05f8 | fEyePitchMinOffsetEmotionFear | 0.0 |
| 0x1420b04d8 | fEyePitchMinOffsetEmotionHappy | -0.05 |
| 0x1420b0658 | fEyePitchMinOffsetEmotionNeutral | -0.05 |
| 0x1420b0538 | fEyePitchMinOffsetEmotionSad | -0.15 |
| 0x1420a8b38 | fFallLegDamageMult | 0.5 |
| 0x1420aa2c0 | fFastTravelSpeedMult | 1.0 |
| 0x1420a03f8 | fFastWalkInterpolationBetweenWalkAndRun | 0.25 |
| 0x14209f558 | fFavorCostActivator | 5.0 |
| 0x14209f570 | fFavorCostAttack | 50.0 |
| 0x14209f5a0 | fFavorCostAttackCrimeMult | 3.0 |
| 0x14209f528 | fFavorCostLoadDoor | 10.0 |
| 0x14209f540 | fFavorCostNonLoadDoor | 0.0 |
| 0x14209f4e0 | fFavorCostOwnedDoorMult | 2.0 |
| 0x14209f588 | fFavorCostStealContainerCrime | 25.0 |
| 0x14209f510 | fFavorCostStealContainerMult | 1.0 |
| 0x14209f4b0 | fFavorCostStealObjectMult | 1.0 |
| 0x14209f498 | fFavorCostTakeObject | 5.0 |
| 0x14209f4f8 | fFavorCostUnlockContainer | 25.0 |
| 0x14209f4c8 | fFavorCostUnlockDoor | 25.0 |
| 0x14209f618 | fFavorEventStopDistance | 650.0 |
| 0x14209f600 | fFavorEventTriggerDistance | 220.0 |
| 0x14209f5e8 | fFavorRequestPickDistance | 800.0 |
| 0x14209f5d0 | fFavorRequestRadius | 1000.0 |
| 0x14209f5b8 | fFavorRequestWaitTimer | 20.0 |
| 0x1420b74e8 | fFirstPersonLookAtVertOffset | 0.0 |
| 0x1420a5e08 | fFleeDistanceExterior | 2000.0 |
| 0x1420a5e20 | fFleeDistanceInterior | 300.0 |
| 0x1420a5e38 | fFleeDoneDistanceExterior | 2500.0 |
| 0x1420a5e50 | fFleeDoneDistanceInterior | 600.0 |
| 0x1420a04d0 | fFleeIsSafeTimer | 30.0 |
| 0x1420ad848 | fFloatQuestMarkerFloatHeight | 20.0 |
| 0x1420ad830 | fFloatQuestMarkerMaxDistance | 2000.0 |
| 0x1420ad818 | fFloatQuestMarkerMinDistance | 1000.0 |
| 0x1420a0398 | fFlyingActorDefaultTurningSpeed | 1.5707964 |
| 0x1420a0470 | fFlyingMountedMaxLookingDown | 70.0 |
| 0x1420a0dd0 | fFollowerSpacingAtDoors | 200.0 |
| 0x1420a0da0 | fFollowExtraCatchUpSpeedMult | 0.2 |
| 0x1420a0d88 | fFollowMatchSpeedZoneWidth | 128.0 |
| 0x1420a0d10 | fFollowRunMaxSpeedupMultiplier | 1.25 |
| 0x1420a0d28 | fFollowRunMinSlowdownMultiplier | 0.9 |
| 0x1420a0d40 | fFollowSlowdownZoneWidth | 150.0 |
| 0x1420a0db8 | fFollowSpaceBetweenFollowers | 100.0 |
| 0x1420a0de8 | fFollowStartSprintDistance | 500.0 |
| 0x1420a0d58 | fFollowStopZoneMinMult | 0.5 |
| 0x1420a0ce0 | fFollowWalkMaxSpeedupMultiplier | 1.5 |
| 0x1420a0cf8 | fFollowWalkMinSlowdownMultiplier | 0.75 |
| 0x1420a0d70 | fFollowWalkZoneMult | 1.0 |
| 0x14209f7e0 | fFriendHitTimer | 10.0 |
| 0x14209f7f8 | fFriendMinimumLastHitTime | 0.5 |
| 0x1420a0e30 | fFurnitureMarkerAngleTolerance | 1.0 |
| 0x1420a1040 | fFurnitureScaleAnimDurationNPC | 0.5 |
| 0x1420a1058 | fFurnitureScaleAnimDurationPlayer | 0.01 |
| 0x1420a9eb8 | fGameplayImpulseMinMass | 5.0 |
| 0x1420a9e70 | fGameplayImpulseMultBiped | 0.2 |
| 0x1420a9ea0 | fGameplayImpulseMultClutter | 1.0 |
| 0x1420a9ed0 | fGameplayImpulseMultDebrisLarge | 1.0 |
| 0x1420a9e88 | fGameplayImpulseMultProp | 0.1 |
| 0x1420a9e58 | fGameplayImpulseMultTrap | 0.15 |
| 0x1420a9e40 | fGameplayImpulseScale | 150.0 |
| 0x1420a9f30 | fGameplayiSpeakingEmotionMaxDeltaChange | 30.0 |
| 0x1420a9f18 | fGameplayiSpeakingEmotionMinDeltaChange | 30.0 |
| 0x1420a9f48 | fGameplaySpeakingEmotionMaxChangeValue | 1.5 |
| 0x1420a9f60 | fGameplaySpeakingEmotionMinChangeValue | 0.0 |
| 0x1420a9f78 | fGameplayVoiceFilePadding | 0.25 |
| 0x1420a6ba0 | fGetHitPainMult | 1.5 |
| 0x1420a9558 | fGrabMaxWeightRunning | 50.0 |
| 0x1420a9540 | fGrabMaxWeightWalking | 100.0 |
| 0x1420a6048 | fGrenadeAgeMax | 90.0 |
| 0x1420a6528 | fGrenadeFriction | 0.0 |
| 0x1420a47e8 | fGrenadeHighArcSpeedPercentage | 0.67 |
| 0x1420a6510 | fGrenadeRestitution | 0.0 |
| 0x1420a49f8 | fGrenadeThrowHitFractionThreshold | 0.8 |
| 0x1420a0860 | fGuardPackageAttackRadiusMult | 0.25 |
| 0x1420a5fd0 | fGunDecalCameraDistance | 2048.0 |
| 0x1420a5fe8 | fGunParticleCameraDistance | 1024.0 |
| 0x1420a6000 | fGunReferenceSkill | 0.0 |
| 0x1420a5fb8 | fGunShellCameraDistance | 512.0 |
| 0x1420a5f88 | fGunShellDirectionRandomize | 0.1 |
| 0x1420a5f58 | fGunShellEjectSpeed | 100.0 |
| 0x1420a5f70 | fGunShellLifetime | 5.0 |
| 0x1420a5fa0 | fGunShellRotateRandomize | 0.1 |
| 0x1420a5f40 | fGunShellRotateSpeed | 300.0 |
| 0x1420a76b0 | fGunSpreadArmBase | 1.0 |
| 0x1420a76c8 | fGunSpreadArmMult | -1.0 |
| 0x1420a7650 | fGunSpreadCondBase | 1.0 |
| 0x1420a7668 | fGunSpreadCondMult | -1.0 |
| 0x1420a77a0 | fGunSpreadCrouchBase | 1.0 |
| 0x1420a77b8 | fGunSpreadCrouchMult | -0.4 |
| 0x1420a7740 | fGunSpreadDriftBase | 0.0 |
| 0x1420a7758 | fGunSpreadDriftMult | 0.1 |
| 0x1420a7710 | fGunSpreadHeadBase | 1.0 |
| 0x1420a7728 | fGunSpreadHeadMult | -1.0 |
| 0x1420a7770 | fGunSpreadIronSightsBase | 1.0 |
| 0x1420a7788 | fGunSpreadIronSightsMult | -0.65 |
| 0x1420a76e0 | fGunSpreadNPCArmBase | 0.5 |
| 0x1420a76f8 | fGunSpreadNPCArmMult | 1.0 |
| 0x1420a7800 | fGunSpreadRunBase | 1.0 |
| 0x1420a7818 | fGunSpreadRunMult | 1.0 |
| 0x1420a7680 | fGunSpreadSkillBase | 1.0 |
| 0x1420a7698 | fGunSpreadSkillMult | -0.01 |
| 0x1420a77d0 | fGunSpreadWalkBase | 1.0 |
| 0x1420a77e8 | fGunSpreadWalkMult | 0.0 |
| 0x1420a5b80 | fHandDamageSkillBase | 0.0 |
| 0x1420a5b98 | fHandDamageSkillMult | 1.0 |
| 0x1420a5bb0 | fHandDamageStrengthBase | 0.0 |
| 0x1420a5bc8 | fHandDamageStrengthMult | 0.75 |
| 0x1420a5bf8 | fHandHealthMax | 20.0 |
| 0x1420a5be0 | fHandHealthMin | 1.0 |
| 0x1420a5c10 | fHandReachDefault | 64.0 |
| 0x1420b6110 | fHavokTauRatio | 0.5 |
| 0x14207a838 | fHazardDefaultTargetInterval | 0.25 |
| 0x1420a9e28 | fHazardDropMaxDistance | 1024.0 |
| 0x1420ab9d0 | fHazardMaxWaitTime | 3.0 |
| 0x14207a850 | fHazardMinimumSpawnInterval | 0.1 |
| 0x1420ab9e8 | fHazardSpacingMult | 0.8 |
| 0x1420a0e48 | fHeadingMarkerAngleTolerance | 5.0 |
| 0x1420a0170 | fHeadTrackSpeedMax | 150.0 |
| 0x1420a01a0 | fHeadTrackSpeedMaxAngle | 40.0 |
| 0x1420a0158 | fHeadTrackSpeedMin | 50.0 |
| 0x1420a0188 | fHeadTrackSpeedMinAngle | 5.0 |
| 0x142077410 | fHealthDataValue1 | 1.1 |
| 0x142077458 | fHealthDataValue2 | 1.2 |
| 0x1420774a0 | fHealthDataValue3 | 1.3 |
| 0x1420774e8 | fHealthDataValue4 | 1.4 |
| 0x142077530 | fHealthDataValue5 | 1.5 |
| 0x142077578 | fHealthDataValue6 | 1.6 |
| 0x1420a12c8 | fHealthRegenDelayMax | 5.0 |
| 0x14209e300 | fHitCasterSizeLarge | 24.0 |
| 0x14209e2e8 | fHitCasterSizeSmall | 12.0 |
| 0x1420ba3b8 | fHorseMaxUpwardPitch | 25.0 |
| 0x1420a8b08 | fHorseMountOffsetX | -63.479 |
| 0x1420a8b20 | fHorseMountOffsetY | 0.0 |
| 0x1420a9588 | fHostileActorExteriorDistance | 3000.0 |
| 0x1420a9570 | fHostileActorInteriorDistance | 2000.0 |
| 0x1420a95a0 | fHostileFlyingActorExteriorDistance | 15000.0 |
| 0x1420add88 | fHUDCompassLocationMaxDist | 8000.0 |
| 0x14209fa50 | fIdleChatterCommentTimer | 5.0 |
| 0x14209fa68 | fIdleChatterCommentTimerMax | 30.0 |
| 0x1420a0e60 | fIdleMarkerAngleTolerance | 1.0 |
| 0x1420aa4e8 | fImpactShaderMaxDistance | 5000.0 |
| 0x1420aa518 | fImpactShaderMaxMagnitude | 5.0 |
| 0x1420aa500 | fImpactShaderMinMagnitude | 0.1 |
| 0x14209f708 | fIntimidateConfidenceMultAverage | 1.0 |
| 0x14209f720 | fIntimidateConfidenceMultBrave | 1.5 |
| 0x14209f6f0 | fIntimidateConfidenceMultCautious | 0.5 |
| 0x14209f6d8 | fIntimidateConfidenceMultCowardly | 0.0 |
| 0x14209f738 | fIntimidateConfidenceMultFoolhardy | 100.0 |
| 0x14209f6c0 | fIntimidateSpeechcraftCurve | 1.5 |
| 0x142076c70 | fInvisibilityMaxRefraction | 1.0 |
| 0x142076c88 | fInvisibilityMinRefraction | 0.01 |
| 0x1420a53a0 | fIronSightsDOFDistance | 310.0 |
| 0x1420a53b8 | fIronSightsDOFRange | 600.0 |
| 0x1420a5388 | fIronSightsDOFStrengthCap | 1.7 |
| 0x1420a5370 | fIronSightsDOFSwitchSeconds | 0.15 |
| 0x1420a6210 | fIronSightsFOVTimeChange | 0.25 |
| 0x1420a5478 | fIronSightsGunMotionBlur | 0.1 |
| 0x1420a5460 | fIronSightsMotionBlur | 0.15 |
| 0x1420aac68 | fItemPointsMult | 1.0 |
| 0x1420a9198 | fItemRepairCostMult | 1.0 |
| 0x1420a03e0 | fJogInterpolationBetweenWalkAndRun | 0.5 |
| 0x1420a8988 | fJumpDoubleMult | 0.5 |
| 0x1420a8880 | fJumpFallHeightExponent | 1.65 |
| 0x1420a88c8 | fJumpFallHeightExponentNPC | 1.65 |
| 0x1420a8868 | fJumpFallHeightMin | 600.0 |
| 0x1420a88b0 | fJumpFallHeightMinNPC | 300.0 |
| 0x1420a8898 | fJumpFallHeightMult | 0.1 |
| 0x1420a88e0 | fJumpFallHeightMultNPC | 0.1 |
| 0x1420a8940 | fJumpFallRiderMult | 0.0 |
| 0x1420a8910 | fJumpFallSkillBase | 1.25 |
| 0x1420a8928 | fJumpFallSkillMult | -0.01 |
| 0x1420a88f8 | fJumpFallVelocityMin | 600.0 |
| 0x1420a8958 | fJumpHeightMin | 64.0 |
| 0x1420a89a0 | fJumpMoveBase | 0.0 |
| 0x1420a89b8 | fJumpMoveMult | 0.3 |
| 0x1420a8970 | fJumpSwimmingMult | 2.0 |
| 0x1420a0c50 | fKarmaModKillingEvilActor | 1.0 |
| 0x1420a0c80 | fKarmaModMurderingNonEvilCreature | -25.0 |
| 0x1420a0c68 | fKarmaModMurderingNonEvilNPC | -100.0 |
| 0x1420a0c98 | fKarmaModStealing | -5.0 |
| 0x1420a7f20 | fKillCamBaseOdds | 0.1 |
| 0x1420a7f38 | fKillCamLevelBias | 0.01 |
| 0x1420a7f80 | fKillCamLevelFactor | 0.5 |
| 0x1420a7f50 | fKillCamLevelMaxBias | 0.1 |
| 0x1420a6f90 | fKillMoveMaxDuration | 10.0 |
| 0x1420a07a0 | fKillWitnessesTimerSetting | 30.0 |
| 0x1420a7278 | fKnockbackAgilBase | 1.0 |
| 0x1420a7290 | fKnockbackAgilMult | -0.008 |
| 0x1420a72a8 | fKnockbackDamageBase | 50.0 |
| 0x1420a72c0 | fKnockbackDamageMult | 10.0 |
| 0x1420a72d8 | fKnockbackForceMax | 512.0 |
| 0x1420a72f0 | fKnockbackTime | 1.0 |
| 0x1420a7200 | fKnockdownAgilBase | 0.0 |
| 0x1420a7218 | fKnockdownAgilMult | 1.0 |
| 0x1420a7938 | fKnockdownBaseHealthThreshold | 75.0 |
| 0x1420a7260 | fKnockdownChance | 0.25 |
| 0x1420a7950 | fKnockdownCurrentHealthThreshold | 25.0 |
| 0x1420a7230 | fKnockdownDamageBase | 0.0 |
| 0x1420a7248 | fKnockdownDamageMult | 0.3 |
| 0x1420a49e0 | fLargeProjectilePickBufferSize | 4.0 |
| 0x1420a49b0 | fLargeProjectileSize | 5.0 |
| 0x14207b608 | fLargeRefMinSize | 1024.0 |
| 0x1420aebf8 | fLegendarySkillResetValue | 15.0 |
| 0x1420775c0 | fLeveledActorMultEasy | 0.25 |
| 0x1420775f0 | fLeveledActorMultHard | 0.75 |
| 0x1420775d8 | fLeveledActorMultMedium | 0.5 |
| 0x142077608 | fLeveledActorMultVeryHard | 1.0 |
| 0x1420772d8 | fLeveledLockMult | 1.5 |
| 0x14207b5f0 | fLevelScalingMult | 0.6 |
| 0x1420a8d00 | fLevelUpCarryWeightMod | 10.0 |
| 0x14209ed00 | fLightRecalcTimer | 2.0 |
| 0x14209ed18 | fLightRecalcTimerPlayer | 0.5 |
| 0x1420adda0 | fLoadingWheelScale | 2.0 |
| 0x14209fc78 | fLockLevelBase | 0.0 |
| 0x14209fc90 | fLockLevelMult | -1.0 |
| 0x1420aa980 | fLockpickBreakAdept | 0.75 |
| 0x1420aa968 | fLockpickBreakApprentice | 1.0 |
| 0x14209fcd8 | fLockPickBreakBase | 0.05 |
| 0x1420aa998 | fLockpickBreakExpert | 0.5 |
| 0x1420aa9b0 | fLockpickBreakMaster | 0.25 |
| 0x14209fcf0 | fLockPickBreakMult | -0.001 |
| 0x1420aa950 | fLockpickBreakNovice | 2.0 |
| 0x1420aa920 | fLockpickBreakSkillBase | 1.0 |
| 0x1420aa938 | fLockpickBreakSkillMult | 0.005 |
| 0x1420aa7b8 | fLockpickBrokenPicksMult | 5.0 |
| 0x14209fca8 | fLockPickQualityBase | 1.0 |
| 0x14209fcc0 | fLockPickQualityMult | 0.02 |
| 0x1420aa878 | fLockpickSkillPartialPickBase | 1.0 |
| 0x1420aa890 | fLockpickSkillPartialPickMult | 0.0 |
| 0x1420aa7d0 | fLockpickSkillSweetSpotBase | 0.82 |
| 0x1420aa7e8 | fLockpickSkillSweetSpotMult | 0.012 |
| 0x1420aa248 | fLockSkillBase | 10.0 |
| 0x14209fc60 | fLockSkillMult | 1.0 |
| 0x14209fd08 | fLockTrapGoOffBase | 0.02 |
| 0x14209fd20 | fLockTrapGoOffMult | -0.002 |
| 0x1420b04a8 | fLookDownDisableBlinkingAmt | 0.25 |
| 0x1420aa398 | fLowHealthTutorialPercentage | 0.25 |
| 0x1420a8658 | fLowLevelNPCBaseHealthMult | 0.25 |
| 0x1420aa3b0 | fLowMagickaTutorialPercentage | 0.25 |
| 0x1420aa3c8 | fLowStaminaTutorialPercentage | 0.25 |

## Game settings: the other floats, M to Z

The value compiled into `SkyrimSE.exe` for each game setting (GMST) it knows: what the game uses when `Skyrim.esm` has no record of that name (the plugin's record wins). `game/sim/settings.zap` keeps the few the port reads; this is the whole table.

Read from the static `SettingT<GameSettingCollection>` objects in `.data` (24 bytes: the vtable, the value, the pointer to the name; the vtable's RTTI names the class), found by scanning `.data` for pointers to names and checked against REA's `read_bytes` at 0x1420d9078 (fShadowBiasScale:Display). The address is the object's; the value is decoded by the name's type letter (f float, i int, u unsigned, b bool, s string, r and a 32-bit colors).

| address | setting | value |
|---|---|---|
| 0x1420a9690 | fMapMarkerMaxPercentSize | 130.0 |
| 0x1420a9618 | fMapMarkerMinFadeAlpha | 40.0 |
| 0x1420a9678 | fMapMarkerMinPercentSize | 90.0 |
| 0x1420a9660 | fMapQuestMarkerMaxPercentSize | 150.0 |
| 0x1420a9630 | fMapQuestMarkerMinFadeAlpha | 90.0 |
| 0x1420a9648 | fMapQuestMarkerMinPercentSize | 100.0 |
| 0x14209e5f8 | fMasserAngleFadeEnd | 45.0 |
| 0x14209e5e0 | fMasserAngleFadeStart | 55.0 |
| 0x14209e610 | fMasserAngleShadowEarlyFade | 0.5 |
| 0x14209e628 | fMasserSpeed | 0.25 |
| 0x14209e640 | fMasserZOffset | 35.0 |
| 0x1420a7d40 | fMaxArmorRating | 95.0 |
| 0x1420a8ec8 | fMaximumWind | 256.0 |
| 0x1420a0938 | fMaxSandboxRescanSeconds | 6.0 |
| 0x1420aeaf0 | fMaxSellMult | 1.0 |
| 0x1420a4a10 | fMeleeMovementRestrictionsUpdateTime | 1.0 |
| 0x1420a4a28 | fMeleeSweepViewAngleMult | 2.0 |
| 0x14207a978 | fMinAmmoWeight | 0.0 |
| 0x1420aead8 | fMinBuyMult | 1.0 |
| 0x1420a8af0 | fMinDistanceUseHorse | 10000.0 |
| 0x1420a6060 | fMineAgeMax | 0.0 |
| 0x1420a64b0 | fMineExteriorRadiusMult | 1.0 |
| 0x1420a6600 | fMinesBlinkFast | 0.1 |
| 0x1420a65d0 | fMinesBlinkMax | 2.0 |
| 0x1420a65e8 | fMinesBlinkSlow | 0.25 |
| 0x1420a65b8 | fMinesDelayMin | 0.1 |
| 0x1420a0920 | fMinSandboxRescanSeconds | 3.0 |
| 0x1420ab9b8 | fModelReferenceEffectMaxWaitTime | 3.0 |
| 0x1420a5490 | fMotionBlur | 0.0 |
| 0x1420a0458 | fMountedMaxLookingDown | 40.0 |
| 0x1420aa4a0 | fMoveCharRunBase | 370.0 |
| 0x1420aa440 | fMoveCharWalkBase | 85.0 |
| 0x1420aa410 | fMoveEncumEffect | 0.4 |
| 0x1420aa428 | fMoveEncumEffectNoWeapon | 0.3 |
| 0x1420aa488 | fMoveFlyRunMult | 20.0 |
| 0x1420aa470 | fMoveFlyWalkMult | 50.0 |
| 0x1420a48f0 | fMovementNearTargetAvoidCost | 25.0 |
| 0x1420a48d8 | fMovementNearTargetAvoidRadius | 64.0 |
| 0x1420a48c0 | fMovementTargetAvoidCost | 25.0 |
| 0x1420a48a8 | fMovementTargetAvoidRadius | 512.0 |
| 0x1420a4890 | fMovementTargetAvoidRadiusMult | 1.25 |
| 0x1420aa4b8 | fMoveSprintMult | 1.3 |
| 0x1420aa458 | fMoveSwimMult | 2.0 |
| 0x1420aa3f8 | fMoveWeightMax | 150.0 |
| 0x1420aa3e0 | fMoveWeightMin | 0.0 |
| 0x1420a86a0 | fNPCAttributeHealthMult | 0.5 |
| 0x1420a8f28 | fNPCBaseMagickaMult | 0.2 |
| 0x14209c8a0 | fNPCGeneticVariation | 0.5 |
| 0x1420a8f70 | fNPCHealthLevelBonus | 5.0 |
| 0x1420a9b40 | fObjectHitH2HReach | 64.0 |
| 0x1420a9b58 | fObjectHitTwoHandReach | 112.0 |
| 0x1420a9b28 | fObjectHitWeaponReach | 150.0 |
| 0x1420a54a8 | fObjectMotionBlur | 100.0 |
| 0x1420a0560 | fObjectWeightPickupDetectionMult | 1.0 |
| 0x1420a8b80 | fOutOfBreathStaminaRegenDelay | 3.0 |
| 0x1420b3e80 | fOverShoulderRangedDragonAddY | -150.0 |
| 0x1420b3e50 | fOverShoulderRangedDragonPosX | 0.0 |
| 0x1420b3e68 | fOverShoulderRangedDragonPosZ | 90.0 |
| 0x1420ba388 | fOverShoulderRangedMountedAddY | -150.0 |
| 0x1420ba358 | fOverShoulderRangedMountedPosX | 0.0 |
| 0x1420ba370 | fOverShoulderRangedMountedPosZ | 90.0 |
| 0x1420a9720 | fPainDelay | 1.5 |
| 0x1420aa8d8 | fPartialPickAverage | 26.0 |
| 0x1420aa8c0 | fPartialPickEasy | 26.0 |
| 0x1420aa8f0 | fPartialPickHard | 26.0 |
| 0x1420aa8a8 | fPartialPickVeryEasy | 26.0 |
| 0x1420aa908 | fPartialPickVeryHard | 26.0 |
| 0x1420b8068 | fPathPointTurningSpeed | 10.0 |
| 0x1420b8050 | fPathPointZDistanceAllowance | 10.0 |
| 0x1420a8f40 | fPCBaseHealthMult | 2.0 |
| 0x1420a8f10 | fPCBaseMagickaMult | 0.5 |
| 0x1420a8f58 | fPCHealthLevelBonus | 5.0 |
| 0x1420a0848 | fPerceptionMult | 400.0 |
| 0x1420a8a18 | fPerkHeavyArmorExpertSpeedMult | 0.5 |
| 0x1420a8a90 | fPerkHeavyArmorJourneymanDamageMult | 0.5 |
| 0x1420a8a30 | fPerkHeavyArmorMasterSpeedMult | 0.0 |
| 0x1420a8a78 | fPerkHeavyArmorNoviceDamageMult | 1.5 |
| 0x1420a8a00 | fPerkHeavyArmorSinkGravityMult | 15.0 |
| 0x1420a8a48 | fPerkLightArmorExpertSpeedMult | 0.0 |
| 0x1420a8aa8 | fPerkLightArmorJourneymanDamageMult | 0.5 |
| 0x1420a6888 | fPerkLightArmorMasterRatingMult | 1.5 |
| 0x1420a8a60 | fPerkLightArmorNoviceDamageMult | 1.5 |
| 0x1420a84f0 | fPersuasionAccuracyMaxDisposition | 1.0 |
| 0x1420a9030 | fPersuasionAccuracyMaxSelect | 100.0 |
| 0x1420a84d8 | fPersuasionAccuracyMinDispostion | 0.05 |
| 0x1420a9018 | fPersuasionAccuracyMinSelect | 0.0 |
| 0x1420a84c0 | fPersuasionBaseValueMaxDisposition | 5.0 |
| 0x1420a9060 | fPersuasionBaseValueMaxSelect | 100.0 |
| 0x1420a84a8 | fPersuasionBaseValueMinDispostion | 0.4 |
| 0x1420a9048 | fPersuasionBaseValueMinSelect | 0.0 |
| 0x1420a8490 | fPersuasionBaseValueShape | 14.5 |
| 0x1420a8430 | fPersuasionMaxDisposition | 50.0 |
| 0x1420a8448 | fPersuasionMaxInput | 100.0 |
| 0x1420a9090 | fPersuasionMaxSelect | 100.0 |
| 0x1420a9000 | fPersuasionMinDispostion | 5.0 |
| 0x1420a8460 | fPersuasionMinInput | 0.0 |
| 0x1420a8478 | fPersuasionMinPercentCircle | 25.0 |
| 0x1420a9078 | fPersuasionMinSelect | 0.0 |
| 0x1420a8418 | fPersuasionShape | 10.0 |
| 0x1420a6b10 | fPhysicsDamage1Damage | 1.0 |
| 0x1420a6ac8 | fPhysicsDamage1Mass | 10.0 |
| 0x1420a6b28 | fPhysicsDamage2Damage | 5.0 |
| 0x1420a6ae0 | fPhysicsDamage2Mass | 50.0 |
| 0x1420a6b40 | fPhysicsDamage3Damage | 10.0 |
| 0x1420a6af8 | fPhysicsDamage3Mass | 100.0 |
| 0x1420a6b58 | fPhysicsDamageSpeedBase | 1.0 |
| 0x1420a6b88 | fPhysicsDamageSpeedMin | 500.0 |
| 0x1420a6b70 | fPhysicsDamageSpeedMult | 0.0001 |
| 0x14209fc30 | fPickLevelBase | 0.0 |
| 0x14209fc48 | fPickLevelMult | 0.0 |
| 0x1420bafa8 | fPickMaxAngle | 90.0 |
| 0x14209fb88 | fPickNumBase | 1.0 |
| 0x14209fba0 | fPickNumMult | 0.1 |
| 0x1420a1190 | fPickPocketActorSkillBase | 40.0 |
| 0x1420a11a8 | fPickPocketActorSkillMult | 0.0 |
| 0x1420a11f0 | fPickPocketAmountBase | 0.0 |
| 0x1420a1208 | fPickPocketAmountMult | -0.05 |
| 0x1420a1220 | fPickPocketDetected | 25.0 |
| 0x1420a1280 | fPickPocketMaxChance | 95.0 |
| 0x1420a1268 | fPickPocketMinChance | 5.0 |
| 0x1420aabc0 | fPickpocketSkillUsesCurve | 1.0 |
| 0x1420a11c0 | fPickPocketTargetSkillBase | 20.0 |
| 0x1420a11d8 | fPickPocketTargetSkillMult | -0.25 |
| 0x1420a1238 | fPickPocketWeightBase | 0.0 |
| 0x1420a1250 | fPickPocketWeightMult | -5.0 |
| 0x14209fbb8 | fPickSpring1 | 5.0 |
| 0x14209fbd0 | fPickSpring2 | 4.0 |
| 0x14209fbe8 | fPickSpring3 | 3.0 |
| 0x14209fc00 | fPickSpring4 | 2.0 |
| 0x14209fc18 | fPickSpring5 | 1.0 |
| 0x1420a47d0 | fPickupItemDistanceFudge | 32.0 |
| 0x14209f180 | fPickUpWeaponDelay | 0.8 |
| 0x1420a47a0 | fPickupWeaponDistanceMinMaxDPSMult | 5.0 |
| 0x1420a4710 | fPickupWeaponMeleeDistanceMax | 1024.0 |
| 0x1420a46f8 | fPickupWeaponMeleeDistanceMin | 256.0 |
| 0x1420a47b8 | fPickupWeaponMeleeWeaponDPSMult | 0.5 |
| 0x1420a46b0 | fPickupWeaponMinDPSImprovementPercent | 0.5 |
| 0x1420a4740 | fPickupWeaponRangedDistanceMax | 2048.0 |
| 0x1420a4728 | fPickupWeaponRangedDistanceMin | 512.0 |
| 0x1420a4788 | fPickupWeaponRangedMeleeDPSRatioThreshold | 0.5 |
| 0x1420a4770 | fPickupWeaponTargetUnreachableDistanceMult | 4.0 |
| 0x1420a46e0 | fPickupWeaponUnarmedDistanceMax | 2048.0 |
| 0x1420a46c8 | fPickupWeaponUnarmedDistanceMin | 256.0 |
| 0x1420a0548 | fPlayerDeathReloadTime | 5.0 |
| 0x1420aa2a8 | fPlayerDetectActorValue | -35.0 |
| 0x1420a1160 | fPlayerDetectionSneakBase | 0.0 |
| 0x1420a1178 | fPlayerDetectionSneakMult | 1.0 |
| 0x1420a9af8 | fPlayerDropDistance | 100.0 |
| 0x1420a86d0 | fPlayerHealthHeartbeatFast | 0.1 |
| 0x1420a86b8 | fPlayerHealthHeartbeatSlow | 0.2 |
| 0x1420a9ae0 | fPlayerMaxResistance | 85.0 |
| 0x1420a4500 | fPlayerTargetCombatDistance | 3000.0 |
| 0x14209f228 | fPlayerTeleportFadeSeconds | 0.001 |
| 0x1420b7360 | fPlayerVelocityCacheTime | 0.05 |
| 0x1420b7348 | fPlayerVelocitySampleInterval | 0.05 |
| 0x1420b7330 | fPlayerVelocitySampleTime | 1.0 |
| 0x1420a5298 | fPowerAttackCoolDownTime | 2.0 |
| 0x1420a5790 | fPowerAttackDefaultBonus | 3.0 |
| 0x1420a7f08 | fPowerAttackStaminaPenalty | 5.0 |
| 0x14209e558 | fPrecipWindMult | 500.0 |
| 0x1420a6420 | fProjectileCollisionImpulseScale | 1.0 |
| 0x1420a74b8 | fProjectileDefaultTracerRange | 10000.0 |
| 0x1420a4938 | fProjectileDeflectionTime | 1.0 |
| 0x1420a6558 | fProjectileInventoryGrenadeFreakoutTime | 0.5 |
| 0x1420a6540 | fProjectileInventoryGrenadeTimer | 2.0 |
| 0x1420a6498 | fProjectileKnockMinMass | 5.0 |
| 0x1420a6468 | fProjectileKnockMultBiped | 1.75 |
| 0x1420a6438 | fProjectileKnockMultClutter | 0.15 |
| 0x1420a6450 | fProjectileKnockMultProp | 1.0 |
| 0x1420a6480 | fProjectileKnockMultTrap | 0.05 |
| 0x1420a63a8 | fProjectileMaxDistance | 32768.0 |
| 0x1420a74d0 | fProjectileReorientTracerMin | 200.0 |
| 0x1420adbf0 | fQuestCinematicCharacterFadeIn | 2.0 |
| 0x1420adc38 | fQuestCinematicCharacterFadeInDelay | 0.1 |
| 0x1420adc08 | fQuestCinematicCharacterFadeOut | 2.0 |
| 0x1420adc20 | fQuestCinematicCharacterRemain | 4.0 |
| 0x1420adc50 | fQuestCinematicObjectiveFadeIn | 0.5 |
| 0x1420adc80 | fQuestCinematicObjectiveFadeInDelay | 1.0 |
| 0x1420adc68 | fQuestCinematicObjectiveFadeOut | 0.5 |
| 0x1420adcb0 | fQuestCinematicObjectivePauseTime | 3.0 |
| 0x1420adc98 | fQuestCinematicObjectiveScrollTime | 0.5 |
| 0x14207b078 | fRandomDoorDistance | 150.0 |
| 0x14209f978 | fRandomSceneAgainMaxTime | 10.0 |
| 0x14209f960 | fRandomSceneAgainMinTime | 5.0 |
| 0x1420a91b0 | fRechargeGoldMult | 2.0 |
| 0x1420a0530 | fReEquipArmorTime | 1.0 |
| 0x1420ab880 | fReflectedAbsorbChanceReduction | 0.5 |
| 0x1420772c0 | fRefTranslationAlmostDonePercent | 0.9 |
| 0x14209f2a0 | fRelationshipBase | 15.0 |
| 0x14209f288 | fRelationshipMult | 0.05 |
| 0x1420a0500 | fRemoteCombatMissedAttack | 4.0 |
| 0x1420a9bb8 | fRemoveExcessComplexDeadTime | 2.5 |
| 0x1420a9b70 | fRemoveExcessDeadTime | 10.0 |
| 0x1420a9138 | fRepairMax | 2.0 |
| 0x1420a9120 | fRepairMin | 0.5 |
| 0x1420a9150 | fRepairScavengeMult | 0.05 |
| 0x1420a9168 | fRepairSkillBase | 4.0 |
| 0x1420a9180 | fRepairSkillMax | 9.0 |
| 0x1420a0890 | fReservationExpirationSeconds | 5.0 |
| 0x1420aec10 | fResetTransitSoundRotationSpeed | 0.3 |
| 0x1420a0818 | fResistArrestTimer | 300.0 |
| 0x1420a65a0 | fRockitDamageBonusWeightMin | 0.0 |
| 0x1420a6588 | fRockitDamageBonusWeightMult | 0.0 |
| 0x14209e7c0 | fRoomLightingTransitionDuration | 3.0 |
| 0x1420a97b0 | fRumbleBlockStrength | 0.5 |
| 0x1420a9798 | fRumbleBlockTime | 0.3 |
| 0x1420a97e0 | fRumbleHitBlockedStrength | 1.0 |
| 0x1420a97c8 | fRumbleHitBlockedTime | 0.3 |
| 0x1420a9810 | fRumbleHitStrength | 0.5 |
| 0x1420a97f8 | fRumbleHitTime | 0.3 |
| 0x1420a9750 | fRumblePainStrength | 0.75 |
| 0x1420a9738 | fRumblePainTime | 0.5 |
| 0x1420a9828 | fRumbleShakeRadiusMult | 1.0 |
| 0x1420a9840 | fRumbleShakeTimeMult | 1.0 |
| 0x1420a9780 | fRumbleStruckStrength | 0.75 |
| 0x1420a9768 | fRumbleStruckTime | 0.3 |
| 0x1420a0950 | fSandBoxDelayEvalSeconds | 5.0 |
| 0x1420a08f0 | fSandBoxExtraDialogueRange | 384.0 |
| 0x1420a0968 | fSandBoxInterMarkerMinDist | 100.0 |
| 0x1420a0908 | fSandBoxRadiusHysteresis | 10.0 |
| 0x1420a08a8 | fSandBoxSearchRadius | 6000.0 |
| 0x1420aa170 | fSayOncePerDayInfoTimer | 12.0 |
| 0x1420ab820 | fScrollCostMult | 0.5 |
| 0x14209e790 | fSecondsBetweenWindowUpdate | 10.0 |
| 0x14209e688 | fSecundaAngleFadeEnd | 40.0 |
| 0x14209e670 | fSecundaAngleFadeStart | 55.0 |
| 0x14209e6a0 | fSecundaAngleShadowEarlyFade | 0.5 |
| 0x14209e6b8 | fSecundaSpeed | 0.3 |
| 0x14209e6d0 | fSecundaZOffset | 50.0 |
| 0x14207b9d8 | fSeenDataUpdateRadius | 1024.0 |
| 0x1420a7e30 | fShieldBaseFactor | 0.08 |
| 0x1420a5e98 | fShieldBashMax | 0.5 |
| 0x1420a5e80 | fShieldBashMin | 0.1 |
| 0x1420a5ec8 | fShieldBashPCMax | 0.5 |
| 0x1420a5eb0 | fShieldBashPCMin | 0.1 |
| 0x1420a7ce0 | fShieldBashSkillUseBase | 5.0 |
| 0x1420a7cf8 | fShieldBashSkillUseMult | 0.0 |
| 0x1420a7e18 | fShieldScalingFactor | 0.25 |
| 0x1420ab598 | fShockBoltGrowWidth | 1.0 |
| 0x1420ab538 | fShockBoltsLength | 1024.0 |
| 0x1420ab580 | fShockBoltSmallWidth | 3.0 |
| 0x1420ab550 | fShockBoltsRadius | 48.0 |
| 0x1420ab568 | fShockBoltsRadiusStrength | 3.0 |
| 0x1420ab700 | fShockBranchBoltsRadius | 24.0 |
| 0x1420ab718 | fShockBranchBoltsRadiusStrength | 3.0 |
| 0x1420ab790 | fShockBranchLifetime | 1.0 |
| 0x1420ab748 | fShockBranchSegmentLength | 32.0 |
| 0x1420ab760 | fShockBranchSegmentVariance | 20.0 |
| 0x1420ab5c8 | fShockCastVOffset | -5.0 |
| 0x1420ab610 | fShockCoreColorB | 1.0 |
| 0x1420ab5f8 | fShockCoreColorG | 1.0 |
| 0x1420ab5e0 | fShockCoreColorR | 1.0 |
| 0x1420ab658 | fShockGlowColorB | 1.0 |
| 0x1420ab640 | fShockGlowColorG | 0.6 |
| 0x1420ab628 | fShockGlowColorR | 0.0 |
| 0x1420ab688 | fShockSegmentLength | 32.0 |
| 0x1420ab6a0 | fShockSegmentVariance | 20.0 |
| 0x1420ab6d0 | fShockSubSegmentVariance | 0.0 |
| 0x1420a0488 | fSittingMaxLookingDown | 40.0 |
| 0x1420aa758 | fSkillUsageLockPickAverage | 3.0 |
| 0x1420aa7a0 | fSkillUsageLockPickBroken | 1.0 |
| 0x1420aa740 | fSkillUsageLockPickEasy | 2.0 |
| 0x1420aa770 | fSkillUsageLockPickHard | 4.0 |
| 0x1420aa728 | fSkillUsageLockPickVeryEasy | 1.0 |
| 0x1420aa788 | fSkillUsageLockPickVeryHard | 5.0 |
| 0x1420aaa28 | fSkillUsageRechargeMult | 1.0 |
| 0x1420aaa10 | fSkillUsageSneakHidden | 2.5 |
| 0x1420aa9f8 | fSkillUsageSneakPerSecond | 0.5 |
| 0x1420a8ca0 | fSkillUseCurve | 1.25 |
| 0x14207ba38 | fSkyCellRefProcessDistanceMult | 10.0 |
| 0x14209ef58 | fSmallBumpSpeed | 300.0 |
| 0x1420aab78 | fSmithingArmorMax | 10.0 |
| 0x1420aab48 | fSmithingConditionFactor | 0.5825 |
| 0x1420aab60 | fSmithingWeaponMax | 10.0 |
| 0x1420a0728 | fSortActorDistanceListTimer | 3.0 |
| 0x142078fa0 | fSpecialLootMaxPCLevelBase | 0.0 |
| 0x142078fb8 | fSpecialLootMaxPCLevelMult | 1.0 |
| 0x142078fd0 | fSpecialLootMaxZoneLevelBase | 0.0 |
| 0x142078fe8 | fSpecialLootMaxZoneLevelMult | 1.5 |
| 0x142078f40 | fSpecialLootMinPCLevelBase | 0.0 |
| 0x142078f58 | fSpecialLootMinPCLevelMult | 0.5 |
| 0x142078f70 | fSpecialLootMinZoneLevelBase | 0.0 |
| 0x142078f88 | fSpecialLootMinZoneLevelMult | 0.5 |
| 0x142079000 | fSpecialLootWeighting | 4.0 |
| 0x1420a8388 | fSpeechCraftBase | 100.0 |
| 0x1420a1430 | fSpeechcraftFavorMax | 1.0 |
| 0x1420a1418 | fSpeechcraftFavorMin | 0.5 |
| 0x1420a83a0 | fSpeechCraftMult | 1.0 |
| 0x1420b0328 | fSpeechDelay | 0.0 |
| 0x1420aac20 | fSpellmakingGoldMult | 1.0 |
| 0x1420a94f8 | fSplashScale1 | 1.0 |
| 0x1420a9510 | fSplashScale2 | 0.75 |
| 0x1420a9528 | fSplashScale3 | 0.4 |
| 0x1420a9450 | fSplashSoundHeavy | 50.0 |
| 0x1420a9480 | fSplashSoundLight | 5.0 |
| 0x1420a9468 | fSplashSoundMedium | 25.0 |
| 0x1420a94c8 | fSplashSoundOutMult | 0.5 |
| 0x1420a9498 | fSplashSoundTimer | 0.25 |
| 0x1420a94b0 | fSplashSoundVelocityMult | 0.05 |
| 0x142079340 | fSprayDecalsDistance | 64.0 |
| 0x142079358 | fSprayDecalsGravity | 128.0 |
| 0x1420aa4d0 | fSprintEncumbranceMult | 1.0 |
| 0x1420a8b68 | fSprintStaminaDrainMult | 15.0 |
| 0x1420aab90 | fSprintStaminaWeightBase | 1.0 |
| 0x1420aaba8 | fSprintStaminaWeightMult | 0.0 |
| 0x14207b498 | fStagger1WeapAR | 10.0 |
| 0x1420a6138 | fStagger1WeapMult | 0.2 |
| 0x14207b4b0 | fStagger2WeapAR | 15.0 |
| 0x1420a6150 | fStagger2WeapMult | 0.5 |
| 0x1420a6090 | fStaggerAttackBase | 0.5 |
| 0x1420a60a8 | fStaggerAttackMult | 0.01 |
| 0x1420a61b0 | fStaggerBlockAttackBase | 1.0 |
| 0x1420a61c8 | fStaggerBlockAttackMult | -0.005 |
| 0x1420a61e0 | fStaggerBlockAttackShieldBase | 1.0 |
| 0x1420a61f8 | fStaggerBlockAttackShieldMult | -0.005 |
| 0x1420a60c0 | fStaggerBlockBase | 0.5 |
| 0x1420a6168 | fStaggerBlockingMult | 1.0 |
| 0x1420a60d8 | fStaggerBlockMult | 0.005 |
| 0x14207b4c8 | fStaggerBowAR | 5.0 |
| 0x14207b480 | fStaggerDaggerAR | 5.0 |
| 0x1420a60f0 | fStaggerMassBase | 0.0 |
| 0x1420a6108 | fStaggerMassMult | 1.0 |
| 0x1420a7e90 | fStaggerMassOffsetBase | 3.0 |
| 0x1420a7ea8 | fStaggerMassOffsetMult | 0.15 |
| 0x1420a6fa8 | fStaggerMaxDuration | 3.0 |
| 0x1420a7cc8 | fStaggerMin | 0.05 |
| 0x1420a7ec0 | fStaggerPlayerMassMult | 2.0 |
| 0x1420a6198 | fStaggerRecoilingMult | 1.5 |
| 0x1420a6180 | fStaggerRunningMult | 1.5 |
| 0x1420a6120 | fStaggerShieldMult | 1.0 |
| 0x1420a7ed8 | fStaminaAttackWeaponBase | 7.0 |
| 0x1420a7ef0 | fStaminaAttackWeaponMult | 0.1 |
| 0x1420a7bc0 | fStaminaBashBase | 5.0 |
| 0x1420a7ba8 | fStaminaBlockBase | 10.0 |
| 0x1420a7b78 | fStaminaBlockDmgMult | 0.25 |
| 0x1420a7b90 | fStaminaBlockStaggerMult | 5.0 |
| 0x1420a7bd8 | fStaminaPowerBashBase | 10.0 |
| 0x1420a12e0 | fStaminaRegenDelayMax | 5.0 |
| 0x14209e868 | fStarsRotateDays | 4.0 |
| 0x14209e880 | fStarsRotateXAxis | 0.0 |
| 0x14209e898 | fStarsRotateYAxis | 0.0 |
| 0x14209e8b0 | fStarsRotateZAxis | 1.0 |
| 0x1420adba8 | fStatsCameraFOV | 50.0 |
| 0x1420aeb68 | fStatsCameraNearDistance | 1.0 |
| 0x1420a8ef8 | fStatsHealthLevelMult | 0.1 |
| 0x1420a8ee0 | fStatsHealthStartMult | 0.5 |
| 0x1420adb90 | fStatsLineScale | 0.1175 |
| 0x1420aeb08 | fStatsRotationRampTime | 2000.0 |
| 0x1420ada70 | fStatsRotationSpeedMax | 0.5 |
| 0x1420aeb20 | fStatsSkillsLookAtX | 0.0 |
| 0x1420aeb38 | fStatsSkillsLookAtY | 0.0 |
| 0x1420aeb50 | fStatsSkillsLookAtZ | 5.0 |
| 0x1420adae8 | fStatsStarCameraOffsetX | 0.0 |
| 0x1420adb00 | fStatsStarCameraOffsetY | -8.0 |
| 0x1420adb18 | fStatsStarCameraOffsetZ | 0.0 |
| 0x1420adb30 | fStatsStarLookAtX | 0.0 |
| 0x1420adb48 | fStatsStarLookAtY | 0.0 |
| 0x1420adb60 | fStatsStarLookAtZ | 1.0 |
| 0x1420adb78 | fStatsStarScale | 0.15 |
| 0x1420ada88 | fStatsStarXIncrement | 5.0 |
| 0x1420adaa0 | fStatsStarYIncrement | 15.0 |
| 0x1420adab8 | fStatsStarZIncrement | -9.0 |
| 0x1420adad0 | fStatsStarZInitialOffset | 5.0 |
| 0x1420a9438 | fSubmergedAngularDamping | 0.75 |
| 0x1420a9408 | fSubmergedLinearDampingH | 2.0 |
| 0x1420a9420 | fSubmergedLinearDampingV | 4.0 |
| 0x1420a93d8 | fSubmergedLODDistance | 384.0 |
| 0x1420a93c0 | fSubmergedMaxSpeed | 2.0 |
| 0x1420a93f0 | fSubmergedMaxWaterDistance | 48.0 |
| 0x1420ab778 | fSubSegmentVariance | 0.0 |
| 0x1420adbd8 | fSubtitleSpeechDelay | 1.5 |
| 0x14209f258 | fSummonedCreatureFadeOutSeconds | 3.0 |
| 0x1420a0e18 | fSummonedCreatureMaxFollowDist | 400.0 |
| 0x1420a0e00 | fSummonedCreatureMinFollowDist | 200.0 |
| 0x1420ab868 | fSummonedCreatureSearchRadius | 512.0 |
| 0x14209e940 | fSunAlphaTransTime | 2.0 |
| 0x14209e9a0 | fSunDirXExtreme | 400.0 |
| 0x14209e910 | fSunMinimumGlareScale | 0.25 |
| 0x14209e928 | fSunReduceGlareSpeed | 4.0 |
| 0x14209e958 | fSunXExtreme | 400.0 |
| 0x14209e970 | fSunYExtreme | 25.0 |
| 0x14209e988 | fSunZExtreme | -100.0 |
| 0x1420a1568 | fSurvArmorScalar | 1.0 |
| 0x1420a1508 | fSurvColdBodyBonus | 17.0 |
| 0x1420a1550 | fSurvColdFeetBonus | 7.0 |
| 0x1420a1538 | fSurvColdHandsBonus | 7.0 |
| 0x1420a1520 | fSurvColdHeadBonus | 8.0 |
| 0x1420a1448 | fSurvNormalBodyBonus | 27.0 |
| 0x1420a1490 | fSurvNormalFeetBonus | 13.0 |
| 0x1420a1478 | fSurvNormalHandsBonus | 13.0 |
| 0x1420a1460 | fSurvNormalHeadBonus | 18.0 |
| 0x1420a1580 | fSurvTorchBonus | 50.0 |
| 0x1420a14a8 | fSurvWarmBodyBonus | 54.0 |
| 0x1420a14f0 | fSurvWarmFeetBonus | 24.0 |
| 0x1420a14d8 | fSurvWarmHandsBonus | 24.0 |
| 0x1420a14c0 | fSurvWarmHeadBonus | 29.0 |
| 0x1420aa830 | fSweetSpotAverage | 8.0 |
| 0x1420aa818 | fSweetSpotEasy | 17.0 |
| 0x1420aa848 | fSweetSpotHard | 5.0 |
| 0x1420aa800 | fSweetSpotVeryEasy | 35.0 |
| 0x1420aa860 | fSweetSpotVeryHard | 3.0 |
| 0x1420a0788 | fTakeBackTimerSetting | 20.0 |
| 0x1420a4968 | fTargetMovedCoveredMoveRepathLength | 256.0 |
| 0x1420a4950 | fTargetMovedRepathLength | 64.0 |
| 0x1420a4980 | fTargetMovedRepathLengthLow | 2048.0 |
| 0x1420b2bb0 | fTargetSearchRadius | 20000.0 |
| 0x14209f630 | fTeammateAggroOnDistancefromPlayer | 4000.0 |
| 0x1420a0368 | fTeleportDoorActivateDelayTimer | 0.0 |
| 0x1420aab30 | fTemperingSkillUseItemValConst | 0.0 |
| 0x1420aab18 | fTemperingSkillUseItemValExp | 0.3 |
| 0x1420aab00 | fTemperingSkillUseItemValMult | 0.5 |
| 0x1420aaae8 | fTemperingSkillUseMult | 15.0 |
| 0x1420aa380 | fTimerForPlayerFurnitureEnter | 3.0 |
| 0x14207a678 | fTimeSpanAfternoonEnd | 16.0 |
| 0x14207a660 | fTimeSpanAfternoonStart | 12.0 |
| 0x14207a6c0 | fTimeSpanEveningEnd | 18.5 |
| 0x14207a6a8 | fTimeSpanEveningStart | 16.0 |
| 0x14207a798 | fTimeSpanMidnightEnd | 6.0 |
| 0x14207a780 | fTimeSpanMidnightStart | 0.0 |
| 0x14207a630 | fTimeSpanMorningEnd | 12.0 |
| 0x14207a618 | fTimeSpanMorningStart | 9.0 |
| 0x14207a750 | fTimeSpanNightEnd | 0.0 |
| 0x14207a738 | fTimeSpanNightStart | 21.0 |
| 0x14207a5e8 | fTimeSpanSunriseEnd | 9.0 |
| 0x14207a5d0 | fTimeSpanSunriseStart | 6.0 |
| 0x14207a708 | fTimeSpanSunsetEnd | 21.0 |
| 0x14207a6f0 | fTimeSpanSunsetStart | 18.0 |
| 0x1420a8520 | fTorchEvaluationTimer | 5.0 |
| 0x1420a8fb8 | fTorchLightLevelInterior | 40.0 |
| 0x1420a8f88 | fTorchLightLevelMorning | 0.6 |
| 0x1420a8fa0 | fTorchLightLevelNight | 1.2 |
| 0x1420b0430 | fTrackDeadZoneXY | 20.0 |
| 0x1420b0448 | fTrackDeadZoneZ | 10.0 |
| 0x1420b0400 | fTrackEyeXY | 28.0 |
| 0x1420b0418 | fTrackEyeZ | 20.0 |
| 0x1420b0460 | fTrackFudgeXY | 0.0 |
| 0x1420b0478 | fTrackFudgeZ | 0.0 |
| 0x1420b0490 | fTrackJustAcquiredDuration | 2.0 |
| 0x1420b03e8 | fTrackMaxZ | 60.0 |
| 0x1420b03d0 | fTrackMinZ | -60.0 |
| 0x1420b03a0 | fTrackSpeed | 2.0 |
| 0x1420b03b8 | fTrackXY | 60.0 |
| 0x1420aa350 | fTrainingBaseCost | 50.0 |
| 0x1420aa368 | fTrainingMultCost | 2.0 |
| 0x14209eeb0 | fTriggerAvoidPlayerDistance | 400.0 |
| 0x1420a7890 | fUnarmedCreatureDPSMult | 1.0 |
| 0x1420a78a8 | fUnarmedDamageMult | 0.5 |
| 0x1420a7878 | fUnarmedNPCDPSMult | 1.57 |
| 0x14209e7a8 | fUnderwaterFullDepth | 1000.0 |
| 0x1420a8568 | fValueofItemForNoOwnership | 45.0 |
| 0x1420a5778 | fVATSAutomaticMeleeDamageMult | 2.0 |
| 0x14207bed0 | fVATSCameraCutAwayDistance | 25.0 |
| 0x14207beb8 | fVATSCameraDollyMin | 256.0 |
| 0x14207bea0 | fVATSCameraDollyTime | 1.0 |
| 0x1420a5580 | fVATSCameraMinTime | 0.0 |
| 0x1420a5640 | fVATSCamTransRBDownStart | 0.0 |
| 0x1420a5628 | fVATSCamTransRBRampDown | 0.0 |
| 0x1420a55f8 | fVATSCamTransRBRampup | 2.0 |
| 0x1420a5610 | fVATSCamTransRBStart | 0.0 |
| 0x1420a55e0 | fVATSCamTransRBStrengthCap | 0.5 |
| 0x1420ad8f0 | fVATSCamZoomInTime | 0.75 |
| 0x1420a5730 | fVATSCriticalChanceBonus | 15.0 |
| 0x1420a78c0 | fVATSDamageToWeaponMult | 2.0 |
| 0x1420a7ae8 | fVATSDestructibleMult | 1.25 |
| 0x1420a79f8 | fVATSDistanceFactor | 2.0 |
| 0x1420a5400 | fVATSDOFRange | 300.0 |
| 0x1420a53e8 | fVATSDOFStrengthCap | 1.0 |
| 0x1420a53d0 | fVATSDOFSwitchSeconds | 0.15 |
| 0x1420a7b00 | fVATSGrenadeChanceMult | 1.0 |
| 0x1420a5598 | fVATSGrenadeDistAimZMult | 0.4 |
| 0x1420a7b30 | fVATSGrenadeRangeMin | 128.0 |
| 0x1420a7b18 | fVATSGrenadeRangeMult | 2.0 |
| 0x1420a7b48 | fVATSGrenadeSkillFactor | 0.4 |
| 0x1420a5700 | fVATSGrenadeSuccessExplodeTimer | 0.0 |
| 0x1420a5718 | fVATSGrenadeSuccessMaxDistance | 75.0 |
| 0x1420a7ab8 | fVATSGrenadeTargetArea | 25.0 |
| 0x1420a7ad0 | fVATSGrenadeTargetMelee | 0.75 |
| 0x1420a5748 | fVATSH2HWarpDistanceMult | 0.5 |
| 0x1420a79e0 | fVATSHitChanceMult | 1.0 |
| 0x1420a55b0 | fVATSImageSpaceTransitionTime | 0.15 |
| 0x1420ad908 | fVATSLimbSelectCamPanTime | 0.3 |
| 0x1420a79b0 | fVATSMaxChance | 95.0 |
| 0x1420ad920 | fVATSMaxEngageDistance | 5000.0 |
| 0x1420a7a88 | fVATSMeleeArmConditionBase | 0.2 |
| 0x1420a7a70 | fVATSMeleeArmConditionMult | 0.8 |
| 0x1420a7a40 | fVATSMeleeChanceMult | 1.0 |
| 0x1420a7848 | fVATSMeleeMaxDistance | 300.0 |
| 0x1420a5670 | fVATSMeleeReachMult | 2.0 |
| 0x1420a5760 | fVATSMeleeWarpDistanceMult | 0.5 |
| 0x1420a6390 | fVATSMoveCameraLimbMult | 0.35 |
| 0x1420a6378 | fVATSMoveCameraLimbPercent | 0.1 |
| 0x1420a6360 | fVATSMoveCameraMaxSpeed | 20000.0 |
| 0x1420a6330 | fVATSMoveCameraXPercent | 0.0 |
| 0x1420a6348 | fVATSMoveCameraYPercent | 0.15 |
| 0x1420a56e8 | fVATSParalyzePalmChance | 0.1 |
| 0x1420a55c8 | fVATSPlaybackDelay | 3.0 |
| 0x1420a5658 | fVATSPlayerDamageMult | 1.0 |
| 0x1420a54c0 | fVATSPlayerMagicTimeSlowdownMult | 0.8 |
| 0x1420a54d8 | fVATSPlayerTimeUpdateMult | 3.0 |
| 0x1420a5430 | fVATSRadialRampup | 5.0 |
| 0x1420a5448 | fVATSRadialStart | 0.3 |
| 0x1420a5418 | fVATSRadialStrength | 0.25 |
| 0x1420a79c8 | fVATSRangeSpreadMax | 2.0 |
| 0x1420a7b60 | fVATSRangeSpreadUncertainty | 0.2 |
| 0x1420a5550 | fVATSSafetyMaxTime | 20.0 |
| 0x1420a5568 | fVATSSafetyMaxTimeRanged | 6.0 |
| 0x1420a7a28 | fVATSScreenPercentFactor | 1.0 |
| 0x1420a5508 | fVATSShotBurstTime | 0.43 |
| 0x1420a56d0 | fVatsShotgunSpreadRatio | 1.0 |
| 0x1420a5520 | fVATSShotLongBurstTime | 0.75 |
| 0x1420a7a58 | fVATSSkillFactor | 1.0 |
| 0x1420aa290 | fVATSSmartCameraCheckHeight | 96.0 |
| 0x1420aa278 | fVATSSmartCameraCheckStepCount | 5.0 |
| 0x1420aa260 | fVATSSmartCameraCheckStepDistance | 128.0 |
| 0x1420a7a10 | fVATSSpreadMult | 1.0 |
| 0x1420a7aa0 | fVATSStealthMult | 0.5 |
| 0x1420a5688 | fVATSStrangerDistance | 192.0 |
| 0x1420a56a0 | fVATSStrangerOdds | 0.1 |
| 0x1420a6318 | fVATSTargetActorHeightPanMult | 0.2 |
| 0x1420a62e8 | fVATSTargetActorZMultFar | 0.2 |
| 0x1420a6300 | fVATSTargetActorZMultFarDist | 175.0 |
| 0x1420a62d0 | fVATSTargetActorZMultNear | 0.8 |
| 0x1420a6270 | fVATSTargetFOVMinDist | 150.0 |
| 0x1420a6288 | fVATSTargetFOVMinFOV | 1.5 |
| 0x1420a6240 | fVATSTargetFOVMultFar | 30.0 |
| 0x1420a6258 | fVATSTargetFOVMultFarDist | 1750.0 |
| 0x1420a6228 | fVATSTargetFOVMultNear | 46.0 |
| 0x1420a62a0 | fVATSTargetRotateMult | 0.4 |
| 0x1420a62b8 | fVATSTargetScanRotateMult | 0.7 |
| 0x1420ad8d8 | fVATSTargetSelectCamPanTime | 0.75 |
| 0x1420a54f0 | fVATSTargetTimeUpdateMult | 1.0 |
| 0x1420a7998 | fVATSThrownWeaponRangeMult | 2.0 |
| 0x1420a12b0 | fVoiceRateBase | 5.0 |
| 0x14209eb20 | fWarningTimer | 5.0 |
| 0x14209f150 | fWaterKnockdownSizeLarge | 0.75 |
| 0x14209f138 | fWaterKnockdownSizeNormal | 0.5 |
| 0x14209f120 | fWaterKnockdownSizeSmall | 0.25 |
| 0x14209f168 | fWaterKnockdownSizeVeryLarge | 1.0 |
| 0x14209f108 | fWaterKnockdownVelocity | 10.0 |
| 0x1420a5ef8 | fWeaponBashMax | 0.5 |
| 0x1420a5ee0 | fWeaponBashMin | 0.1 |
| 0x1420a5f28 | fWeaponBashPCMax | 0.5 |
| 0x1420a5f10 | fWeaponBashPCMin | 0.1 |
| 0x1420a7d10 | fWeaponBashSkillUseBase | 1.0 |
| 0x1420a7d28 | fWeaponBashSkillUseMult | 0.0 |
| 0x1420a7de8 | fWeaponBlockSkillUseBase | 0.0 |
| 0x1420a7e00 | fWeaponBlockSkillUseMult | 1.0 |
| 0x1420b2fd8 | fWeaponBloodAlphaToRGBScale | 0.85 |
| 0x1420b2fa8 | fWeaponBloodFadeDuration | 2.0 |
| 0x1420b2fc0 | fWeaponBloodFalloffThreshold | 0.3 |
| 0x1420b2f90 | fWeaponBloodLifetime | 10.0 |
| 0x1420a6690 | fWeaponClutterKnockBipedScale | 5.0 |
| 0x1420a6660 | fWeaponClutterKnockMaxWeaponMass | 5.0 |
| 0x1420a6678 | fWeaponClutterKnockMinClutterMass | 15.0 |
| 0x1420a6648 | fWeaponClutterKnockMult | 750.0 |
| 0x1420a7830 | fWeaponConditionCriticalChanceMult | 0.1 |
| 0x1420a57c0 | fWeaponConditionJam1 | 0.4 |
| 0x1420a5898 | fWeaponConditionJam10 | 0.0 |
| 0x1420a57d8 | fWeaponConditionJam2 | 0.2 |
| 0x1420a57f0 | fWeaponConditionJam3 | 0.1 |
| 0x1420a5808 | fWeaponConditionJam4 | 0.05 |
| 0x1420a5820 | fWeaponConditionJam5 | 0.0 |
| 0x1420a5838 | fWeaponConditionJam6 | 0.0 |
| 0x1420a5850 | fWeaponConditionJam7 | 0.0 |
| 0x1420a5868 | fWeaponConditionJam8 | 0.0 |
| 0x1420a5880 | fWeaponConditionJam9 | 0.0 |
| 0x1420a58b0 | fWeaponConditionRateOfFire1 | 0.5 |
| 0x1420a5988 | fWeaponConditionRateOfFire10 | 1.0 |
| 0x1420a58c8 | fWeaponConditionRateOfFire2 | 0.55 |
| 0x1420a58e0 | fWeaponConditionRateOfFire3 | 0.6 |
| 0x1420a58f8 | fWeaponConditionRateOfFire4 | 0.65 |
| 0x1420a5910 | fWeaponConditionRateOfFire5 | 0.7 |
| 0x1420a5928 | fWeaponConditionRateOfFire6 | 0.75 |
| 0x1420a5940 | fWeaponConditionRateOfFire7 | 0.8 |
| 0x1420a5958 | fWeaponConditionRateOfFire8 | 0.85 |
| 0x1420a5970 | fWeaponConditionRateOfFire9 | 0.9 |
| 0x1420a59a0 | fWeaponConditionReloadJam1 | 1.0 |
| 0x1420a5a78 | fWeaponConditionReloadJam10 | 0.0 |
| 0x1420a59b8 | fWeaponConditionReloadJam2 | 0.75 |
| 0x1420a59d0 | fWeaponConditionReloadJam3 | 0.5 |
| 0x1420a59e8 | fWeaponConditionReloadJam4 | 0.25 |
| 0x1420a5a00 | fWeaponConditionReloadJam5 | 0.1 |
| 0x1420a5a18 | fWeaponConditionReloadJam6 | 0.0 |
| 0x1420a5a30 | fWeaponConditionReloadJam7 | 0.0 |
| 0x1420a5a48 | fWeaponConditionReloadJam8 | 0.0 |
| 0x1420a5a60 | fWeaponConditionReloadJam9 | 0.0 |
| 0x1420a5a90 | fWeaponConditionSpread1 | 1.0 |
| 0x1420a5b68 | fWeaponConditionSpread10 | 0.0 |
| 0x1420a5aa8 | fWeaponConditionSpread2 | 0.8 |
| 0x1420a5ac0 | fWeaponConditionSpread3 | 0.7 |
| 0x1420a5ad8 | fWeaponConditionSpread4 | 0.6 |
| 0x1420a5af0 | fWeaponConditionSpread5 | 0.5 |
| 0x1420a5b08 | fWeaponConditionSpread6 | 0.4 |
| 0x1420a5b20 | fWeaponConditionSpread7 | 0.3 |
| 0x1420a5b38 | fWeaponConditionSpread8 | 0.2 |
| 0x1420a5b50 | fWeaponConditionSpread9 | 0.1 |
| 0x1420a7c38 | fWeaponTwoHandedAnimationSpeedMult | 1.5 |
| 0x14209e538 | fWeatherCloudSpeedMax | 0.1 |
| 0x14209e778 | fWeatherFlashAmbient | 0.3 |
| 0x14209e760 | fWeatherFlashDirectional | 1.0 |
| 0x14209e748 | fWeatherFlashDuration | 0.25 |
| 0x14209e730 | fWeatherTransAccel | 4.0 |
| 0x14209e700 | fWeatherTransMax | 0.25 |
| 0x14209e718 | fWeatherTransMin | 0.01 |
| 0x1420ab0e8 | fWortalchmult | 1.0 |
| 0x1420ab088 | fWortcraftChanceIntDenom | 5.0 |
| 0x1420ab0a0 | fWortcraftChanceLuckDenom | 10.0 |
| 0x1420ab0b8 | fWortcraftStrChanceDenom | 4.0 |
| 0x1420ab0d0 | fWortcraftStrCostDenom | 10.0 |
| 0x1420ab118 | fWortFailSkillUseMagnitude | 1.0 |
| 0x1420ab100 | fWortStrMult | 0.2 |
| 0x1420a8cb8 | fXPLevelUpBase | 170.0 |
| 0x1420a8cd0 | fXPLevelUpMult | 30.0 |
| 0x1420a8ce8 | fXPPerSkillRank | 1.0 |
| 0x1420aa0f8 | fZKeyComplexHelperMinDistance | 6.0 |
| 0x1420aa110 | fZKeyComplexHelperScale | 2.0 |
| 0x1420aa128 | fZKeyComplexHelperWeightMax | 100.0 |
| 0x1420aa140 | fZKeyComplexHelperWeightMin | 0.0 |
| 0x1420aa158 | fZKeyHeavyWeight | 75.0 |
| 0x1420aa0e0 | fZKeyMaxContactDistance | 10.0 |
| 0x1420aa0c8 | fZKeyMaxContactMassRatio | 4.0 |
| 0x1420aa050 | fZKeyMaxForce | 250.0 |
| 0x1420aa068 | fZKeyMaxForceScaleHigh | 1.0 |
| 0x1420aa080 | fZKeyMaxForceScaleLow | 0.2 |
| 0x1420aa098 | fZKeyMaxForceWeightHigh | 300.0 |
| 0x1420aa0b0 | fZKeyMaxForceWeightLow | 0.0 |
| 0x1420aa038 | fZKeyObjectDamping | 0.75 |
| 0x1420aa008 | fZKeySpringDamping | 0.5 |
| 0x1420aa020 | fZKeySpringElasticity | 0.2 |

## Game settings: the integers (i*, b*)

The value compiled into `SkyrimSE.exe` for each game setting (GMST) it knows: what the game uses when `Skyrim.esm` has no record of that name (the plugin's record wins). `game/sim/settings.zap` keeps the few the port reads; this is the whole table.

Read from the static `SettingT<GameSettingCollection>` objects in `.data` (24 bytes: the vtable, the value, the pointer to the name; the vtable's RTTI names the class), found by scanning `.data` for pointers to names and checked against REA's `read_bytes` at 0x1420d9078 (fShadowBiasScale:Display). The address is the object's; the value is decoded by the name's type letter (f float, i int, u unsigned, b bool, s string, r and a 32-bit colors).

| address | setting | value |
|---|---|---|
| 0x1420a52b0 | bAutoAimBasedOnDistance | 0 |
| 0x1420a9708 | bRegenNPCMagickaDuringCast | 1 |
| 0x1420a9b10 | iActivatePickLength | 150 |
| 0x14209ea90 | iActorKeepTurnDegree | 10 |
| 0x1420a87c0 | iActorLuckSkillBase | -20 |
| 0x1420a03c8 | iActorTorsoMaxRotation | 45 |
| 0x1420a69a8 | iAICombatMaxAllySummonCount | 3 |
| 0x1420a6a50 | iAICombatMinDetection | -50 |
| 0x1420a6a08 | iAICombatRestoreHealthPercentage | 30 |
| 0x1420a6a20 | iAICombatRestoreMagickaPercentage | 30 |
| 0x1420a4440 | iAIFleeMaxHitCount | 3 |
| 0x14209f918 | iAIMaxSocialDistanceToTriggerEvent | 500 |
| 0x1420a63c0 | iAimingNumIterations | 10 |
| 0x1420a6780 | iAINPCRacePowerChance | 5 |
| 0x1420a06f8 | iAINumberActorsComplexScene | 20 |
| 0x1420a0fc8 | iAINumberDaysToStayBribed | 1 |
| 0x1420a0fb0 | iAINumberDaysToStayIntimidated | 1 |
| 0x14209f900 | iAISocialDistanceToTriggerEvent | 90 |
| 0x14209fd38 | iAlertAgressionMin | 50 |
| 0x1420af678 | iAllowAlchemyDuringCombat | 0 |
| 0x1420af648 | iAllowRechargeDuringCombat | 1 |
| 0x1420af660 | iAllowRepairDuringCombat | 0 |
| 0x14209f840 | iAllyHitCombatAllowed | 1000 |
| 0x14209f858 | iAllyHitNonCombatAllowed | 3 |
| 0x1420a87f0 | iArmorBaseSkill | 50 |
| 0x1420a5c88 | iArmorDamageBootsChance | 10 |
| 0x1420a5c28 | iArmorDamageCuirassChance | 25 |
| 0x1420a5c70 | iArmorDamageGauntletsChance | 10 |
| 0x1420a5c40 | iArmorDamageGreavesChance | 15 |
| 0x1420a5c58 | iArmorDamageHelmChance | 10 |
| 0x1420a5ca0 | iArmorDamageShieldChance | 30 |
| 0x14207b018 | iArmorWeightBoots | 20 |
| 0x14207afd0 | iArmorWeightCuirass | 30 |
| 0x14207b000 | iArmorWeightGauntlets | 5 |
| 0x14207afe8 | iArmorWeightGreaves | 15 |
| 0x14207afb8 | iArmorWeightHelmet | 5 |
| 0x14207b030 | iArmorWeightShield | 15 |
| 0x1420a07b8 | iArrestOnSightNonViolent | 1000 |
| 0x1420a07d0 | iArrestOnSightViolent | 999 |
| 0x1420a63d8 | iArrowInventoryChance | 50 |
| 0x1420a7320 | iArrowMaxCount | 32 |
| 0x1420a07e8 | iAttackOnSightNonViolent | 0 |
| 0x1420a0800 | iAttackOnSightViolent | 2999 |
| 0x1420ae598 | iAttractModeIdleTime | 90 |
| 0x14209ca68 | iAVDAutoCalcSkillMax | 100 |
| 0x14209ca98 | iAVDhmsLevelUp | 10 |
| 0x14209ca80 | iAVDSkillsLevelUp | 10 |
| 0x14209cab0 | iAVDSkillStart | 15 |
| 0x1420a45a8 | iAvoidHurtingNonTargetsResponsibility | 50 |
| 0x1420a4998 | iBallisticProjectilePathPickSegments | 4 |
| 0x1420780f0 | iBaseDisposition | 35 |
| 0x1420a6dc8 | iBloodSplatterMaxCount | 10 |
| 0x14209f1f8 | iBoneLODDistMult | 1000 |
| 0x14209c900 | iBrowMorphCount | 10 |
| 0x14207bcc0 | iCalcLevelAdjustDown | 1 |
| 0x14207bcd8 | iCalcLevelAdjustUp | 1 |
| 0x1420a9858 | iClassAcrobat | 145320 |
| 0x1420a9870 | iClassAgent | 145298 |
| 0x1420a99a8 | iClassArcher | 145291 |
| 0x1420a9888 | iClassAssassin | 145299 |
| 0x1420a9960 | iClassBarbarian | 145288 |
| 0x1420a9900 | iClassBard | 116772 |
| 0x1420a9a20 | iClassBattlemage | 145815 |
| 0x1420a9a80 | iClassCharactergenClass | 143590 |
| 0x1420a9978 | iClassCrusader | 145289 |
| 0x1420a98d0 | iClassHealer | 2320 |
| 0x1420a98b8 | iClassKnight | 2102 |
| 0x1420a98e8 | iClassMage | 67030 |
| 0x1420a99f0 | iClassMonk | 145321 |
| 0x1420a9a68 | iClassNightblade | 146440 |
| 0x1420a98a0 | iClassPilgrim | 2098 |
| 0x1420a9930 | iClassPriest | 145285 |
| 0x1420a99c0 | iClassRogue | 145292 |
| 0x1420a9990 | iClassScout | 145290 |
| 0x1420a9a08 | iClassSorcerer | 145324 |
| 0x1420a9a50 | iClassSpellsword | 146439 |
| 0x1420a99d8 | iClassThief | 145295 |
| 0x1420a9948 | iClassWarrior | 145287 |
| 0x1420a9a38 | iClassWitchhunter | 145816 |
| 0x1420aba30 | iCommonSoulActorLevel | 8 |
| 0x14209eac0 | iCurrentTargetBonus | 50 |
| 0x14209c648 | iDaysToRespawnVendor | 1 |
| 0x1420a8fe8 | iDeathDropWeaponChance | 0 |
| 0x1420a6030 | iDebrisMaxCount | 25 |
| 0x14209efd0 | iDetectEventLightLevelExterior | 75 |
| 0x14209efe8 | iDetectEventLightLevelInterior | 225 |
| 0x1420b0e80 | iDifficultyLevelMax | 5 |
| 0x1420a6c60 | iDismemberBloodDecalCount | 10 |
| 0x1420a0740 | iDispKaramMax | 20 |
| 0x14209ead8 | iDistancetoAttackedTarget | 384 |
| 0x1420a0440 | iDragonFastTravelMinDistance | 10000 |
| 0x1420a0410 | iDragonOrbitMarkerReference | 126833 |
| 0x1420a0428 | iDragonPatrolMarkerReference | 233730 |
| 0x1420bac98 | iEnemyHealthDisplayAngle:Interface | 90 |
| 0x1420bac80 | iEnemyHealthDisplayTime:Interface | 2000 |
| 0x1420b9408 | iExplosionDebug | 0 |
| 0x14209c918 | iEyeMorphCount | 10 |
| 0x1420a8b50 | iFallLegDamageChance | 50 |
| 0x14209f3a8 | iFavorAllyValue | 300 |
| 0x14209f3c0 | iFavorConfidantValue | 200 |
| 0x14209f3d8 | iFavorFriendValue | 100 |
| 0x1420bacb0 | iFavoritesDisplayTime:Interface | 3000 |
| 0x14209f390 | iFavorLoverValue | 400 |
| 0x14209f480 | iFavorPointsRestore | 4 |
| 0x142079048 | iFloraEmptyAlpha | 160 |
| 0x142079060 | iFloraFullAlpha | 128 |
| 0x14209f810 | iFriendHitCombatAllowed | 3 |
| 0x14209f828 | iFriendHitNonCombatAllowed | 0 |
| 0x1420a9ee8 | iGameplayiSpeakingEmotionDeltaChange | 10 |
| 0x1420a9f00 | iGameplayiSpeakingEmotionListenValue | 50 |
| 0x1420aba60 | iGrandSoulActorLevel | 19 |
| 0x1420aba48 | iGreaterSoulActorLevel | 14 |
| 0x1420a0758 | iGuardWarnings | 2 |
| 0x1420ad008 | iHairColor00 | 8289918 |
| 0x1420ad020 | iHairColor01 | 3618617 |
| 0x1420ad038 | iHairColor02 | 2039585 |
| 0x1420ad050 | iHairColor03 | 4289146 |
| 0x1420ad068 | iHairColor04 | 4680837 |
| 0x1420ad080 | iHairColor05 | 3557724 |
| 0x1420ad098 | iHairColor06 | 3360589 |
| 0x1420ad0b0 | iHairColor07 | 2830157 |
| 0x1420ad0c8 | iHairColor08 | 2965094 |
| 0x1420ad0e0 | iHairColor09 | 4287105 |
| 0x1420ad0f8 | iHairColor10 | 1000298 |
| 0x1420ad110 | iHairColor11 | 1974080 |
| 0x1420ad128 | iHairColor12 | 2958114 |
| 0x1420ad140 | iHairColor13 | 2239537 |
| 0x1420ad158 | iHairColor14 | 7237230 |
| 0x1420ad170 | iHairColor15 | 5400188 |
| 0x1420a8ac0 | iHorseTurnDegreesPerSecond | 45 |
| 0x1420a8ad8 | iHorseTurnDegreesRampUpPerSecond | 80 |
| 0x14207b9f0 | iHoursToClearCorpses | 24 |
| 0x14207ba08 | iHoursToRespawnCell | 72 |
| 0x14207ba20 | iHoursToRespawnCellCleared | 144 |
| 0x142076690 | iIngredientAlchemyUses | 0 |
| 0x142076678 | iIngredientUseEffectThreshold | 50 |
| 0x1420766a8 | iIngredientWortcraftUses | 0 |
| 0x1420ad4e8 | iInventoryAskQuantityAt | 5 |
| 0x1420a0cc8 | iKarmaMax | 1000 |
| 0x1420a0cb0 | iKarmaMin | -1000 |
| 0x1420a7f68 | iKillCamLevelOffset | 4 |
| 0x1420a49c8 | iLargeProjectilePickCount | 4 |
| 0x1420aba18 | iLesserSoulActorLevel | 2 |
| 0x14207acb8 | iLevCharLevelDifferenceMax | 0 |
| 0x1420aee80 | iLevelUpReminder | 300000 |
| 0x14207ace0 | iLevItemLevelDifferenceMax | 0 |
| 0x14209ec58 | iLightLevelExteriorMod | 0 |
| 0x14209ec40 | iLightLevelInteriorMod | 50 |
| 0x14209ec70 | iLightLevelMax | 100 |
| 0x14209c930 | iLipMorphCount | 10 |
| 0x1420773b0 | iLockLevelMaxAverage | 50 |
| 0x142077398 | iLockLevelMaxEasy | 25 |
| 0x1420773c8 | iLockLevelMaxHard | 75 |
| 0x1420773f8 | iLockLevelMaxImpossible | 255 |
| 0x142077380 | iLockLevelMaxVeryEasy | 0 |
| 0x1420773e0 | iLockLevelMaxVeryHard | 100 |
| 0x1420a8670 | iLowLevelNPCMaxLevel | 3 |
| 0x1420a85b0 | iMapMarkerFadeStartDistance | 7500 |
| 0x1420a8580 | iMapMarkerRevealDistance | 1000 |
| 0x1420a8598 | iMapMarkerVisibleDistance | 20000 |
| 0x14209e658 | iMasserSize | 94 |
| 0x14207a950 | iMaxArrowsInQuiver | 20 |
| 0x142077088 | iMaxAttachedArrows | 3 |
| 0x1420aa530 | iMaxCharacterLevel | 20 |
| 0x1420abbf8 | iMaxPlayerRunes | 6 |
| 0x1420ab838 | iMaxSummonedCreatures | 1 |
| 0x14207e2e0 | iMessageBoxMaxItems | 10 |
| 0x1420a6c00 | iMessCrippledLimbExplodeBonus | 50 |
| 0x1420a6bd0 | iMessIntactLimbDismemberChance | 75 |
| 0x1420a6be8 | iMessIntactLimbExplodeBonus | 50 |
| 0x1420a6c18 | iMessTargetedLimbExplodeBonus | 50 |
| 0x1420a6c30 | iMessTorsoExplodeChance | 50 |
| 0x1420a7860 | iMinClipSizeToAddReloadDelay | 2 |
| 0x1420a64c8 | iMineDisarmExperience | 0 |
| 0x1420a0f50 | iMoodFaceValue | 50 |
| 0x14209c8e8 | iNoseMorphCount | 10 |
| 0x1420a8688 | iNPCBasePerLevelHealthMult | 4 |
| 0x14209fdc8 | iNumberActorsAllowedToFollowPlayer | 6 |
| 0x1420a9ac8 | iNumberActorsGoThroughLoadDoorInCombat | 2 |
| 0x14209fdb0 | iNumberActorsInCombatPlayer | 20 |
| 0x14209fd98 | iNumberGuardsCrimeResponse | 4 |
| 0x1420a9d68 | iNumExplosionDecalCDPoint | 250 |
| 0x1420bacc8 | iObjectivesWaitTime:Interface | 250 |
| 0x1420a8550 | iPCStartSpellSkillLevel | 30 |
| 0x1420a67f8 | iPerkAttackDisarmChance | 5 |
| 0x1420a6810 | iPerkBlockDisarmChance | 5 |
| 0x1420a6828 | iPerkBlockStaggerChance | 5 |
| 0x1420a6870 | iPerkHandToHandBlockRecoilChance | 25 |
| 0x1420a89d0 | iPerkHeavyArmorJumpSum | 35 |
| 0x1420a89e8 | iPerkHeavyArmorSinkSum | 35 |
| 0x1420a68a0 | iPerkLightArmorMasterMinSum | 5 |
| 0x1420a6840 | iPerkMarksmanKnockdownChance | 5 |
| 0x1420a6858 | iPerkMarksmanParalyzeChance | 5 |
| 0x1420a8370 | iPersuasionAngleMax | 90 |
| 0x1420a8358 | iPersuasionAngleMin | 10 |
| 0x1420a90d8 | iPersuasionBribeCrime | 90 |
| 0x1420a82e0 | iPersuasionBribeGold | 10 |
| 0x1420a90c0 | iPersuasionBribeRefuse | 60 |
| 0x1420a90a8 | iPersuasionBribeScale | 5 |
| 0x1420a8508 | iPersuasionDemandDisposition | -2 |
| 0x1420a82f8 | iPersuasionDemandGold | 10 |
| 0x1420a9108 | iPersuasionDemandRefuse | 75 |
| 0x1420a90f0 | iPersuasionDemandScale | 5 |
| 0x1420a8340 | iPersuasionInner | 15 |
| 0x1420a8328 | iPersuasionMiddle | 25 |
| 0x1420a8310 | iPersuasionOuter | 50 |
| 0x1420a8298 | iPersuasionPower1 | 5 |
| 0x1420a82b0 | iPersuasionPower2 | 20 |
| 0x1420a82c8 | iPersuasionPower3 | 40 |
| 0x14209eb08 | iPickPocketWarnings | 2 |
| 0x1420a9918 | iPlayerCustomClass | 141379 |
| 0x1420a86e8 | iPlayerHealthHeartbeatFadeMS | 1000 |
| 0x1420a63f0 | iProjectileMaxRefCount | 15 |
| 0x1420a6570 | iProjectileMineShooterCanTrigger | 0 |
| 0x1420adcc8 | iQuestReminderPipboyDisabledTime | 30 |
| 0x14209f318 | iRelationshipAcquaintanceValue | 0 |
| 0x14209f2d0 | iRelationshipAllyValue | 300 |
| 0x14209f378 | iRelationshipArchnemesisValue | -400 |
| 0x14209f2e8 | iRelationshipConfidantValue | 200 |
| 0x14209f360 | iRelationshipEnemyValue | -300 |
| 0x14209f348 | iRelationshipFoeValue | -200 |
| 0x14209f300 | iRelationshipFriendValue | 100 |
| 0x14209f2b8 | iRelationshipLoverValue | 400 |
| 0x14209f330 | iRelationshipRivalValue | -100 |
| 0x1420a9bd0 | iRemoveExcessDeadComplexCount | 3 |
| 0x1420a9be8 | iRemoveExcessDeadComplexTotalActorCount | 20 |
| 0x1420a9b88 | iRemoveExcessDeadCount | 15 |
| 0x1420a9ba0 | iRemoveExcessDeadTotalActorCount | 20 |
| 0x1420a0ed8 | iSecondsToSleepPerUpdate | 900 |
| 0x14209e6e8 | iSecundaSize | 40 |
| 0x1420ab6e8 | iShockBranchNumBolts | 3 |
| 0x1420ab730 | iShockBranchSegmentsPerBolt | 50 |
| 0x1420ab7a8 | iShockDebug | 0 |
| 0x1420ab5b0 | iShockNumBolts | 8 |
| 0x1420ab670 | iShockSegmentsPerBolt | 25 |
| 0x1420ab6b8 | iShockSubSegments | 1 |
| 0x1420a0c38 | iSkillPointsTagSkillMult | 1 |
| 0x1420aa9e0 | iSkillUsageSneakFullDetection | 100 |
| 0x1420aa9c8 | iSkillUsageSneakMinDetection | -18 |
| 0x14207b558 | iSoulLevelValueCommon | 1000 |
| 0x14207b5b8 | iSoulLevelValueGrand | 3000 |
| 0x14207b588 | iSoulLevelValueGreater | 2000 |
| 0x14207b528 | iSoulLevelValueLesser | 500 |
| 0x14207b4f8 | iSoulLevelValuePetty | 250 |
| 0x14209ef10 | iSoundLevelLoud | 100 |
| 0x14209eef8 | iSoundLevelNormal | 50 |
| 0x14209eee0 | iSoundLevelSilent | 0 |
| 0x14209ef28 | iSoundLevelVeryLoud | 200 |
| 0x14209df98 | iSpeechChallengeDifficultyAverage | 50 |
| 0x14209df80 | iSpeechChallengeDifficultyEasy | 25 |
| 0x14209dfb0 | iSpeechChallengeDifficultyHard | 75 |
| 0x14209df68 | iSpeechChallengeDifficultyVeryEasy | 0 |
| 0x14209dfc8 | iSpeechChallengeDifficultyVeryHard | 100 |
| 0x142079370 | iSprayDecalsDebug | 0 |
| 0x1420a6078 | iStaggerAttackChance | 100 |
| 0x14209cdb0 | iStandardEmotionValue | 0 |
| 0x14209eaf0 | iStealWarnings | 2 |
| 0x1420aa320 | iTrainingExpertCost | 3 |
| 0x1420a8760 | iTrainingExpertSkill | 75 |
| 0x1420aa308 | iTrainingJourneymanCost | 1 |
| 0x1420a8748 | iTrainingJourneymanSkill | 50 |
| 0x1420aa338 | iTrainingMasterCost | 5 |
| 0x1420a8778 | iTrainingMasterSkill | 90 |
| 0x1420a8730 | iTrainingNumAllowedPerLevel | 5 |
| 0x1420a0770 | iTrespassWarnings | 2 |
| 0x142077e20 | iUpdateESMVersion | 4 |
| 0x1420a5538 | iVATSCameraHitDist | 100 |
| 0x1420ae610 | iVATSConcentratedFireBonus | 5 |
| 0x1420a56b8 | iVATSStrangerMaxHP | 50 |
| 0x1420a1298 | iVoicePointsDefault | 50 |
| 0x1420a6f18 | iWeaponCriticalHitDropChance | 100 |
| 0x142076c10 | iWortcraftMaxEffectsApprentice | 2 |
| 0x142076c40 | iWortcraftMaxEffectsExpert | 4 |
| 0x142076c28 | iWortcraftMaxEffectsJourneyman | 3 |
| 0x142076c58 | iWortcraftMaxEffectsMaster | 5 |
| 0x142076bf8 | iWortcraftMaxEffectsNovice | 1 |
| 0x1420aa548 | iXPBase | 200 |
| 0x1420aa560 | iXPBumpBase | 100 |
| 0x1420b2910 | iXPDeathRewardHealthThreshold | 75 |
| 0x1420b2670 | iXPLevelHackComputerAverage | 2 |
| 0x1420b2658 | iXPLevelHackComputerEasy | 1 |
| 0x1420b2688 | iXPLevelHackComputerHard | 3 |
| 0x1420b2640 | iXPLevelHackComputerVeryEasy | 0 |
| 0x1420b26a0 | iXPLevelHackComputerVeryHard | 4 |
| 0x1420b2490 | iXPLevelKillCreatureAverage | 10 |
| 0x1420b2478 | iXPLevelKillCreatureEasy | 5 |
| 0x1420b24a8 | iXPLevelKillCreatureHard | 12 |
| 0x1420b2460 | iXPLevelKillCreatureVeryEasy | 2 |
| 0x1420b24c0 | iXPLevelKillCreatureVeryHard | 15 |
| 0x1420b2508 | iXPLevelKillNPCAverage | 10 |
| 0x1420b24f0 | iXPLevelKillNPCEasy | 5 |
| 0x1420b2520 | iXPLevelKillNPCHard | 12 |
| 0x1420b24d8 | iXPLevelKillNPCVeryEasy | 2 |
| 0x1420b2538 | iXPLevelKillNPCVeryHard | 15 |
| 0x1420b2760 | iXPLevelPickLockAverage | 2 |
| 0x1420b2748 | iXPLevelPickLockEasy | 1 |
| 0x1420b2778 | iXPLevelPickLockHard | 3 |
| 0x1420b2730 | iXPLevelPickLockVeryEasy | 0 |
| 0x1420b2790 | iXPLevelPickLockVeryHard | 4 |
| 0x1420b2850 | iXPLevelSpeechChallengeAverage | 2 |
| 0x1420b2838 | iXPLevelSpeechChallengeEasy | 1 |
| 0x1420b2868 | iXPLevelSpeechChallengeHard | 3 |
| 0x1420b2820 | iXPLevelSpeechChallengeVeryEasy | 0 |
| 0x1420b2880 | iXPLevelSpeechChallengeVeryHard | 4 |
| 0x1420a9fd8 | iXPRewardDiscoverMapMarker | 10 |
| 0x1420a9ff0 | iXPRewardDiscoverSecretArea | 10 |
| 0x1420a9fc0 | iXPRewardHackComputer | 10 |
| 0x1420b26e8 | iXPRewardHackComputerAverage | 20 |
| 0x1420b26d0 | iXPRewardHackComputerEasy | 10 |
| 0x1420b2700 | iXPRewardHackComputerHard | 30 |
| 0x1420b26b8 | iXPRewardHackComputerVeryEasy | 5 |
| 0x1420b2718 | iXPRewardHackComputerVeryHard | 50 |
| 0x1420b25f8 | iXPRewardKillNPCAverage | 20 |
| 0x1420b25e0 | iXPRewardKillNPCEasy | 10 |
| 0x1420b2610 | iXPRewardKillNPCHard | 30 |
| 0x1420b25c8 | iXPRewardKillNPCVeryEasy | 0 |
| 0x1420b2628 | iXPRewardKillNPCVeryHard | 50 |
| 0x1420a9f90 | iXPRewardKillOpponent | 20 |
| 0x1420b2580 | iXPRewardKillOpponentAverage | 20 |
| 0x1420b2568 | iXPRewardKillOpponentEasy | 10 |
| 0x1420b2598 | iXPRewardKillOpponentHard | 30 |
| 0x1420b2550 | iXPRewardKillOpponentVeryEasy | 0 |
| 0x1420b25b0 | iXPRewardKillOpponentVeryHard | 50 |
| 0x1420a9fa8 | iXPRewardPickLock | 10 |
| 0x1420b27d8 | iXPRewardPickLockAverage | 20 |
| 0x1420b27c0 | iXPRewardPickLockEasy | 10 |
| 0x1420b27f0 | iXPRewardPickLockHard | 30 |
| 0x1420b27a8 | iXPRewardPickLockVeryEasy | 0 |
| 0x1420b2808 | iXPRewardPickLockVeryHard | 50 |
| 0x1420b28c8 | iXPRewardSpeechChallengeAverage | 20 |
| 0x1420b28b0 | iXPRewardSpeechChallengeEasy | 10 |
| 0x1420b28e0 | iXPRewardSpeechChallengeHard | 30 |
| 0x1420b2898 | iXPRewardSpeechChallengeVeryEasy | 0 |
| 0x1420b28f8 | iXPRewardSpeechChallengeVeryHard | 50 |

## Game settings: magic, spells, enchanting, alchemy

The value compiled into `SkyrimSE.exe` for each game setting (GMST) it knows: what the game uses when `Skyrim.esm` has no record of that name (the plugin's record wins). `game/sim/settings.zap` keeps the few the port reads; this is the whole table.

Read from the static `SettingT<GameSettingCollection>` objects in `.data` (24 bytes: the vtable, the value, the pointer to the name; the vtable's RTTI names the class), found by scanning `.data` for pointers to names and checked against REA's `read_bytes` at 0x1420d9078 (fShadowBiasScale:Display). The address is the object's; the value is decoded by the name's type letter (f float, i int, u unsigned, b bool, s string, r and a 32-bit colors).

| address | setting | value |
|---|---|---|
| 0x1420aac50 | fAlchemyGoldMult | 1.0 |
| 0x1420aaab8 | fAlchemyIngredientInitMult | 4.0 |
| 0x1420aaad0 | fAlchemySkillFactor | 2.0 |
| 0x1420aae18 | fMagicAbsorbDistanceReachMult | 3.0 |
| 0x1420ab7c0 | fMagicAbsorbVisualTimer | 4.0 |
| 0x1420abb08 | fMagicAccumulatingModifierEffectHoldDuration | 0.5 |
| 0x1420aac98 | fMagicAreaBaseCostMult | 0.15 |
| 0x1420aaf50 | fMagicAreaScale | 1.75 |
| 0x1420aaf68 | fMagicAreaScaleMax | 100.0 |
| 0x1420aaf80 | fMagicAreaScaleMin | 2.5 |
| 0x142076b50 | fMagicBallMaximumDistance | 2000.0 |
| 0x142076b38 | fMagicBallOptimalDistance | 1000.0 |
| 0x1420ab988 | fMagicBarrierDepth | 30.0 |
| 0x1420ab970 | fMagicBarrierHeight | 500.0 |
| 0x1420ab958 | fMagicBarrierSpacing | 25.0 |
| 0x1420aae48 | fMagicBoltDuration | 1.5 |
| 0x142076b80 | fMagicBoltMaximumDistance | 2000.0 |
| 0x142076b68 | fMagicBoltOptimalDistance | 1000.0 |
| 0x1420aae30 | fMagicBoltSegmentLength | 300.0 |
| 0x1420aad10 | fMagicCasterPCSkillCostBase | 0.005 |
| 0x1420aad28 | fMagicCasterPCSkillCostMult | 1.0 |
| 0x1420aace0 | fMagicCasterSkillCostBase | 0.005 |
| 0x1420aacf8 | fMagicCasterSkillCostMult | 1.0 |
| 0x142076ca0 | fMagicCasterTargetUpdateInterval | 0.25 |
| 0x1420ab478 | fMagicCEEnchantMagOffset | 5.0 |
| 0x1420aaf20 | fMagicChainExplosionEffectivenessDelta | 0.1 |
| 0x1420ab040 | fMagicCloudAreaMin | 1.0 |
| 0x1420ab028 | fMagicCloudDurationMin | 5.0 |
| 0x1420ab010 | fMagicCloudFindTargetTime | 0.25 |
| 0x1420aafb0 | fMagicCloudLifeScale | 0.5 |
| 0x1420aafe0 | fMagicCloudSizeScale | 2.0 |
| 0x1420aaff8 | fMagicCloudSlowdownRate | 0.2 |
| 0x1420aaf98 | fMagicCloudSpeedBase | 750.0 |
| 0x1420aafc8 | fMagicCloudSpeedScale | 0.75 |
| 0x1420ab7d8 | fMagicCostScale | 1.1 |
| 0x1420abb20 | fMagicDefaultAccumulatingModifierEffectRate | 1.0 |
| 0x142076cb8 | fMagicDefaultCEBarterFactor | 1.0 |
| 0x1420aae00 | fMagicDefaultTouchDistance | 256.0 |
| 0x1420ab490 | fMagicDiseaseTransferBase | 0.0 |
| 0x1420ab4a8 | fMagicDiseaseTransferMult | 1.0 |
| 0x1420ab460 | fMagicDispelMagnitudeMult | 5.0 |
| 0x1420abbc8 | fMagicDualCastingCostBase | 0.0 |
| 0x1420abbe0 | fMagicDualCastingCostMult | 1.5 |
| 0x1420abb98 | fMagicDualCastingEffectivenessBase | 2.0 |
| 0x1420abbb0 | fMagicDualCastingEffectivenessMult | 0.0 |
| 0x1420abb68 | fMagicDualCastingTimeBase | 0.0 |
| 0x1420abb80 | fMagicDualCastingTimeMult | 1.5 |
| 0x1420aacb0 | fMagicDurMagBaseCostMult | 0.1 |
| 0x1420aad40 | fMagicEnchantmentChargeBase | 0.0 |
| 0x1420aad58 | fMagicEnchantmentChargeMult | 1.0 |
| 0x1420aad70 | fMagicEnchantmentDrainBase | 0.0 |
| 0x1420aad88 | fMagicEnchantmentDrainMult | 0.25 |
| 0x1420aaed8 | fMagicExplosionAgilityMult | 0.0 |
| 0x1420aaf38 | fMagicExplosionClutterMult | 6.5 |
| 0x1420aaef0 | fMagicExplosionIncorporealMult | 600.0 |
| 0x1420aaf08 | fMagicExplosionIncorporealTime | 1.25 |
| 0x1420aaea8 | fMagicExplosionPowerBase | 100.0 |
| 0x1420aae90 | fMagicExplosionPowerMax | 100.0 |
| 0x1420aae78 | fMagicExplosionPowerMin | 0.0 |
| 0x1420aaec0 | fMagicExplosionPowerMult | 0.4 |
| 0x142076be0 | fMagicFogMaximumDistance | 500.0 |
| 0x142076bc8 | fMagicFogOptimalDistance | 300.0 |
| 0x1420ab400 | fMagicGrabActorDrawSpeed | 100.0 |
| 0x1420ab3e8 | fMagicGrabActorMinDistance | 90.0 |
| 0x1420ab418 | fMagicGrabActorRange | 750.0 |
| 0x1420ab430 | fMagicGrabActorThrowForce | 25.0 |
| 0x1420aba90 | fMagicGuideSpacing | 500.0 |
| 0x1420a12f8 | fMagickaRegenDelayMax | 5.0 |
| 0x1420ab058 | fMagickaReturnBase | 0.75 |
| 0x1420ab070 | fMagickaReturnMult | 0.02 |
| 0x1420abaf0 | fMagicLesserPowerCooldownTimer | 3.0 |
| 0x1420ab160 | fMagicLightForwardOffset | 22.0 |
| 0x1420ab178 | fMagicLightHeightOffset | 10.0 |
| 0x1420ab1a8 | fMagicLightRadiusBase | 0.0 |
| 0x1420ab190 | fMagicLightSideOffset | 0.0 |
| 0x1420ab448 | fMagicNightEyeAmbient | 0.75 |
| 0x1420ab808 | fMagicPCSkillCostScale | 0.5 |
| 0x1420ab130 | fMagicPlayerMinimumInvisibility | 0.1 |
| 0x1420ab9a0 | fMagicPostDrawCastDelay | 1.5 |
| 0x1420aae60 | fMagicProjectileMaxDistance | 10000.0 |
| 0x1420aacc8 | fMagicRangeTargetCostMult | 1.5 |
| 0x1420aada0 | fMagicResistActorSkillBase | 0.0 |
| 0x1420aadb8 | fMagicResistActorSkillMult | -0.0025 |
| 0x1420aadd0 | fMagicResistTargetWillpowerBase | 0.0 |
| 0x1420aade8 | fMagicResistTargetWillpowerMult | 0.005 |
| 0x1420ab7f0 | fMagicSkillCostScale | 0.5 |
| 0x142076bb0 | fMagicSprayMaximumDistance | 1000.0 |
| 0x142076b98 | fMagicSprayOptimalDistance | 500.0 |
| 0x1420ab850 | fMagicSummonMaxAppearTime | 4.0 |
| 0x1420ab310 | fMagicTelekinesiDistanceMult | 1.0 |
| 0x1420ab370 | fMagicTelekinesisBaseDistance | 15.0 |
| 0x1420ab2e0 | fMagicTelekinesisComplexMaxForce | 1000.0 |
| 0x1420ab2c8 | fMagicTelekinesisComplexObjectDamping | 0.7 |
| 0x1420ab298 | fMagicTelekinesisComplexSpringDamping | 0.9 |
| 0x1420ab2b0 | fMagicTelekinesisComplexSpringElasticity | 0.1 |
| 0x1420ab3b8 | fMagicTelekinesisDamageBase | 5.0 |
| 0x1420ab388 | fMagicTelekinesisDamageMult | 1.0 |
| 0x1420ab208 | fMagicTelekinesisDistanceMin | 48.0 |
| 0x1420ab3a0 | fMagicTelekinesisDualCastDamageMult | 2.0 |
| 0x1420ab358 | fMagicTelekinesisDualCastThrowMult | 2.0 |
| 0x1420ab2f8 | fMagicTelekinesisLiftPowerMult | 0.5 |
| 0x1420ab280 | fMagicTelekinesisMaxForce | 1000.0 |
| 0x1420ab1d8 | fMagicTelekinesisMoveAccelerate | 400.0 |
| 0x1420ab1c0 | fMagicTelekinesisMoveBase | 50.0 |
| 0x1420ab1f0 | fMagicTelekinesisMoveMax | 1000.0 |
| 0x1420ab268 | fMagicTelekinesisObjectDamping | 0.95 |
| 0x1420ab238 | fMagicTelekinesisSpringDamping | 0.5 |
| 0x1420ab250 | fMagicTelekinesisSpringElasticity | 0.075 |
| 0x1420ab220 | fMagicTelekinesisThrow | 1000.0 |
| 0x1420ab340 | fMagicTelekinesisThrowAccelerate | 10.0 |
| 0x1420ab328 | fMagicTelekinesisThrowMax | 30.0 |
| 0x1420ab4c0 | fMagicTrackingLimit | 3.0 |
| 0x1420ab4d8 | fMagicTrackingLimitComplex | 1.0 |
| 0x1420ab4f0 | fMagicTrackingMultBall | 1.0 |
| 0x1420ab508 | fMagicTrackingMultBolt | 0.5 |
| 0x1420ab520 | fMagicTrackingMultFog | 1.0 |
| 0x1420aac80 | fMagicUnitsPerFoot | 22.0 |
| 0x1420ab8e0 | fMagicVACNoPartTargetedMult | 0.1 |
| 0x1420ab8c8 | fMagicVACPartTargetedMult | 0.1 |
| 0x1420abb38 | fMagicWardPowerMaxBase | 0.5 |
| 0x1420abb50 | fMagicWardPowerMaxMult | 0.0 |
| 0x1420a9318 | fPotionGoldValueMult | 1.0 |
| 0x1420a91c8 | fPotionMortPestleMult | 0.25 |
| 0x1420a9270 | fPotionT1AleDurMult | -0.01 |
| 0x1420a9258 | fPotionT1AleMagMult | -0.01 |
| 0x1420a9240 | fPotionT1CalDurMult | 0.0025 |
| 0x1420a9228 | fPotionT1CalMagMult | 0.0035 |
| 0x1420a91e0 | fPotionT1MagMult | 2.5 |
| 0x1420a9210 | fPotionT1RetDurMult | 0.003 |
| 0x1420a91f8 | fPotionT1RetMagMult | 0.005 |
| 0x1420a92b8 | fPotionT2AleDurMult | -0.02 |
| 0x1420a92a0 | fPotionT2CalDurMult | 0.0025 |
| 0x1420a9288 | fPotionT2RetDurMult | 0.0035 |
| 0x1420a9300 | fPotionT3AleMagMult | -0.01 |
| 0x1420a92e8 | fPotionT3CalMagMult | 0.003 |
| 0x1420a92d0 | fPotionT3RetMagMult | 0.005 |
| 0x1420bacf8 | fShoutMeterFinishTime:Interface | 3.0 |
| 0x142099138 | fShoutRumbleBigMotorDurationV1 | 0.0 |
| 0x142099168 | fShoutRumbleBigMotorDurationV2 | 0.0 |
| 0x142099198 | fShoutRumbleBigMotorDurationV3 | 0.0 |
| 0x142099120 | fShoutRumbleBigMotorFrequencyV1 | 0.0 |
| 0x142099150 | fShoutRumbleBigMotorFrequencyV2 | 0.0 |
| 0x142099180 | fShoutRumbleBigMotorFrequencyV3 | 0.0 |
| 0x1420991c8 | fShoutRumbleSmallMotorDurationV1 | 0.0 |
| 0x1420991f8 | fShoutRumbleSmallMotorDurationV2 | 0.0 |
| 0x142099228 | fShoutRumbleSmallMotorDurationV3 | 0.0 |
| 0x1420991b0 | fShoutRumbleSmallMotorFrequencyV1 | 0.0 |
| 0x1420991e0 | fShoutRumbleSmallMotorFrequencyV2 | 0.0 |
| 0x142099210 | fShoutRumbleSmallMotorFrequencyV3 | 0.0 |
| 0x1420ab910 | fShoutTime1 | 0.2 |
| 0x1420ab928 | fShoutTime2 | 0.9 |
| 0x1420ab940 | fShoutTimeout | 8.0 |
| 0x1420a0590 | fSpellCastingDetectionHitActorMod | 40.0 |
| 0x1420a0578 | fSpellCastingDetectionMod | 10.0 |
| 0x1420aba00 | fSummonDistanceCheckThreshold | 750.0 |
| 0x1420abad8 | fWardAngleForExplosions | 90.0 |
| 0x1420aba78 | iMagicGuideWaypoints | 10 |
| 0x1420ab148 | iMagicLightMaxCount | 4 |
| 0x1420b00e0 | sAlchemy | "Alchemy" |
| 0x1420b0110 | sAlchemyMenuDescription | "Combine ingredients to make potions" |
| 0x1420b0080 | sEnchantArmorIncompatible | "Chosen enchantment cannot be applied to this item" |
| 0x1420afff0 | sEnchantDeconstructMenuDescription | "Choose an item to destroy and learn its effects" |
| 0x1420b0068 | sEnchantInsufficientCharge | "Insufficient charge for enchantment" |
| 0x1420aff60 | sEnchantItem | "Enchant item?" |
| 0x1420afed0 | sEnchantMenuDescription | "Choose an item to destroy and learn its Enchantment, or combine an Item, Enchantment, and Soul Gem to create magic items" |
| 0x1420b0050 | sEnchantMustChooseItems | "Choose an item, enchantment, and soul gem" |
| 0x142076d60 | sMagicCastCastWhileShouting | "You cannot cast a spell while shouting" |
| 0x142076d78 | sMagicCastInsufficientItemCharge | "Your item has insufficient charge" |
| 0x142076ce8 | sMagicCastInsufficientMagicka | "You don't have enough Magicka" |
| 0x142076d30 | sMagicCastMultiCast | "You cannot cast this spell while casting another" |
| 0x142076cd0 | sMagicCastOKText | "" |
| 0x142076d00 | sMagicCastPowerUsed | "You can only cast Powers once per day" |
| 0x142076d18 | sMagicCastRangedUnderwater | "You cannot cast ranged spells underwater" |
| 0x142076d48 | sMagicCastShoutWhileCasting | "You cannot shout while casting a spell" |
| 0x142076a48 | sMagicConcentration | "Concentration" |
| 0x142076a18 | sMagicConstantEffect | "Constant Effect" |
| 0x142076a90 | sMagicDeliveryAimed | "Aimed" |
| 0x142076a60 | sMagicDeliverySelf | "Self" |
| 0x142076620 | sMagicDeliveryStrike | "Strike" |
| 0x142076aa8 | sMagicDeliveryTargetActor | "Target Actor" |
| 0x142076ac0 | sMagicDeliveryTargetLocation | "Target Location" |
| 0x142076a78 | sMagicDeliveryTouch | "Contact" |
| 0x142076608 | sMagicEffectItemAbsorb | "Absorb" |
| 0x142076578 | sMagicEffectItemCreateLock | "Create" |
| 0x1420765f0 | sMagicEffectItemDamage | "Damage" |
| 0x1420765d8 | sMagicEffectItemDrain | "Drain" |
| 0x142076548 | sMagicEffectItemFeet | "ft" |
| 0x142076488 | sMagicEffectItemFor | "for" |
| 0x1420765a8 | sMagicEffectItemFortify | "Fortify" |
| 0x1420764b8 | sMagicEffectItemIn | "in" |
| 0x142076560 | sMagicEffectItemLock | "Lock" |
| 0x1420764a0 | sMagicEffectItemOn | "on" |
| 0x1420764e8 | sMagicEffectItemPercent | "%" |
| 0x142076530 | sMagicEffectItemPointsPlural | "pts" |
| 0x142076500 | sMagicEffectItemPointsSingular | "pt" |
| 0x1420765c0 | sMagicEffectItemRestore | "Restore" |
| 0x142076518 | sMagicEffectItemSecondsPlural | "secs" |
| 0x1420764d0 | sMagicEffectItemSecondsSingular | "sec" |
| 0x142076590 | sMagicEffectItemUpToLevel | "up to level" |
| 0x1420af900 | sMagicEffectNotApplied | "%s is immune to %s." |
| 0x1420af8e8 | sMagicEffectResisted | "%s is too powerful for %s." |
| 0x1420af960 | sMagicEnhanceWeaponNoWeapon | "You must have a weapon drawn." |
| 0x1420af978 | sMagicEnhanceWeaponWeaponEnchanted | "Your current weapon is already enchanted." |
| 0x142076a30 | sMagicFireAndForget | "Fire and Forget" |
| 0x1420abaa8 | sMagicGuideNoMarker | "You must have an active quest or have placed a marker on the map." |
| 0x1420abac0 | sMagicGuideNoPath | "There's no way to get to the nearest active quest location or map marker." |
| 0x142076ad8 | sMagicProjectileTypeBall | "Ball" |
| 0x142076af0 | sMagicProjectileTypeBolt | "Bolt" |
| 0x142076b20 | sMagicProjectileTypeFog | "Fog" |
| 0x142076b08 | sMagicProjectileTypeSpray | "Spray" |
| 0x142076850 | sMagicSchoolAlteration | "Alteration" |
| 0x142076868 | sMagicSchoolConjuration | "Conjuration" |
| 0x142076880 | sMagicSchoolDestruction | "Destruction" |
| 0x142076898 | sMagicSchoolIllusion | "Illusion" |
| 0x1420768b0 | sMagicSchoolRestoration | "Restoration" |
| 0x1420ab3d0 | sMagicTelekinesisNoRecast | "You're already holding something." |
| 0x1420768e0 | sMagicTypeAbility | "Ability" |
| 0x1420769b8 | sMagicTypeAddiction | "Addiction" |
| 0x1420768f8 | sMagicTypeDisease | "Disease" |
| 0x142076958 | sMagicTypeEnchantment | "Enchantment" |
| 0x142076910 | sMagicTypeLesserPower | "Lesser Power" |
| 0x1420769a0 | sMagicTypeLevelled | "Levelled Spell" |
| 0x142076940 | sMagicTypePoison | "Poison" |
| 0x142076970 | sMagicTypePotion | "Potion" |
| 0x142076928 | sMagicTypePower | "Power" |
| 0x142076a00 | sMagicTypeScroll | "Scroll" |
| 0x1420768c8 | sMagicTypeSpell | "Spell" |
| 0x1420769e8 | sMagicTypeStaffEnchantment | "Staff Enchantment" |
| 0x1420769d0 | sMagicTypeVoicePower | "Voice Power" |
| 0x142076988 | sMagicTypeWortcraft | "Wortcraft" |
| 0x1420b00b0 | sPotionCreationFailed | "Potion creation failed" |
| 0x1420abf58 | sShoutAdded | "Word of Power Learned" |
| 0x1420af4e0 | sSpellAdded | "New Spell Learned" |

## Game settings: the strings (s*)

The value compiled into `SkyrimSE.exe` for each game setting (GMST) it knows: what the game uses when `Skyrim.esm` has no record of that name (the plugin's record wins). `game/sim/settings.zap` keeps the few the port reads; this is the whole table.

Read from the static `SettingT<GameSettingCollection>` objects in `.data` (24 bytes: the vtable, the value, the pointer to the name; the vtable's RTTI names the class), found by scanning `.data` for pointers to names and checked against REA's `read_bytes` at 0x1420d9078 (fShadowBiasScale:Display). The address is the object's; the value is decoded by the name's type letter (f float, i int, u unsigned, b bool, s string, r and a 32-bit colors).

| address | setting | value |
|---|---|---|
| 0x1420b61d0 | sAbortText | "Abort" |
| 0x1420abcd0 | sAccept | "Accept" |
| 0x1420ae4c0 | sActionMapping | "Action Mapping" |
| 0x1420b0bc0 | sActionPointsAttack | "Attack" |
| 0x1420b0bf0 | sActionPointsCrouch | "Crouch" |
| 0x1420b0c50 | sActionPointsHeal | "Heal" |
| 0x1420b0ba8 | sActionPointsPunch | "Punch" |
| 0x1420b0bd8 | sActionPointsReload | "Reload" |
| 0x1420b0c08 | sActionPointsStand | "Stand" |
| 0x1420b0c20 | sActionPointsSwitchWeapon | "Switch Weapon" |
| 0x1420b0c38 | sActionPointsToggleWeaponDrawn | "Toggle Weapon Drawn" |
| 0x1420aed60 | sActivate | "Activate" |
| 0x1420a6a80 | sActivateCreatureCalmed | "The creature is calmed and cannot respond." |
| 0x1420a6a68 | sActivateNPCCalmed | "is calmed and cannot respond." |
| 0x1420af7e0 | sActivationChoiceMessage | "What would you like to do?" |
| 0x1420ad800 | sActiveEffects | "ACTIVE EFFECTS" |
| 0x1420ad608 | sActiveMineDescription | "Live" |
| 0x1420ac810 | sActorFade | "Actor Fade" |
| 0x1420b0158 | sAdd | "Add" |
| 0x1420af9c0 | sAddCrimeGold | "crimegold added to" |
| 0x1420ac8d0 | sAddedEffects | "Added Effects" |
| 0x1420ada58 | sAddedNote | "Note Added: %s" |
| 0x1420abe80 | sAddItemtoInventory | "Added" |
| 0x1420ac150 | sAddItemtoSpellList | "added" |
| 0x1420ad320 | sAllegiance | "Allegiance" |
| 0x1420ad680 | sAllItems | "ALL" |
| 0x1420af4f8 | sAlreadyKnown | "You already know" |
| 0x1420ad620 | sAlreadyPlacedMine | "An active mine has already been placed on this enemy." |
| 0x1420ad770 | sAlteration | "ALTERATION" |
| 0x1420ae568 | sAmber | "AMBER" |
| 0x1420aca08 | sAnimationCanNotEquipArmor | "You cannot change armor while attacking." |
| 0x1420ac9f0 | sAnimationCanNotEquipWeapon | "You cannot change weapons while attacking." |
| 0x1420ac060 | sAnimationCanNotUnequip | "You cannot change weapons while attacking." |
| 0x1420ad6b0 | sApparel | "APPAREL" |
| 0x1420790e8 | sApprenticeDisplayName | "Apprentice" |
| 0x1420ac918 | sAreaText | "Area" |
| 0x1420afea0 | sArmor | "ARMOR" |
| 0x1420afe70 | sArmorEnchantments | "ARMOR ENCHANTMENTS" |
| 0x1420afd68 | sArmorRating | "Armor Rating" |
| 0x1420afd98 | sArmorSmithing | "Armor Smithing" |
| 0x14207af88 | sArmorWeightHeavy | "Heavy" |
| 0x14207af70 | sArmorWeightLight | "Light" |
| 0x14207afa0 | sArmorWeightNone | "None" |
| 0x1420aee08 | sAttack | "Attack" |
| 0x1420af888 | sAttributeDamaged | "has been damaged" |
| 0x1420af8a0 | sAttributeDrained | "is being drained" |
| 0x1420abfb8 | sAttributesCount | "Distribute %d Point" |
| 0x1420abf70 | sAttributesTitle | "ATTRIBUTES: %d/%d Points Assigned" |
| 0x1420ac510 | sAutoLoading | "Autoloading..." |
| 0x1420ae520 | sAutosaveAbbrev | "AUTO" |
| 0x1420ac210 | sAutoSaveDisabledDueToLackOfSpace | "Save location full. Disabling Autosave." |
| 0x1420ac4f8 | sAutoSaving | "Autosaving..." |
| 0x1420af5d0 | sAutoSavingLong | "Saving content. Please don't turn off your console." |
| 0x1420abd00 | sBack | "Back" |
| 0x1420aecd0 | sBleedingOutMessage | "You are bleeding out!" |
| 0x1420a66a8 | sBloodParticleDefault | "Effects\\BloodSpray.nif" |
| 0x1420a6708 | sBloodParticleMeleeDefault | "Effects\\ImpactMeleeBloodSpray01.nif" |
| 0x1420a6de0 | sBloodSplatterAlpha01OPTFilename | "Textures\\Gore\\ScreenBloodAlpha01OPT.dds" |
| 0x1420a6df8 | sBloodSplatterColor01OPTFilename | "Textures\\Gore\\ScreenBloodColor01OPT.dds" |
| 0x1420a6e10 | sBloodSplatterFlare01Filename | "Textures\\Effects\\FXBloodFlare.dds" |
| 0x1420a66f0 | sBloodTextureDefault | "Effects\\blooddecal.dds" |
| 0x1420ad728 | sBooks | "BOOKS" |
| 0x1420ad380 | sBounty | "Bounty" |
| 0x1420af4c8 | sBountyStatString | "%s Bounty" |
| 0x1420ae310 | sBrightness | "Brightness" |
| 0x1420add70 | sBroken | "[Locked - Broken]" |
| 0x1420ace40 | sButton | "Button" |
| 0x1420ace70 | sButtonLocked | "That button cannot be remapped" |
| 0x1420ae370 | sCameraPitch | "Invert Y" |
| 0x1420b3c40 | sCameraShakeFilename_G | "%s\\Actors\\Character\\CameraShake.nif" |
| 0x1420abcb8 | sCancel | "Cancel" |
| 0x1420bb230 | sCannotCastShout | "You can't shout right now." |
| 0x1420aca38 | sCanNotEquipWornEnchantment | "You cannot equip this item right now." |
| 0x1420aca20 | sCanNotReadBook | "You cannot read a book while in combat." |
| 0x1420ae760 | sCanNotTrainAnymore | "You have reached your training limit for your current level." |
| 0x1420ae778 | sCanNotTrainHigher | "This NPC cannot help you train any higher." |
| 0x1420ace10 | sCantChangeResolution | "You must close your current game to change resolutions." |
| 0x1420ac0c0 | sCantEquipBrokenItem | "Broken items cannot be equipped until they have been repaired." |
| 0x1420ac030 | sCantEquipGeneric | "You cannot equip this item." |
| 0x1420ac048 | sCantEquipPowerArmor | "Power armor training is required to equip this item." |
| 0x1420aecb8 | sCantHotkeyItem | "You cannot favorite that item." |
| 0x1420ae8f8 | sCantInstallModDependency | "This mod cannot be installed since it depends on files that aren't present." |
| 0x1420ae910 | sCantInstallModInvalid | "This mod cannot be activated and should be deleted." |
| 0x1420ae688 | sCantLoadControls | "Unable to load controls. Defaults will be used." |
| 0x1420ae670 | sCantLoadSettings | "Unable to load settings. Defaults will be used." |
| 0x1420ac4c8 | sCantQuickLoad | "You can't Quickload while the game is paused." |
| 0x1420ac4b0 | sCantQuickSave | "You can't Quicksave while the game is paused." |
| 0x1420ac0f0 | sCantRemoveWornItem | "Unable to remove the worn item." |
| 0x1420af288 | sCantRepairPastMax | "CANNOT REPAIR PAST %.0f%s" |
| 0x1420ac468 | sCantSaveNow | "You cannot save right now." |
| 0x1420ac078 | sCantUnequipGeneric | "You cannot unequip this item." |
| 0x1420ae808 | sChangedModsResetConfirm | "The mod selection / load order has changed.  The game will now reload your data files." |
| 0x1420ac858 | sChangeItemSelection | "Change Item Selection" |
| 0x1420af480 | sCharGenControlsDisabled | "Your hands are bound." |
| 0x1420ac9a8 | sChemsAddicted | "You have become addicted to %s." |
| 0x1420ac9c0 | sChemsWithdrawal | "You are suffering from %s withdrawal." |
| 0x1420ac990 | sChemsWornOff | "%s has worn off." |
| 0x1420abdc0 | sChoose | "Choose" |
| 0x1420ad530 | sChooseSoulGem | "Choose Soul Gem to Use" |
| 0x1420ad398 | sCleared | "Cleared" |
| 0x1420b00f8 | sClearSelections | "Clear Selections" |
| 0x1420aed30 | sClose | "Close" |
| 0x1420ae868 | sCloseMarketplaceMenu_Confirm | "Downloads still in progress. Are you sure you want to exit?" |
| 0x1420ae850 | sCloseModManager_Confirm | "Downloads still in progress. Are you sure you want to exit?" |
| 0x1420af0a8 | sConfirmAttribute | "Increase %s?" |
| 0x1420ae3e8 | sConfirmContinue | "Continue from your last saved game?" |
| 0x1420ae430 | sConfirmDelete | "Delete this game?" |
| 0x1420b0008 | sConfirmDisenchant | "Are you sure you want to destroy this item and learn its enchantment?" |
| 0x1420ae400 | sConfirmLoad | "Load this game?" |
| 0x1420ae3d0 | sConfirmNew | "Start a new game?" |
| 0x1420ae898 | sConfirmNewMods | "Start a new game? Mods are currently loaded. Note: Achievements are disabled." |
| 0x1420ae8b0 | sConfirmNewMods_Orbis | "Start a new game? Mods are currently loaded. Note: Trophies are disabled." |
| 0x1420ae418 | sConfirmSave | "Overwrite this game?" |
| 0x1420aefe8 | sConfirmSpendSoul | "Spend Soul?" |
| 0x1420ae448 | sConfirmWarning | "WARNING:  Any unsaved progress will be lost." |
| 0x1420ad7b8 | sConjuration | "CONJURATION" |
| 0x1420afac8 | sConstructibleMenuConfirm | "Do you want to create this item?" |
| 0x1420afa80 | sConstructibleMenuDescription | "Choose an item to create" |
| 0x1420ad560 | sContainerItemsTitle | "Inventory" |
| 0x1420aec40 | sContainerPlaceChance | "TO PLACE" |
| 0x1420aec28 | sContainerStealChance | "TO STEAL" |
| 0x1420abf40 | sContinue | "Continue" |
| 0x1420b6230 | sContinueText | "Continue Running Executable?" |
| 0x1420af8b8 | sContractedDisease | "You have contracted" |
| 0x1420ac6c0 | sControllerOption | "Turn off 360 Controller in the Controls section of the Settings menu to switch back to Keyboard/Mouse." |
| 0x1420ac600 | sCorruptContentMessage | "Some of your downloaded content is corrupt and could not be loaded." |
| 0x1420afa50 | sCraft | "Craft" |
| 0x1420afa98 | sCreate | "Create" |
| 0x1420b0098 | sCreated | "Created" |
| 0x1420ac8a0 | sCreatedPoisonNamePrefix | "Poison of " |
| 0x1420ac888 | sCreatedPotionNamePrefix | "Potion of " |
| 0x1420af6c0 | sCriticalStrike | "Critical Strike on" |
| 0x1420ac738 | sCrosshair | "Crosshair" |
| 0x1420ad2f0 | sCurrentLocation | "Current Location" |
| 0x1420addb8 | sCurrentObjective | "CURRENT OBJECTIVE" |
| 0x1420abc40 | sCursorFilename | "Interface\\Icons\\Misc\\cursor.dds" |
| 0x1420afae0 | sDaedric | "DAEDRIC" |
| 0x1420afd50 | sDamage | "Damage" |
| 0x14207a3c0 | sDayFriday | "Fredas" |
| 0x14207a360 | sDayMonday | "Morndas" |
| 0x14207a3d8 | sDaySaturday | "Loredas" |
| 0x14207a348 | sDaySunday | "Sundas" |
| 0x14207a3a8 | sDayThursday | "Turdas" |
| 0x14207a378 | sDayTuesday | "Tirdas" |
| 0x14207a390 | sDayWednesday | "Middas" |
| 0x14207b9c0 | sDefaultCellName | "Wilderness" |
| 0x14207ba50 | sDefaultCubeMap | "Cubemaps\\CaveGreenCube_e.dds" |
| 0x1420acdf8 | sDefaultMessage | "DEFAULT MESSAGE TEXT" |
| 0x14207a1e0 | sDefaultOrdSuffix | "th" |
| 0x1420ae4a8 | sDefaultPlayerName | "Player Name" |
| 0x1420ae7f0 | sDeleteAllModsConfirm | "Do you really want to delete all downloaded mods?" |
| 0x1420ae838 | sDeleteLibraryModConfirm | "Are you sure you want to delete this mod?  If this mod is not registered with Bethesda.net, it will no longer be recoverable." |
| 0x1420ae820 | sDeleteModConfirm | "Do you want to delete this mod?" |
| 0x1420ac420 | sDeleteSaveGame | "Are you sure you want to delete this save game?" |
| 0x1420ac570 | sDeleteSuccessful | "Save game deleted." |
| 0x1420ad7a0 | sDestruction | "DESTRUCTION" |
| 0x1420ae4d8 | sDevice | "Device" |
| 0x1420ac588 | sDeviceRemoved | "The save device you selected is no longer available.  You will need to select a new device the next time you save.  Until then, Autosave is disabled." |
| 0x1420ae2b0 | sDialogSubtitles | "Dialog Subtitles" |
| 0x1420ac720 | sDifficulty | "Difficulty" |
| 0x1420ae5c8 | sDisableHelp | "Disable Help" |
| 0x1420ac6d8 | sDisableXBoxController | "360 Controller" |
| 0x1420b00c8 | sDiscoveredEffects | "Discovered effects" |
| 0x1420ad548 | sDiscoveredIngredientEffectEating | "%s discovered from %s" |
| 0x1420acc78 | sDiscoveredText | "discovered" |
| 0x1420b0020 | sDisenchant | "Disenchant" |
| 0x1420a66c0 | sDismemberParticleDefault | "Gore\\BloodSprayLimb01.nif" |
| 0x1420a66d8 | sDismemberRobotParticleDefault | "Gore\\RobotLimbSpray01.nif" |
| 0x1420abdd8 | sDone | "Done" |
| 0x1420aea00 | sDownload | "Download" |
| 0x1420ad1b8 | sDownloadsAvailable | "New Content Available" |
| 0x1420ad1e8 | sDownloadsNotAvail | "No New Content Available" |
| 0x1420afaf8 | sDragon | "DRAGON" |
| 0x1420b8b20 | sDragonCrashEffectModel | "effects/dragoncrash/fxdragoncrashfurrow01.nif" |
| 0x1420aeeb0 | sDragonSoulAcquired | "Dragon Soul Acquired" |
| 0x1420afc00 | sDraugr | "DRAUGR" |
| 0x1420ac120 | sDropEquippedItemWarning | "You cannot drop an equipped item until you complete your current action." |
| 0x1420ac108 | sDropQuestItemWarning | "You cannot remove Quest Items from your Inventory." |
| 0x1420af948 | sDungeonCleared | "Dungeon Cleared!" |
| 0x1420ac900 | sDurationText | "Duration" |
| 0x1420afb10 | sDwarven | "DWARVEN" |
| 0x1420afb28 | sEbony | "EBONY" |
| 0x1420ac9d8 | sEffectAlreadyAdded | "Effect has already been added.  Edit the effect instead." |
| 0x1420aefb8 | sEffectsListDisplayHour | "hour" |
| 0x1420aef70 | sEffectsListDisplayHours | "hours" |
| 0x1420aefa0 | sEffectsListDisplayMin | "min" |
| 0x1420aef58 | sEffectsListDisplayMins | "mins" |
| 0x1420aef88 | sEffectsListDisplaySec | "sec" |
| 0x1420ad4d0 | sEffectsListDisplaySecs | "secs" |
| 0x1420acbb8 | sEffectsVolume | "Effects" |
| 0x1420afb58 | sElven | "ELVEN" |
| 0x1420ada40 | sEmpty | "Empty" |
| 0x1420ae5e0 | sEnableHelp | "Enable Help" |
| 0x1420afeb8 | sEnchanting | "Enchanting" |
| 0x1420aff00 | sEnchantment | "Enchantment" |
| 0x1420b0038 | sEnchantmentKnown | "The enchantment on this item is already known" |
| 0x1420affd8 | sEnchantmentsLearned | "You learned the %s enchantment from destroying this item." |
| 0x1420aff90 | sEnterItemName | "Enter Item Name" |
| 0x1420ad188 | sEnterName | "Enter character name." |
| 0x1420abeb0 | sEquipItemOnPlayer | "was equipped" |
| 0x1420af618 | sEssentialCharacterDown | "is unconscious." |
| 0x1420abe08 | sExit | "Exit" |
| 0x1420ae3b8 | sExitGameAffirm | "Exit Game" |
| 0x1420ae7c0 | sExpert | "Expert" |
| 0x142079118 | sExpertDisplayName | "Expert" |
| 0x1420a9cd8 | sExplosionSplashParticles | "Effects\\ExplosionSplash.NIF" |
| 0x1420aea48 | sFailedActivation | "This object cannot be activated right now." |
| 0x1420af018 | sFailShouting | "You cannot change shouts while shouting." |
| 0x1420af000 | sFailSpendSoul | "Use Dragon Souls to unlock shouts." |
| 0x1420afb70 | sFalmer | "FALMER" |
| 0x1420ad3c8 | sFastTravelConfirm | "Fast travel to %s?" |
| 0x1420af810 | sFastTravelNoTravelHealthDamage | "You can't fast travel while taking health damage" |
| 0x1420ad758 | sFavorites | "FAVORITES" |
| 0x1420ac4e0 | sFileNotFound | "File does not exist" |
| 0x1420ac678 | sFindingContentMessage | "Looking for content.  Please wait." |
| 0x14207a198 | sFirstOrdSuffix | "st" |
| 0x1420a0380 | sFirstPersonSkeleton | "Actors\\Character\\_1stPerson\\Skeleton.NIF" |
| 0x1420aec88 | sFood | "FOOD" |
| 0x1420acb88 | sFootstepsVolume | "Footstep" |
| 0x1420abd18 | sFor | "for" |
| 0x1420ace28 | sFullHealth | "You are already at full health." |
| 0x1420aeda8 | sFurnitureSleep | "Sleep" |
| 0x1420ac708 | sGamepadDisconnectedMessage | "Please connect a controller to continue." |
| 0x1420ac6f0 | sGamepadDisconnectedTitle | "Controller disconnected." |
| 0x14209cc00 | sGenderFemale | "female" |
| 0x14209cbe8 | sGenderMale | "male" |
| 0x1420ae2c8 | sGeneralSubtitles | "General Subtitles" |
| 0x1420afc60 | sGenericCraftKeywordName01 | "GADGETS" |
| 0x1420afc78 | sGenericCraftKeywordName02 | "GIZMOS" |
| 0x1420afc90 | sGenericCraftKeywordName03 | "WHOSE-ITS" |
| 0x1420afca8 | sGenericCraftKeywordName04 | "WHAT-ITS" |
| 0x1420afcc0 | sGenericCraftKeywordName05 | "THINGAMABOBS" |
| 0x1420afcd8 | sGenericCraftKeywordName06 | "KNICKS" |
| 0x1420afcf0 | sGenericCraftKeywordName07 | "KNACKS" |
| 0x1420afd08 | sGenericCraftKeywordName08 | "BITS" |
| 0x1420afd20 | sGenericCraftKeywordName09 | "BOBS" |
| 0x1420afd38 | sGenericCraftKeywordName10 | "LOST SOCKS" |
| 0x1420ae640 | sGFWLive | "LIVE" |
| 0x1420afb88 | sGlass | "GLASS" |
| 0x1420abd48 | sGold | "gold" |
| 0x1420ad230 | sGotAwayWithStealing | "got away with stealing" |
| 0x1420ae6a0 | sGrassFade | "Grass Fade" |
| 0x1420ace88 | sHairColor0 | "sHairColor0" |
| 0x1420acea0 | sHairColor1 | "sHairColor1" |
| 0x1420acf78 | sHairColor10 | "sHairColor10" |
| 0x1420acf90 | sHairColor11 | "sHairColor11" |
| 0x1420acfa8 | sHairColor12 | "sHairColor12" |
| 0x1420acfc0 | sHairColor13 | "sHairColor13" |
| 0x1420acfd8 | sHairColor14 | "sHairColor14" |
| 0x1420acff0 | sHairColor15 | "sHairColor15" |
| 0x1420aceb8 | sHairColor2 | "sHairColor2" |
| 0x1420aced0 | sHairColor3 | "sHairColor3" |
| 0x1420acee8 | sHairColor4 | "sHairColor4" |
| 0x1420acf00 | sHairColor5 | "sHairColor5" |
| 0x1420acf18 | sHairColor6 | "sHairColor6" |
| 0x1420acf30 | sHairColor7 | "sHairColor7" |
| 0x1420acf48 | sHairColor8 | "sHairColor8" |
| 0x1420acf60 | sHairColor9 | "sHairColor9" |
| 0x142079da8 | sHandToHandIcon | "Icons\\Weapons\\HandToHand.dds" |
| 0x1420aece8 | sHarvest | "Harvest" |
| 0x1420ad5c0 | sHealth | "Health" |
| 0x142077440 | sHealthDataPrefixArmo1 | "Fine" |
| 0x142077488 | sHealthDataPrefixArmo2 | "Very Fine" |
| 0x1420774d0 | sHealthDataPrefixArmo3 | "Extra Fine" |
| 0x142077518 | sHealthDataPrefixArmo4 | "Super Fine" |
| 0x142077560 | sHealthDataPrefixArmo5 | "Super Duper Fine" |
| 0x1420775a8 | sHealthDataPrefixArmo6 | "Ultra Fine" |
| 0x142077428 | sHealthDataPrefixWeap1 | "Fine" |
| 0x142077470 | sHealthDataPrefixWeap2 | "Very Fine" |
| 0x1420774b8 | sHealthDataPrefixWeap3 | "Extra Fine" |
| 0x142077500 | sHealthDataPrefixWeap4 | "Super Fine" |
| 0x142077548 | sHealthDataPrefixWeap5 | "Super Duper Fine" |
| 0x142077590 | sHealthDataPrefixWeap6 | "Ultra Fine" |
| 0x1420af588 | sHeavyArmorNoJump | "Your heavy armor prevents you from jumping." |
| 0x1420af5a0 | sHeavyArmorSink | "Your heavy armor is causing you to sink." |
| 0x1420ae490 | sHelp | "Help" |
| 0x1420afc18 | sHide | "HIDE" |
| 0x1420ad2c0 | sHigh | "High" |
| 0x1420ad308 | sHold | "Hold" |
| 0x14207a4f8 | sHolidayEmperorsBirthday | "Emperor's Birthday" |
| 0x14207a420 | sHolidayFirstPlanting | "First Planting" |
| 0x14207a4b0 | sHolidayHarvestsEnd | "Harvest's End" |
| 0x14207a438 | sHolidayJestersDay | "Jester's Day" |
| 0x14207a480 | sHolidayMerchantsFestival | "Merchant's Festival" |
| 0x14207a468 | sHolidayMidYearCelebration | "Mid Year Celebration" |
| 0x14207a3f0 | sHolidayNewLifeFestival | "New Life Festival" |
| 0x14207a528 | sHolidayNorthWindsPrayer | "North Wind's Prayer" |
| 0x14207a540 | sHolidayOldLifeFestival | "Old Life Festival" |
| 0x14207a450 | sHolidaySecondPlanting | "Second Planting" |
| 0x14207a408 | sHolidaySouthWindsPrayer | "South Wind's Prayer" |
| 0x14207a498 | sHolidaySunsRest | "Sun's Rest" |
| 0x14207a4c8 | sHolidayTalesAndTallows | "Tales and Tallows" |
| 0x14207a510 | sHolidayWarriorsFestival | "Warrior's Festival" |
| 0x14207a4e0 | sHolidayWitchesFestival | "Witches' Festival" |
| 0x1420aeee0 | sHUDArmorRating | "ARMOR RATING" |
| 0x1420ac7b0 | sHUDColor | "HUD Color" |
| 0x1420aef10 | sHUDCompleted | "Completed" |
| 0x1420aeec8 | sHUDDamage | "DAMAGE" |
| 0x1420aef28 | sHUDFailed | "Failed" |
| 0x1420ae2e0 | sHUDOpacity | "HUD Opacity" |
| 0x1420aeef8 | sHUDStarted | "Started" |
| 0x1420b6200 | sIgnoreText | "Ignore" |
| 0x1420ad788 | sIllusion | "ILLUSION" |
| 0x1420a6738 | sImpactParticleConcreteDefault | "Effects\\ImpactBallisticConcrete01.nif" |
| 0x1420a6720 | sImpactParticleMetalDefault | "Effects\\ImpactBallisticMetal01.nif" |
| 0x1420a6750 | sImpactParticleWoodDefault | "Effects\\ImpactBallisticWood01.nif" |
| 0x1420ad338 | sImperial | "IMPERIAL" |
| 0x1420ac168 | sImpossibleLock | "This lock cannot be picked. It requires a key to open." |
| 0x1420afdc8 | sImprovement | "Improvement" |
| 0x1420add58 | sInaccessible | "[INACCESSIBLE]" |
| 0x1420b0128 | sIngredient | "Ingredient" |
| 0x1420af720 | sIngredientFail | " Ingredient had no effect." |
| 0x1420ad6e0 | sIngredients | "INGREDIENTS" |
| 0x1420ae790 | sInsufficientGoldToTrain | "You have insufficient gold to train." |
| 0x1420accc0 | sInvalidPickpocket | "You cannot place items in a container while pickpocketing." |
| 0x14209cc58 | sInvalidTagString | "[...]" |
| 0x1420afbe8 | sIron | "IRON" |
| 0x1420afee8 | sItem | "Item" |
| 0x1420ac828 | sItemFade | "Item Fade" |
| 0x1420aeac0 | sItemTooExpensive | "You don't have enough gold." |
| 0x1420aeaa8 | sItemTooHeavy | "The item is too heavy to carry." |
| 0x1420afc48 | sJewelry | "JEWELRY" |
| 0x1420ae7a8 | sJourneyman | "Journeyman" |
| 0x142079100 | sJourneymanDisplayName | "Journeyman" |
| 0x1420ad638 | sJunk | "Junk" |
| 0x1420ace58 | sKeyLocked | "That key cannot be remapped" |
| 0x1420ad740 | sKeys | "KEYS" |
| 0x1420afa08 | sKinectAllyTooFarToTrade | "Your follower is too far to trade with." |
| 0x1420afa38 | sKinectCantInit | "The Kinect Sensor has failed to initialize. Voice commands have been disabled. Ensure that your Kinect Sensor is connected and updated." |
| 0x1420afa20 | sKinectNotCalibrated | "Your Kinect Sensor has not been calibrated. Voice commands have been disabled. Please use the Kinect Tuner to calibrate your Kinect Sensor." |
| 0x1420ac8b8 | sKnownEffects | "Known Effects" |
| 0x1420afe10 | sLackRequiredPerksToImprove | "You lack the required perks to improve this item" |
| 0x1420afe28 | sLackRequiredPerkToImproveMagical | "You lack the perk to improve magical items" |
| 0x1420afdf8 | sLackRequiredSkillToImprove | "You lack the required skill to improve this item" |
| 0x1420afab0 | sLackRequiredToCreate | "You lack the required components to create this item" |
| 0x1420afde0 | sLackRequiredToImprove | "You lack the required components to improve this item" |
| 0x1420abda8 | sLarge | "Large" |
| 0x1420affa8 | sLearn | "Learn" |
| 0x1420affc0 | sLearningEnchantments | "Learning Enchantments" |
| 0x1420afba0 | sLeather | "LEATHER" |
| 0x1420acd38 | sLeaveMarker | "Leave It" |
| 0x1420aebc8 | sLegendaryResetConfirm | "Are you sure you want to reset this skill?" |
| 0x1420aebe0 | sLegendaryResetSecondConfirm | "If you do this you will lose your perks and be reset to 15?" |
| 0x1420af090 | sLevelAbbrev | "Level" |
| 0x1420addd0 | sLevelProgress | "Level Progress" |
| 0x1420aee98 | sLevelUpAvailable | "Level up available." |
| 0x1420ae6d0 | sLightFade | "Light Fade" |
| 0x1420ac438 | sLoadFromMainMenu | "Are you sure you want to load this game?" |
| 0x1420ac528 | sLoading | "Loading..." |
| 0x1420af840 | sLoadingArea | "Loading area..." |
| 0x1420ac660 | sLoadingContentMessage | "Loading extra content. Please wait." |
| 0x1420ae2f8 | sLoadingLOD | "Loading distant LOD..." |
| 0x1420ae8c8 | sLoadVanillaSaveWithMods | "Mods are currently loaded. Note: Achievements are disabled.  Do you wish to continue loading this save ?" |
| 0x1420ae8e0 | sLoadVanillaSaveWithMods_Orbis | "Mods are currently loaded. Note: Trophies are disabled. Do you wish to continue loading this save ?" |
| 0x1420ac450 | sLoadWhilePlaying | "Are you sure you want to load this game?  All unsaved progress will be lost." |
| 0x1420accd8 | sLockBroken | "The lock has been broken." |
| 0x1420ada28 | sLocked | "Locked" |
| 0x142077320 | sLockLevelNameAverage | "Average" |
| 0x142077308 | sLockLevelNameEasy | "Easy" |
| 0x142077338 | sLockLevelNameHard | "Hard" |
| 0x142077368 | sLockLevelNameImpossible | "Requires Key" |
| 0x1420772f0 | sLockLevelNameVeryEasy | "Very Easy" |
| 0x142077350 | sLockLevelNameVeryHard | "Very Hard" |
| 0x1420ac180 | sLockpickInsufficientPerks | "You lack the required perk to pick this lock." |
| 0x1420ac6a8 | sLostController | "The Xbox 360 Controller has been disconnected. Click OK to use the Keyboard/Mouse, or reconnect the Xbox 360 Controller and press the A Button." |
| 0x1420ad2a8 | sLow | "Low" |
| 0x1420af6f0 | sMagnitudeIsLevelText | "Target Level" |
| 0x1420ac8e8 | sMagnitudeText | "Magnitude" |
| 0x1420acd68 | sMainMenu | "Main Menu" |
| 0x1420ad248 | sMakeDefaults | "Make these your default settings?" |
| 0x1420ad218 | sMapMarkerAdded | "Map marker added." |
| 0x1420ae7d8 | sMaster | "Master" |
| 0x142079130 | sMasterDisplayName | "Master" |
| 0x1420acb58 | sMasterVolume | "Master" |
| 0x1420abd90 | sMedium | "Medium" |
| 0x1420ac318 | sMenuDisplayAutosaveName | "Autosave" |
| 0x1420ac360 | sMenuDisplayDayString | "Day" |
| 0x1420ac330 | sMenuDisplayLevelString | "Level" |
| 0x1420ac2e8 | sMenuDisplayNewSave | "New Save" |
| 0x1420ac2d0 | sMenuDisplayNoSaves | "No saved games." |
| 0x1420ac2b8 | sMenuDisplayPlayTime | "Play Time" |
| 0x1420ac300 | sMenuDisplayQuicksaveName | "Quicksave" |
| 0x1420ac2a0 | sMenuDisplaySave | "Save" |
| 0x1420ae628 | sMenuDisplayShortXBoxSaveMessage | "Saving..." |
| 0x1420ac348 | sMenuDisplayUnknownLocationString | "Unknown Location" |
| 0x1420ac288 | sMenuDisplayXBoxSaveMessage | "Saving content. Please don't turn off your console." |
| 0x1420ad710 | sMisc | "MISC" |
| 0x1420af708 | sMiscConstantEffect | "Constant Effect" |
| 0x1420acc48 | sMiscPlayerDeadLoadOption | "Reload" |
| 0x1420acc60 | sMiscPlayerDeadMenuOption | "Main Menu" |
| 0x1420acc30 | sMiscPlayerDeadMessage | "Reloading the most recent save game" |
| 0x1420aea30 | sMiscQuestDescription | "Miscellaneous quests!" |
| 0x1420aea18 | sMiscQuestName | "Miscellaneous" |
| 0x1420acc00 | sMiscUnknownEffect | "(Unknown Effect)" |
| 0x1420acdb0 | sMissingImage | "Data\\Textures\\Interface\\Shared\\missing_image.dds" |
| 0x1420acd98 | sMissingName | "<Missing Name>" |
| 0x1420af4b0 | sModdedString | "Modded" |
| 0x14207a270 | sMonthApril | "Rains Hand" |
| 0x14207a2d0 | sMonthAugust | "Last Seed" |
| 0x14207a330 | sMonthDecember | "Evening Star" |
| 0x14207a240 | sMonthFebruary | "Sun's Dawn" |
| 0x14207a228 | sMonthJanuary | "Morning Star" |
| 0x14207a2b8 | sMonthJuly | "Sun's Height" |
| 0x14207a2a0 | sMonthJune | "Mid Year" |
| 0x14207a258 | sMonthMarch | "First Seed" |
| 0x14207a288 | sMonthMay | "Second Seed" |
| 0x14207a318 | sMonthNovember | "Sun's Dusk" |
| 0x14207a300 | sMonthOctober | "Frost Fall" |
| 0x14207a2e8 | sMonthSeptember | "Heart Fire" |
| 0x1420ae328 | sMouseSensitivity | "Mouse Sensitivity" |
| 0x1420acd20 | sMoveMarker | "Move It" |
| 0x1420acd08 | sMoveMarkerQuestion | "Do you want to move your marker or remove it?" |
| 0x1420af048 | sMultipleDragonSoulCount | "%i Dragon Souls" |
| 0x1420acb70 | sMusicVolume | "Music" |
| 0x1420ad2d8 | sMustRestart | "You must exit and restart Skyrim for changes in this setting to take effect." |
| 0x1420ad590 | sName | "Name" |
| 0x1420ad368 | sNeutral | "Neutral" |
| 0x1420ae460 | sNewSave | "[NEW SAVE]" |
| 0x1420abce8 | sNext | "Next" |
| 0x1420abca0 | sNo | "No" |
| 0x1420aea60 | sNoArrows | "No arrows equipped." |
| 0x1420aea78 | sNoBolts | "No bolts equipped." |
| 0x1420ad518 | sNoChargeItems | "No items to charge enchantment" |
| 0x1420af780 | sNoChildUse | "Children cannot use that." |
| 0x1420ac5a0 | sNoDeviceSelected | "You have not selected a storage device.  You will need to select one before you can save.  Until then, Autosave is disabled." |
| 0x1420af7b0 | sNoEatQuestItem | "You can not eat quest items." |
| 0x1420af828 | sNoFastTravelAlarm | "You cannot fast travel while guards are pursuing you." |
| 0x1420acac8 | sNoFastTravelCell | "You cannot fast travel from this location." |
| 0x1420acab0 | sNoFastTravelCombat | "You cannot fast travel during combat!" |
| 0x1420aca98 | sNoFastTravelDefault | "You cannot fast travel at this time." |
| 0x1420af7f8 | sNoFastTravelHostileActorsNear | "You cannot fast travel when enemies are nearby." |
| 0x1420acb28 | sNoFastTravelInAir | "You can't fast travel while jumping or falling." |
| 0x1420acaf8 | sNoFastTravelOverencumbered | "You cannot fast travel while overencumbered." |
| 0x1420acae0 | sNoFastTravelScriptBlock | "Fast travel is currently unavaliable from this location." |
| 0x1420acb10 | sNoFastTravelUndiscovered | "You have not discovered this location yet." |
| 0x1420ad470 | sNoItemsToRepair | "No items to repair" |
| 0x1420ac018 | sNoJumpWarning | "You can not drop objects while in the air." |
| 0x1420af570 | sNoKeyDropWarning | "You cannot drop keys." |
| 0x1420af5b8 | sNoLockPickIfCrimeAlert | "You can't pick a lock while being pursued by guards." |
| 0x1420af7c8 | sNoMoreFollowers | "You have too many followers." |
| 0x1420abdf0 | sNone | "None" |
| 0x1420af768 | sNoPickPocketAgain | " has already caught you." |
| 0x1420ac648 | sNoProfileSelected | "You have not signed in to a Gamer Profile.  You will need to sign in to a Gamer Profile and then select a storage device before you can save.  Until then, Autosave is disabled." |
| 0x1420af2a0 | sNoRepairHostileActorsNear | "You cannot repair items when enemies are nearby." |
| 0x1420ad4b8 | sNoRepairInCombat | "You cannot repair items while in combat." |
| 0x1420ac5e8 | sNoRestart | "No, keep playing." |
| 0x1420ae508 | sNormal | "Normal" |
| 0x1420a6798 | sNormalWeaponsResisted | "Your attack has no effect." |
| 0x1420ae478 | sNoSaves | "[NO SAVES FOUND]" |
| 0x1420af798 | sNoSitOnOwnedFurniture | "You cannot sit on owned furniture." |
| 0x1420af378 | sNoSleepDefault | "You cannot sleep at this time." |
| 0x1420af3c0 | sNoSleepHostileActorsNear | "You cannot sleep when enemies are nearby." |
| 0x1420af3d8 | sNoSleepInAir | "You cannot sleep in the air." |
| 0x1420af3f0 | sNoSleepInCell | "You cannot sleep in this location." |
| 0x1420af438 | sNoSleepInOwnedBed | "You cannot sleep in an owned bed." |
| 0x1420af408 | sNoSleepTakingHealthDamage | "You cannot sleep while taking health damage." |
| 0x1420af390 | sNoSleepTrespass | "You cannot sleep while trespassing." |
| 0x1420af3a8 | sNoSleepWarnToLeave | "You cannot sleep while being asked to leave." |
| 0x1420af420 | sNoSleepWhileAlarm | "You cannot sleep while guards are pursuing you." |
| 0x1420ad488 | sNoSpareParts | "NO USABLE SPARE PARTS" |
| 0x1420af750 | sNoTalkFleeing | " is fleeing for their life." |
| 0x1420af738 | sNoTalkUnConscious | " is unconscious." |
| 0x1420af870 | sNotAllowedToUseAutoDoorsWhileonHorse | "Dismount Horse before going through door." |
| 0x1420ac000 | sNotEnoughRoomWarning | "You do not have enough room to drop this object." |
| 0x1420aea90 | sNotEnoughVendorGold | "Transaction value: %d gold.\nVendor only has %d gold." |
| 0x1420b61a0 | sNoText | "No" |
| 0x1420790d0 | sNoviceDisplayName | "Novice" |
| 0x1420af2b8 | sNoWaitDefault | "You cannot wait at this time." |
| 0x1420af300 | sNoWaitHostileActorsNear | "You cannot wait when enemies are nearby." |
| 0x1420af318 | sNoWaitInAir | "You cannot wait in the air." |
| 0x1420af330 | sNoWaitInCell | "You cannot wait in this location." |
| 0x1420af348 | sNoWaitTakingHealthDamage | "You cannot wait while taking health damage." |
| 0x1420af2d0 | sNoWaitTrespass | "You cannot wait while trespassing." |
| 0x1420af2e8 | sNoWaitWarnToLeave | "You cannot wait while being asked to leave." |
| 0x1420af360 | sNoWaitWhileAlarm | "You cannot wait while guards are pursuing you." |
| 0x1420ade00 | sNumberAbbrev | "No." |
| 0x1420ac840 | sObjectFade | "Object Fade" |
| 0x1420aca50 | sObjectInUse | "This object is already in use by someone else." |
| 0x1420ae700 | sObjectLODFade | "Object LOD Fade" |
| 0x1420af468 | sOf | " of " |
| 0x1420abe50 | sOff | "OFF" |
| 0x1420abc70 | sOk | "Ok" |
| 0x1420b6218 | sOKText | "OK" |
| 0x1420ad1d0 | sOldDownloadsAvailable | "View Available Content" |
| 0x1420abe38 | sOn | "ON" |
| 0x1420aed18 | sOpen | "Open" |
| 0x1420acbe8 | sOpenedContainer | "Opened the container with a key." |
| 0x1420ac1b0 | sOpenWithKey | "Unlocked with %s." |
| 0x1420b0140 | sOptional | "Optional" |
| 0x1420aef40 | sOr | "OR" |
| 0x1420afb40 | sOrcish | "ORCISH" |
| 0x1420ac198 | sOutOfLockpicks | "You are out of lockpicks." |
| 0x1420ac090 | sOverEncumbered | "You are carrying too much to be able to run." |
| 0x1420aee20 | sOwned | "Owned" |
| 0x142079180 | sParticleArrayAttachExcludeList | "Node1,Node2,Node3" |
| 0x1420ad200 | sPauseText | "Pause" |
| 0x1420b01a0 | sPCControlsTextNone | "None" |
| 0x1420b01d0 | sPCControlsTextPrefix | "Text" |
| 0x1420b01b8 | sPCControlsTriggerPrefix | "Trigger" |
| 0x1420af9a8 | sPCRelationshipNegativeChangeText | " is no longer your " |
| 0x1420af990 | sPCRelationshipPositiveChangeText | " is now your " |
| 0x1420ad278 | sPickpocket | "Pickpocket" |
| 0x1420ad650 | sPickpocketFail | "You've been caught pickpocketing." |
| 0x1420ac7c8 | sPipboyColor | "Pip-Boy Color" |
| 0x1420af0c0 | sPlaceMarker | "Place Marker" |
| 0x1420af0d8 | sPlaceMarkerUndiscovered | "You have not discovered this location yet.\nPlace marker?" |
| 0x1420aee68 | sPlayerDisarmedMessage | "You have been disarmed!" |
| 0x1420acc18 | sPlayerLeavingBorderRegion | "You cannot go that way." |
| 0x1420accf0 | sPlayerSetMarkerName | "Custom Destination" |
| 0x1420ae550 | sPlayTime | "Play Time" |
| 0x1420ae748 | sPleaseStandBy | "PLEASE STAND BY" |
| 0x1420ac1e0 | sPoisonAlreadyPoisonedMessage | "The current weapon is already poisoned." |
| 0x1420af5e8 | sPoisonBowConfirmMessage | "Do you want to poison your next shot with the " |
| 0x1420ac1f8 | sPoisonConfirmMessage | "Do you want to poison the " |
| 0x1420af8d0 | sPoisoned | "You have been poisoned." |
| 0x1420ac1c8 | sPoisonNoWeaponMessage | "You must first equip a weapon to poison it." |
| 0x1420af600 | sPoisonUnableToPoison | "Current weapon cannot be poisoned." |
| 0x1420ad6c8 | sPotions | "POTIONS" |
| 0x1420ad7e8 | sPowers | "POWERS" |
| 0x1420b01e8 | sPresenceInMenu | "In Menu" |
| 0x1420b0200 | sPresencePlayingLevel | "Level: %d" |
| 0x1420ae4f0 | sPressControl | "Press the new control for this action" |
| 0x1420ae5b0 | sPrevious | "Previous" |
| 0x1420aff30 | sPreviousSelection | "Previous Selection" |
| 0x1420af258 | sPrisoner | "Prisoner" |
| 0x14209cae0 | sPronounFemale | "she" |
| 0x14209cbd0 | sPronounIntFemale | "herself" |
| 0x14209cbb8 | sPronounIntMale | "himself" |
| 0x14209cac8 | sPronounMale | "he" |
| 0x14209cb10 | sPronounObjFemale | "her" |
| 0x14209caf8 | sPronounObjMale | "him" |
| 0x14209cb40 | sPronounPosFemale | "hers" |
| 0x14209cb28 | sPronounPosMale | "his" |
| 0x14209cb70 | sPronounPosObjFemale | "her" |
| 0x14209cb58 | sPronounPosObjMale | "his" |
| 0x14209cba0 | sPronounRefFemale | "herself" |
| 0x14209cb88 | sPronounRefMale | "himself" |
| 0x1420ad5a8 | sQuantity | "Quantity" |
| 0x1420abee0 | sQuestAddedText | "Quest added" |
| 0x1420abef8 | sQuestCompletedText | "Quest completed" |
| 0x1420abf28 | sQuestFailed | "Quest FAILED" |
| 0x1420abf10 | sQuestUpdatedText | "Quest updated" |
| 0x1420ac498 | sQuickLoading | "Quickloading..." |
| 0x1420ae538 | sQuicksaveAbbrev | "QUICK" |
| 0x1420ac480 | sQuickSaving | "Quicksaving..." |
| 0x1420b0188 | sQuitAlchemy | "Quit alchemy?" |
| 0x1420aff48 | sQuitEnchanting | "Quit enchanting?" |
| 0x1420acc90 | sRadioSignalLost | "%s signal lost." |
| 0x1420acca8 | sRadioStationDiscovered | "%s signal found." |
| 0x1420ae3a0 | sRadioVolume | "Radio" |
| 0x14207b108 | sRandomDoorTeleportFailureMessage | "This door leads nowhere." |
| 0x1420ac930 | sRangeText | "Range" |
| 0x1420af078 | sRanksText | "Ranks" |
| 0x1420aed48 | sRead | "Read" |
| 0x14207bcf0 | sRefAttachNodeName | "REF_ATTACH_NODE" |
| 0x1420aca68 | sRemoteActivation | "This object is activated from somewhere else." |
| 0x1420b0170 | sRemove | "Remove" |
| 0x1420af9f0 | sRemoveCrimeGold | "crimegold removed from" |
| 0x1420abe98 | sRemoveItemfromInventory | "Removed" |
| 0x1420acd50 | sRemoveMarker | "Remove It" |
| 0x1420aff78 | sRenameItem | "Rename Item" |
| 0x1420ad3e0 | sRepair | "REPAIR" |
| 0x1420ad458 | sRepairAllItems | "Repair All (%d)" |
| 0x1420ad428 | sRepairCost | "Cost: %d caps" |
| 0x1420ad440 | sRepairItem | "Repair" |
| 0x1420ad3f8 | sRepairServicesTitle | "Repair Services" |
| 0x1420ad410 | sRepairSkill | "Repair Skill" |
| 0x1420ad4a0 | sRepairSkillTooLow | "%d%s REPAIR SKILL NEEDED" |
| 0x1420b0218 | sReportModCat_Explicit | "Explicit Content" |
| 0x1420ae958 | sReportModCat_General | "Other" |
| 0x1420b0230 | sReportModCat_Harassment | "Harassment" |
| 0x1420b0248 | sReportModCat_Impersonation | "Impersonation of User" |
| 0x1420b0260 | sReportModCat_PrivateInfo | "Use of Private Information" |
| 0x1420b0278 | sReportModCat_Profanity | "Profanity" |
| 0x1420b0290 | sReportModCat_Racial | "Racial Discrimination" |
| 0x1420b02a8 | sReportModCat_Religious | "Religious Discrimination" |
| 0x1420b02c0 | sReportModCat_Slander | "Slander" |
| 0x1420b02d8 | sReportModCat_Spam | "Spam" |
| 0x1420ae928 | sReportModChooseCategory | "What Terms of Service violation is this mod being reported for?" |
| 0x1420ae940 | sReportModConfirm | "Report mod for explicit content, general abuse or violations of Code of Conduct/Terms of Service?" |
| 0x1420afa68 | sRequirements | "Requirements" |
| 0x1420af060 | sRequirementsText | "Requires:  " |
| 0x1420ae658 | sResetToDefaults | "Reset your control mappings to their default settings?" |
| 0x1420ac798 | sResolution | "Resolution" |
| 0x1420ad3b0 | sResource | "Resource" |
| 0x1420ac630 | sRestartBecauseContentRemoved | "The game must restart now because downloaded content has been removed." |
| 0x1420ae730 | sRestartSignedOut | "You have signed out of your profile and will now be returned to the main menu." |
| 0x1420ac5b8 | sRestartToUseNewContent | "New content has been added.  You will need to restart to use this content.  All unsaved progress will be lost." |
| 0x1420ac618 | sRestartToUseProfileContent | "In order to use the downloaded content associated with this profile, you will need to restart." |
| 0x1420ad7d0 | sRestoration | "RESTORATION" |
| 0x1420ae880 | sResultsFor | "Results For '%s'" |
| 0x1420b61e8 | sRetryText | "Retry" |
| 0x1420abe20 | sReturn | "Return" |
| 0x1420af918 | sRewardXP | "Experience Points Earned" |
| 0x1420af930 | sRewardXPIcon | "Interface\\Shared\\Messages\\glow_XP_Gain.dds" |
| 0x1420aedf0 | sRide | "Ride" |
| 0x1420ade48 | sRSMAge | "Age" |
| 0x1420ae208 | sRSMBody | "Body" |
| 0x1420ae268 | sRSMBrow | "Brow" |
| 0x1420ae0a0 | sRSMBrowForward | "Brow Forward" |
| 0x1420ae070 | sRSMBrowHeight | "Brow Height" |
| 0x1420aded8 | sRSMBrowTypes | "Brow Type" |
| 0x1420ae088 | sRSMBrowWidth | "Brow Width" |
| 0x1420ae010 | sRSMCheekboneHeight | "Cheekbone Height" |
| 0x1420ae028 | sRSMCheekboneWidth | "Cheekbone Width" |
| 0x1420ae160 | sRSMCheekColor | "Cheek Color" |
| 0x1420af1e0 | sRSMCheekColorLower | "Cheek Color Lower" |
| 0x1420af210 | sRSMChinColor | "Chin Color" |
| 0x1420ae118 | sRSMChinForward | "Chin Forward" |
| 0x1420ae100 | sRSMChinLength | "Chin Length" |
| 0x1420ae0e8 | sRSMChinWidth | "Chin Width" |
| 0x1420af168 | sRSMComplexion | "Complexion" |
| 0x1420af180 | sRSMComplexionColor | "Complexion Color" |
| 0x1420af0f0 | sRSMConfirm | "Are you sure you want to be this character?" |
| 0x1420af108 | sRSMConfirmDestruction | "Change preset and lose your changes?" |
| 0x1420af198 | sRSMDirt | "Dirt" |
| 0x1420af1b0 | sRSMDirtColor | "Dirt Color" |
| 0x1420adec0 | sRSMEyeColor | "Eye Color" |
| 0x1420ae130 | sRSMEyeDepth | "Eye Depth" |
| 0x1420ae058 | sRSMEyeHeight | "Eye Height" |
| 0x1420ae178 | sRSMEyelinerColor | "Eyeliner Color" |
| 0x1420ae250 | sRSMEyes | "Eyes" |
| 0x1420ae1a8 | sRSMEyeSocketLowerColor | "Eye Tint" |
| 0x1420ae190 | sRSMEyeSocketUpperColor | "Eye Shadow" |
| 0x1420adea8 | sRSMEyeTypes | "Eye Shape" |
| 0x1420ae040 | sRSMEyeWidth | "Eye Width" |
| 0x1420ae238 | sRSMFace | "Face" |
| 0x1420adf50 | sRSMFacialHairColorPresets | "Facial Hair Color" |
| 0x1420adf38 | sRSMFacialHairPresets | "Facial Hair" |
| 0x1420af138 | sRSMFinishedWarning | "Finished?" |
| 0x1420af240 | sRSMForeheadColor | "Forehead Color" |
| 0x1420ae298 | sRSMHair | "Hair" |
| 0x1420adf20 | sRSMHairColorPresets | "Hair Color" |
| 0x1420adf08 | sRSMHairPresets | "Hair" |
| 0x1420ae220 | sRSMHead | "Head" |
| 0x1420ade60 | sRSMHeadPresets | "Presets" |
| 0x1420adff8 | sRSMJawForward | "Jaw Forward" |
| 0x1420adfe0 | sRSMJawHeight | "Jaw Height" |
| 0x1420adfc8 | sRSMJawWidth | "Jaw Width" |
| 0x1420af1c8 | sRSMLaughLines | "Laugh Lines" |
| 0x1420ae148 | sRSMLipColor | "Lip Color" |
| 0x1420ae280 | sRSMMouth | "Mouth" |
| 0x1420ae0d0 | sRSMMouthForward | "Mouth Forward" |
| 0x1420ae0b8 | sRSMMouthHeight | "Mouth Height" |
| 0x1420adef0 | sRSMMouthTypes | "Mouth Shape" |
| 0x1420ae1d8 | sRSMName | "Name" |
| 0x1420af120 | sRSMNameWarning | "Rename character." |
| 0x1420af228 | sRSMNeckColor | "Neck Color" |
| 0x1420af1f8 | sRSMNoseColor | "Nose Color" |
| 0x1420adfb0 | sRSMNoseHeight | "Nose Height" |
| 0x1420adf98 | sRSMNoseLength | "Nose Length" |
| 0x1420ade90 | sRSMNoseTypes | "Nose Type" |
| 0x1420adf80 | sRSMPaint | "War Paint" |
| 0x1420af150 | sRSMPaintColor | "War Paint Color" |
| 0x1420ae1f0 | sRSMRace | "Race" |
| 0x1420adf68 | sRSMScars | "Scars" |
| 0x1420ade18 | sRSMSex | "Sex" |
| 0x1420ae1c0 | sRSMSkinColor | "Skin Tone" |
| 0x1420ade78 | sRSMTone | "Skin Tone" |
| 0x1420ade30 | sRSMWeight | "Weight" |
| 0x1420ae388 | sRumble | "Vibration" |
| 0x1420ac558 | sSaveFailed | "Save failed." |
| 0x1420ac228 | sSaveGameContentIsMissing | "This save relies on content that is no longer present. Some objects may no longer be available. Continue Loading?" |
| 0x1420ac3a8 | sSaveGameCorrupt | "SAVE CORRUPT" |
| 0x1420ac3f0 | sSaveGameCorruptMenuMessage | "The save game is corrupt and cannot be loaded." |
| 0x1420ac240 | sSaveGameDeviceError | "There was an error accessing the device.  Please try again." |
| 0x1420ac390 | sSaveGameIsCorrupt | "The save game is corrupt.  Returning to game." |
| 0x1420ac3d8 | sSaveGameNoLongerAvailable | "The save game is no longer available.  Returning to game." |
| 0x1420ac378 | sSaveGameNoMasterFilesFound | "None of the master files used in this save game are loaded.  Returning to game." |
| 0x1420ac3c0 | sSaveGameOldVersion | "SAVE OBSOLETE" |
| 0x1420ac258 | sSaveGameOutOfDiskSpace | "The maximum number of saves has been reached. Please delete older saves in order to be able to create a new one." |
| 0x1420ac270 | sSaveNotAvailable | "No valid save game found." |
| 0x1420ac750 | sSaveOnRest | "Save On Rest" |
| 0x1420ac780 | sSaveOnTravel | "Save On Travel" |
| 0x1420ac768 | sSaveOnWait | "Save On Wait" |
| 0x1420ac408 | sSaveOverSaveGame | "Are you sure you want to overwrite this save game?" |
| 0x1420ac540 | sSaveSuccessful | "Save successful." |
| 0x1420af858 | sSceneBlockingActorActivation | "This person is in a conversation." |
| 0x1420ac138 | sScrollEquipped | " equipped." |
| 0x1420ad6f8 | sScrolls | "SCROLLS" |
| 0x1420ad290 | sSearch | "Search" |
| 0x14207a588 | sSeasonFall | "Fall" |
| 0x14207a558 | sSeasonSpring | "Spring" |
| 0x14207a570 | sSeasonSummer | "Summer" |
| 0x14207a5a0 | sSeasonWinter | "Winter" |
| 0x14207a1b0 | sSecondOrdSuffix | "nd" |
| 0x1420abe68 | sSelect | "Select" |
| 0x1420ac870 | sSelectItemToRepair | "CHOOSE ITEM TO REPAIR WITH" |
| 0x1420ac948 | sSelfRange | "Self" |
| 0x1420af450 | sServeSentenceQuestion | "Do you want to serve your time in jail?" |
| 0x1420aca80 | sServeTimeQuestion | "Do you just want to serve your time?" |
| 0x1420ae988 | sSexFemale | "female" |
| 0x1420ae9b8 | sSexFemalePossessive | "her" |
| 0x1420ae9e8 | sSexFemalePronoun | "she" |
| 0x1420ae970 | sSexMale | "male" |
| 0x1420ae9a0 | sSexMalePossessive | "his" |
| 0x1420ae9d0 | sSexMalePronoun | "he" |
| 0x1420ae6b8 | sShadowFade | "Shadow Fade" |
| 0x1420aeca0 | sShouts | "SHOUTS" |
| 0x1420af030 | sSingleDragonSoulCount | "%i Dragon Soul" |
| 0x1420aedc0 | sSit | "Sit" |
| 0x1420acdc8 | sSkillIncreased | "%s Increased to %i" |
| 0x1420acde0 | sSkillIncreasedNum | "%s increased by %d" |
| 0x1420abfe8 | sSkillsCount | "Tag %d Skill" |
| 0x1420abfa0 | sSkillsTitle | "SKILLS:  %d/%d Selected" |
| 0x1420abd78 | sSmall | "Small" |
| 0x1420afe40 | sSmithingConfirm | "Do you want to improve this item?" |
| 0x1420afdb0 | sSmithingMenuDescription | "Choose an item to improve" |
| 0x1420ad578 | sSortMethod | "Sort" |
| 0x1420ac0a8 | sSoulCaptured | "You have captured a soul!" |
| 0x1420aff18 | sSoulGem | "Soul Gem" |
| 0x1420afe88 | sSoulGems | "SOUL GEMS" |
| 0x1420acbd0 | sSoulGemTooSmall | "There is no Soul Gem large enough to capture the soul." |
| 0x1420aefd0 | sSoulLevel | "Filled with %s Soul" |
| 0x14207b540 | sSoulLevelNameCommon | "Common" |
| 0x14207b5a0 | sSoulLevelNameGrand | "Grand" |
| 0x14207b570 | sSoulLevelNameGreater | "Greater" |
| 0x14207b510 | sSoulLevelNameLesser | "Lesser" |
| 0x14207b4e0 | sSoulLevelNamePetty | "Petty" |
| 0x1420abc58 | sSpace | " " |
| 0x1420ae6e8 | sSpecularityFade | "Specularity Fade" |
| 0x1420ada10 | sSpeechChallengeFailure | "[FAILED]" |
| 0x1420ad9f8 | sSpeechChallengeSuccess | "[SUCCESS]" |
| 0x1420a94e0 | sSplashParticles | "Effects\\waterSplash.NIF" |
| 0x1420adbc0 | sStatsMustSelectPerk | "You must select a perk." |
| 0x1420aebb0 | sStatsNextRank | "Next Rank:" |
| 0x1420aeb98 | sStatsPerkConfirm | "Are you sure you want this perk?" |
| 0x1420ad260 | sSteal | "Steal" |
| 0x1420aee50 | sStealFrom | "Steal from" |
| 0x1420acd80 | sStealHorse | "Do you want to steal this horse?" |
| 0x1420afbb8 | sSteel | "STEEL" |
| 0x1420ad350 | sStormcloak | "Stormcloak" |
| 0x1420afbd0 | sStudded | "STUDDED" |
| 0x1420af6a8 | sSuccessfulSneakAttackEnd | "X damage!" |
| 0x1420af690 | sSuccessfulSneakAttackMain | "Sneak attack for " |
| 0x1420aed78 | sTake | "Take" |
| 0x1420ad500 | sTakeAll | "Take All" |
| 0x1420aedd8 | sTalk | "Talk" |
| 0x1420ac960 | sTargetRange | "Target" |
| 0x1420aec70 | sTeammateCantGiveOutfit | "Your teammate already owns that armor." |
| 0x1420aec58 | sTeammateCantTakeOutfit | "You can't take your teammate's starting armor." |
| 0x1420ad668 | sTeammateOverencumbered | "can't carry any more." |
| 0x14209de68 | sTestTopicSetting | "" |
| 0x1420acb40 | sTESVDLC2DragonUnableToFlyMessage | "Your dragon cannot fast travel right now." |
| 0x1420af510 | sTESVDLC2FlyingDragonNoCastMessage | "You cannot cast that type of spell while riding a dragon." |
| 0x1420af558 | sTESVDLC2FlyingMountCancelLandingMessage | "Cancelling your request to land." |
| 0x1420af528 | sTESVDLC2FlyingMountCannotLandMessage | "Your dragon cannot land at this time." |
| 0x1420af540 | sTESVDLC2FlyingMountLandingMessage | "Your dragon is searching for a place to land." |
| 0x1420ac7e0 | sTextureSize | "Texture Size" |
| 0x14207a1c8 | sThirdOrdSuffix | "rd" |
| 0x14207a168 | sTimeAM | "AM" |
| 0x14207a1f8 | sTimeHours | "Hours" |
| 0x14207a210 | sTimeMinutes | "Minutes" |
| 0x14207a180 | sTimePM | "PM" |
| 0x14207a648 | sTimeSpanAfternoon | "afternoon" |
| 0x14207a690 | sTimeSpanEvening | "evening" |
| 0x14207a768 | sTimeSpanMidnight | "midnight" |
| 0x14207a600 | sTimeSpanMorning | "morning" |
| 0x14207a720 | sTimeSpanNight | "night" |
| 0x14207a5b8 | sTimeSpanSunrise | "sunrise" |
| 0x14207a6d8 | sTimeSpanSunset | "sunset" |
| 0x1420abd30 | sTo | "To" |
| 0x1420ac978 | sTouchRange | "Strike" |
| 0x1420abfd0 | sTraitsCount | "Choose up to %d Trait" |
| 0x1420abf88 | sTraitsTitle | "OPTIONAL TRAITS:  %d/%d Selected" |
| 0x1420ae718 | sTreeLODFade | "Tree LOD Fade" |
| 0x1420af498 | sTweenDisabledMessage | "Character screen not available to werewolves." |
| 0x1420abec8 | sUnequipItemOnPlayer | "was unequipped" |
| 0x1420aed00 | sUnlock | "Unlock" |
| 0x1420aed90 | sUse | "Use" |
| 0x1420ad5f0 | sValue | "Value" |
| 0x1420ad878 | sVatsAimed | "Aimed" |
| 0x1420ad860 | sVatsAiming | "Aiming" |
| 0x1420ad890 | sVatsBodyPart | "Body Part" |
| 0x1420ad938 | sVATSMessageLowAP | "Low" |
| 0x1420ad968 | sVATSMessageNoAmmo | "You don't have enough ammo." |
| 0x1420ad950 | sVATSMessageZeroChance | "You have zero chance to hit." |
| 0x1420ad8c0 | sVatsSelect | "Select" |
| 0x1420ad8a8 | sVatsTarget | "Target" |
| 0x1420ae5f8 | sVDSGManual | "VDSG MANUAL" |
| 0x1420adde8 | sVDSGPlate | "VDSG Plate" |
| 0x142079d90 | sVerletCape | "vamplordcapemesh" |
| 0x1420ad1a0 | sVideoChange | "You must exit and restart Skyrim for the new resolution to take effect." |
| 0x1420ac7f8 | sViewDistance | "View Distance" |
| 0x1420acba0 | sVoiceVolume | "Voice" |
| 0x1420aee38 | sWaitHere | "Wait Here" |
| 0x1420ac0d8 | sWeaponBreak | "Your weapon has broken." |
| 0x1420afe58 | sWeaponEnchantments | "WEAPON ENCHANTMENTS" |
| 0x1420ad698 | sWeapons | "WEAPONS" |
| 0x1420afd80 | sWeaponSmithing | "Weapon Smithing" |
| 0x1420ad5d8 | sWeight | "Weight" |
| 0x1420ae580 | sWhite | "WHITE" |
| 0x1420af9d8 | sWitnessKilled | "Last witness killed." |
| 0x1420afc30 | sWood | "WOOD" |
| 0x1420ae340 | sXSensitivity | "X-Sensitivity" |
| 0x1420abc88 | sYes | "Yes" |
| 0x1420ac5d0 | sYesRestart | "Yes, restart the game." |
| 0x1420b6188 | sYesText | "Yes" |
| 0x1420b61b8 | sYesToAllText | "Yes to All" |
| 0x1420abd60 | sYour | "Your" |
| 0x1420ae358 | sYSensitivity | "Y-Sensitivity" |

## Ini settings: [Audio]

The value compiled into `SkyrimSE.exe` for each ini setting: what the game uses when neither `Skyrim.ini` nor `SkyrimPrefs.ini` sets it. `skyrim/ini.zap` keeps the few the port reads; this is the whole table. A setting the game fills at run time holds 0 here (iDifficulty and fAutosaveEveryXMins are two).

Read from the static `SettingT<INISettingCollection>` objects in `.data` (24 bytes: the vtable, the value, the pointer to the name; the vtable's RTTI names the class), found by scanning `.data` for pointers to names and checked against REA's `read_bytes` at 0x1420d9078 (fShadowBiasScale:Display). The address is the object's; the value is decoded by the name's type letter (f float, i int, u unsigned, b bool, s string, r and a 32-bit colors).

| address | setting | value |
|---|---|---|
| 0x1420b5c18 | bEnableAudio:Audio | 1 |
| 0x1420b5c30 | bEnableAudioCache:Audio | 1 |
| 0x1420b4a88 | fASFadeInTime:Audio | 3.0 |
| 0x1420b4aa0 | fASFadeOutTime:Audio | 8.0 |
| 0x1420b3d40 | fAudioRumbleBigDeadZone:audio | 0.0 |
| 0x1420b3cb0 | fAudioRumbleBigExponent:audio | 0.5 |
| 0x1420b3d28 | fAudioRumbleBigLerpMax:audio | 1.0 |
| 0x1420b3d10 | fAudioRumbleBigLerpMin:audio | 0.0 |
| 0x1420b3d58 | fAudioRumblePowerAttackAdj:audio | 0.15 |
| 0x1420b3cf8 | fAudioRumbleSmallDeadZone:audio | 0.0 |
| 0x1420b3c98 | fAudioRumbleSmallExponent:audio | 0.4 |
| 0x1420b3ce0 | fAudioRumbleSmallLerpMax:audio | 1.0 |
| 0x1420b3cc8 | fAudioRumbleSmallLerpMin:audio | 0.0 |
| 0x1420b5708 | fCollisionSoundHeavyThreshold:Audio | 160.0 |
| 0x1420b5c60 | fDefaultMasterVolume:Audio | 1.0 |
| 0x142079ed8 | fDialogueHeadPitchExaggeration:Audio | 2.0 |
| 0x142079ef0 | fDialogueHeadRollExaggeration:Audio | 2.0 |
| 0x142079f08 | fDialogueHeadYawExaggeration:Audio | 2.0 |
| 0x1420b6b78 | fHardLandingDamageThreshold:Audio | 500.0 |
| 0x1420b4b78 | fHighlightSpeechOverlap:Audio | 0.5 |
| 0x1420b4b60 | fMaxHighlightRadius:Audio | 250.0 |
| 0x1420b4b18 | fMenuModeFadeInTime:Audio | 0.5 |
| 0x1420b4b00 | fMenuModeFadeOutTime:Audio | 0.5 |
| 0x14209e2b8 | fMinSoundVel:Audio | 60.0 |
| 0x14207e310 | fMusicDuckingSeconds:Audio | 1.0 |
| 0x14207e340 | fMusicFinaleCrossFadeTimeIn:Audio | 3.0 |
| 0x14207e358 | fMusicFinaleCrossFadeTimeOut:Audio | 6.0 |
| 0x14207e328 | fMusicUnDuckingSeconds:Audio | 4.0 |
| 0x1420bab90 | fNonDialogVoiceDucking:Audio | 9.0 |
| 0x1420babc0 | fNonDialogVoiceDuckingFadeIn:Audio | 1.0 |
| 0x1420baba8 | fNonDialogVoiceDuckingFadeOut:Audio | 1.5 |
| 0x1420b4b30 | fNonHighlightSpeechAtten:Audio | 12.0 |
| 0x1420b4ab8 | fRegionLoopFadeInTime:Audio | 6.0 |
| 0x1420b4ad0 | fRegionLoopFadeOutTime:Audio | 8.0 |
| 0x1420b4a28 | fRegionRandomSoundPlacementBase:Audio | 100.0 |
| 0x1420b4a40 | fRegionSoundPlacementRandomOffset:Audio | 650.0 |
| 0x1420b4a58 | fRegionSoundPlacementZOffset:Audio | 256.0 |
| 0x1420b4ae8 | fReverbTransitionTime:Audio | 0.5 |
| 0x1420b35c0 | fWaterAudioFadeInSeconds:Audio | 3.0 |
| 0x1420b35d8 | fWaterAudioFadeOutSeconds:Audio | 5.0 |
| 0x1420b56f0 | iCollisionSoundTimeDelta:Audio | 150 |
| 0x1420b4b48 | iHighlightSpeechOverlap:Audio | 500 |
| 0x1420b5c00 | sAudioAPI:Audio | "XAudio2" |
| 0x1420ba030 | sDeathCameraEffect:Audio | "MAGShoutSlowTimeActiveLP" |
| 0x1420b5cc0 | sMissingAssetSoundFile:Audio | "" |
| 0x1420b5cf0 | uAsyncReadPriorityThreshold:Audio | 64 |
| 0x1420b4ba8 | uAudioThreadSleepTimeGameMode:Audio | 33 |
| 0x1420b4b90 | uAudioThreadSleepTimeMenuMode:Audio | 1 |
| 0x1420b5c48 | uMaxSizeForCachedSound:Audio | 262144 |
| 0x1420b4a70 | uRegionSoundsAllowedPerUpdate:Audio | 1 |
| 0x1420b5cd8 | uStreamingThreshold:Audio | 4194304 |
| 0x1420b3620 | uWaterAudioAmbientAttenuation:Audio | 2200 |
| 0x1420b3608 | uWaterAudioAxisSamplePoints:Audio | 8 |
| 0x1420b35f0 | uWaterAudioSamplePointsToUse:Audio | 8 |

## Ini settings: [Combat], [Animation], [RagdollAnim], the IK sections, [HAVOK], [Verlet], [GamePlay]

The value compiled into `SkyrimSE.exe` for each ini setting: what the game uses when neither `Skyrim.ini` nor `SkyrimPrefs.ini` sets it. `skyrim/ini.zap` keeps the few the port reads; this is the whole table. A setting the game fills at run time holds 0 here (iDifficulty and fAutosaveEveryXMins are two).

Read from the static `SettingT<INISettingCollection>` objects in `.data` (24 bytes: the vtable, the value, the pointer to the name; the vtable's RTTI names the class), found by scanning `.data` for pointers to names and checked against REA's `read_bytes` at 0x1420d9078 (fShadowBiasScale:Display). The address is the object's; the value is decoded by the name's type letter (f float, i int, u unsigned, b bool, s string, r and a 32-bit colors).

| address | setting | value |
|---|---|---|
| 0x142077820 | bAddBipedWhenKeyframed:HAVOK | 0 |
| 0x1420d1cc0 | bAdditiveHeadAnim:LookIK | 1 |
| 0x14207b308 | bAimSights:Combat | 0 |
| 0x1420d1a08 | bAllowCharacterBumper:HAVOK | 1 |
| 0x1420d17a8 | bAllowDeactivationWhileWarmStarting:HAVOK | 0 |
| 0x1420b7228 | bAllowDragonFlightLocationDiscovery:GamePlay | 0 |
| 0x1420b71f8 | bAllowHavokGrabTheLiving:GamePlay | 0 |
| 0x1420c5c68 | bAlwaysDriveRagdoll:Animation | 0 |
| 0x1420c7970 | bAlwaysSaveAllInfo:Animation | 1 |
| 0x1420b6b90 | bAnimInterpEnable:Animation | 1 |
| 0x1420b8270 | bApplyPitchToExtractedMotion:Animation | 1 |
| 0x1420b5770 | bChainExplosionDebug:Combat | 0 |
| 0x1420b9fc0 | bCombatPathSmoothing:Combat | 1 |
| 0x1420b9fd8 | bCombatPathSprinting:Combat | 1 |
| 0x1420b9d28 | bDebugCombat:Combat | 0 |
| 0x1420b3f30 | bDebugCombatAimLocations:Combat | 0 |
| 0x1420b3f00 | bDebugCombatArea:Combat | 0 |
| 0x1420b3f60 | bDebugCombatAttackRange:Combat | 0 |
| 0x1420b96f0 | bDebugCombatCoverReservations:Combat | 0 |
| 0x1420b97d0 | bDebugCombatDetection:Combat | 0 |
| 0x1420b97a0 | bDebugCombatGroups2:Combat | 0 |
| 0x1420b9788 | bDebugCombatGroups:Combat | 0 |
| 0x1420b9e30 | bDebugCombatProjectileLOS:Combat | 0 |
| 0x1420b97b8 | bDebugCombatSearch:Combat | 0 |
| 0x1420b9d58 | bDebugCombatTargetLocations:Combat | 0 |
| 0x1420b3f48 | bDebugCombatTargets:Combat | 0 |
| 0x1420b9e00 | bDebugCombatTextColorDark:Combat | 0 |
| 0x1420b9dc8 | bDebugCombatThreats:Combat | 0 |
| 0x1420b3f18 | bDebugCombatUnreachableLocations:Combat | 0 |
| 0x1420d1898 | bDebugMultithreaded:HAVOK | 0 |
| 0x1420b9770 | bDisableCombatDialogue:Combat | 0 |
| 0x1420b6a88 | bDisableHeadTracking:HeadTracking | 0 |
| 0x1420b69f8 | bDisableNPCAttacks:Combat | 0 |
| 0x1420b7470 | bDisablePlayerCollision:HAVOK | 0 |
| 0x1420b68d8 | bDismemberOneLimb:Combat | 0 |
| 0x1420b3bf8 | bDisplayMarkWarning:Animation | 0 |
| 0x1420c5b28 | bDrawAnimPoseInVDB:Animation | 0 |
| 0x1420c5b10 | bDriveRagdollWithGraph:Animation | 1 |
| 0x1420b8ba0 | bEnableHavokHit:Animation | 0 |
| 0x1420b9d78 | bEncounterZoneTargetRestrict:Combat | 1 |
| 0x1420b71e0 | bEssentialTakeNoDamage:GamePlay | 1 |
| 0x1420b6ba8 | bFeedbackToGraphFromCharacterController:Animation | 1 |
| 0x1420d17f0 | bFindContactPointsOnAdd:HAVOK | 0 |
| 0x1420c5af8 | bFootIK:Animation | 1 |
| 0x1420d1c00 | bFootIK:RagdollAnim | 1 |
| 0x1420b93f0 | bFootIKFeedback:Animation | 1 |
| 0x1420d1d80 | bFootPlacementOn:FootIK | 1 |
| 0x1420b6890 | bForceJumpingFromGraph:HAVOK | 0 |
| 0x14207b320 | bForceNPCsUseAmmo:Combat | 0 |
| 0x1420d1c18 | bGrabIK:RagdollAnim | 1 |
| 0x1420d2200 | bHavokDebug:HAVOK | 0 |
| 0x1420b9440 | bHazardDebug:Combat | 0 |
| 0x1420b71c8 | bHealthBarShowing:GamePlay | 0 |
| 0x1420b6bc0 | bHumanoidFootIKEnable:Animation | 1 |
| 0x1420b8b38 | bInitiallyLoadAllClips:Animation | 0 |
| 0x1420b71b0 | bInstantLevelUp:GamePlay | 0 |
| 0x1420b77a8 | bIronSightsZoomEnable:Combat | 1 |
| 0x14207b2f0 | bLaserSights:Combat | 0 |
| 0x1420b3bb8 | bLoadCollatedAnimTextData:Animation | 1 |
| 0x1420d1c30 | bLookIK:RagdollAnim | 1 |
| 0x1420b4920 | bMagicDebug:Combat | 0 |
| 0x1420c5a00 | bMultiThreadBoneUpdate:Animation | 1 |
| 0x1420b6e60 | bPlayerAlwaysStaggered:Combat | 1 |
| 0x1420b69e0 | bPlayHitLocationIdles:Combat | 1 |
| 0x1420b69c8 | bPlayStaggers:Combat | 1 |
| 0x1420d1c60 | bPoseMatching:RagdollAnim | 1 |
| 0x14207bc78 | bPreventHavokAddAll:HAVOK | 0 |
| 0x14207bc60 | bPreventHavokAddClutter:HAVOK | 0 |
| 0x1420b9458 | bProjectileDebug:Combat | 0 |
| 0x1420d1be8 | bRagdollAnim:RagdollAnim | 1 |
| 0x1420d1c48 | bRagdollFeedback:RagdollAnim | 1 |
| 0x1420c5cc0 | bRandomizeGraphSeed:Animation | 1 |
| 0x1420d21e8 | bRegisterAllVDBViewers:HAVOK | 0 |
| 0x1420d1eb8 | bRigidBodyController:FootIK | 1 |
| 0x1420c5a18 | bSendNonVisibleBehaviorGraphsToSPU:Animation | 1 |
| 0x1420c5cf0 | bShouldProcessRequests:Animation | 1 |
| 0x1420b89e0 | bTargetLockIsToggle:Gameplay | 1 |
| 0x1420b7258 | bTrackProgress:GamePlay | 0 |
| 0x1420d19f0 | bUseCharacterRB:HAVOK | 1 |
| 0x1420d24e0 | bUseCharRBExtrapolation:HAVOK | 1 |
| 0x1420b4cb0 | bUseConstantStepDelta:Verlet | 1 |
| 0x1420d18b0 | bUseConstraintProjector:HAVOK | 1 |
| 0x1420b0758 | bUseCustomizationMorphs:FaceGen | 1 |
| 0x1420b6c78 | bUseNavMeshForMovement:Actor | 1 |
| 0x1420b0740 | bUseRaceMorph:FaceGen | 1 |
| 0x1420b4c98 | bUseRotationBasedTransformUpdate:Verlet | 1 |
| 0x1420c5ca0 | bUseSpeedSampler:Animation | 1 |
| 0x1420b6c08 | bUseSPUGenerate:Animation | 0 |
| 0x1420d2568 | bUseUnsupportedCast:HAVOK | 1 |
| 0x1420c5d28 | bUseVariableCache:Animation | 1 |
| 0x1420d18c8 | bUseWorldLock:HAVOK | 1 |
| 0x1420b94d0 | bVATSProjectileDebug:Combat | 0 |
| 0x1420d1a58 | bWONameSync:Havok | 1 |
| 0x1420d1ab0 | fAccelerationGain:RagdollAnim | 1.0 |
| 0x1420b70f0 | fAimChaseLookingMult:Combat | 3.0 |
| 0x1420b70d8 | fAimDownDegrees:Combat | 90.0 |
| 0x1420b70c0 | fAimUpDegrees:Combat | 90.0 |
| 0x1420d1c78 | fAngleMax:LookIK | 2.0 |
| 0x1420d1c90 | fAngleMaxEase:LookIK | 90.0 |
| 0x1420c5ac8 | fAnimInterpFarDist:Animation | 800.0 |
| 0x1420c5a98 | fAnimInterpMaxTime:Animation | 0.25 |
| 0x1420c5a80 | fAnimInterpMinTime:Animation | 0.08 |
| 0x1420c5ab0 | fAnimInterpNearDist:Animation | 400.0 |
| 0x1420c5ae0 | fAnimInterpSlop:Animation | 0.25 |
| 0x1420d1db0 | fAnkleOffset:FootIK | 0.2 |
| 0x1420c5a68 | fBoneLODDistanceScale:Animation | 1.0 |
| 0x1420b3c10 | fCameraCasterFadeSittingRadius:HAVOK | 45.0 |
| 0x1420d1ba0 | fCameraDist:RagdollAnim | 1000.0 |
| 0x1420d19d8 | fCharControllerWarpDistSqr:HAVOK | 6000000.0 |
| 0x1420d1e28 | fControllerTetherLen:FootIK | 6.0 |
| 0x1420b7050 | fDeathForceCleared:Combat | 1.0 |
| 0x1420b9e48 | fDebugCombatProjectileLOSTime:Combat | 5.0 |
| 0x1420b9e18 | fDebugCombatTextSize:Combat | 0.5 |
| 0x1420b6dd0 | fDecapInitialSpeed:Combat | 250.0 |
| 0x14207bc90 | fDefaultWaterfallCurrentVelocity:HAVOK | 6.0 |
| 0x1420d1930 | fDesiredVel:RagdollAnim | 1.5 |
| 0x1420d1960 | fDetectionUpdateTimeSec:RagdollAnim | 5.0 |
| 0x1420d1cf0 | fDriveGain:GrabIK | 0.25 |
| 0x1420d1ca8 | fEaseAngleShutOff:LookIK | 0.5 |
| 0x1420d1cd8 | fEyeIKDistanceMax:LookIK | 2.5 |
| 0x1420d1f30 | fFeedbackImpulseMult:RagdollAnim | 500.0 |
| 0x1420d1ee8 | fFeedbackOnOffGain:RagdollAnim | 0.3 |
| 0x1420d1f00 | fFeedbackOnOffGainTimeMS:RagdollAnim | 1000.0 |
| 0x1420d1f18 | fFeedbackTimeMS:RagdollAnim | 10000.0 |
| 0x1420b6998 | fFootIKDistance:GamePlay | 1024.0 |
| 0x1420d1d68 | fFootPlantedGain:FootIK | 1.0 |
| 0x1420d1d50 | fFootRaisedGain:FootIK | 0.9 |
| 0x1420d1a38 | fGoodPosCastCheckDepth:HAVOK | 0.1 |
| 0x1420d1a20 | fGoodPosCheckDepth:HAVOK | 0.1 |
| 0x1420b4c68 | fGravity:Verlet | -1500.0 |
| 0x1420d1d20 | fGroundAscendingGain:FootIK | 0.4 |
| 0x1420d1d38 | fGroundDescendingGain:FootIK | 0.4 |
| 0x1420b8b88 | fHavokHitImpulseMult:Animation | 50.0 |
| 0x1420b8b58 | fHavokHitTimeSec:Animation | 3.0 |
| 0x1420b6b60 | fHeadTrackingMaxAngle:HeadTracking | 90.0 |
| 0x1420d1a80 | fHierarchyGain:RagdollAnim | 0.17 |
| 0x1420b6a40 | fHitEffectThresholdMod:Combat | 0.04 |
| 0x1420b6a28 | fHitEffectThresholdSevere:Combat | 0.043 |
| 0x1420b6920 | fHitVectorDelay:Combat | 0.4 |
| 0x1420b7020 | fIdleChangeClearTime:Animation | 1.0 |
| 0x1420d1948 | fImpulseLimit:RagdollAnim | 15.0 |
| 0x1420d2550 | fInAirFallingCharGravityMult:Havok | 1.35 |
| 0x1420b77c0 | fIronSightsZoomDefault:Combat | 50.0 |
| 0x1420b6968 | fJumpAnimDelay:HAVOK | 0.75 |
| 0x1420b4908 | fMagicTargetLocationExtraLargeActorRadius:Gameplay | 256.0 |
| 0x1420b48f0 | fMagicTargetLocationNormalActorRadius:Gameplay | 32.0 |
| 0x1420b78e0 | fMagnetismHeadingMult:Combat | 1.0 |
| 0x1420b78f8 | fMagnetismLookingMult:Combat | 10.0 |
| 0x1420b7928 | fMagnetismObjHeadingMult:Combat | 0.5 |
| 0x1420b7940 | fMagnetismObjLookingMult:Combat | 0.5 |
| 0x1420b7910 | fMagnetismObjStrafeHeadingMult:Combat | 0.0 |
| 0x1420b78b0 | fMagnetismStrafeBaseSpeed:Combat | 350.0 |
| 0x1420b78c8 | fMagnetismStrafeHeadingMult:Combat | 0.5 |
| 0x1420b7898 | fMagnetismStrafeMaxDistance:Combat | 750.0 |
| 0x1420b7210 | fMapMarkerUpdateTime:GamePlay | 0.05 |
| 0x1420d1e58 | fMaxFootCastMilliSec:FootIK | 0.6 |
| 0x1420b6bf0 | fMaxFrameCounterDifferenceToConsiderVisible:Animation | 0.06666667 |
| 0x1420b6b30 | fMaxPathLookAtPointDist:HeadTracking | 512.0 |
| 0x142077838 | fMaxPickTime:HAVOK | 0.003 |
| 0x142077868 | fMaxPickTimeDebug:HAVOK | 0.06 |
| 0x142077880 | fMaxPickTimeDebugVATS:HAVOK | 0.6 |
| 0x142077850 | fMaxPickTimeVATS:HAVOK | 0.03 |
| 0x1420d1e40 | fMaxStepVertError:FootIK | 3.5 |
| 0x1420d1778 | fMaxTime:HAVOK | 0.016666668 |
| 0x1420d1910 | fMaxTimeComplex:HAVOK | 0.033333335 |
| 0x1420b3be0 | fMaxTimeToMarkSec:Animation | 3.0 |
| 0x1420d1bb8 | fMaxTrackingDist:LookIK | 5000.0 |
| 0x1420b6938 | fMinBloodDamage:Combat | 1.0 |
| 0x1420b6b18 | fMinPathLookAtPointDist:HeadTracking | 128.0 |
| 0x1420d1bd0 | fMinTrackingDist:LookIK | 12.0 |
| 0x1420b9488 | fMostCommonProjectileCollisionRadius1:Combat | 0.0 |
| 0x1420b94a0 | fMostCommonProjectileCollisionRadius2:Combat | 0.5 |
| 0x1420b94b8 | fMostCommonProjectileCollisionRadius3:Combat | 10.0 |
| 0x1420b6fc0 | fMotionFeedbackMinAngleDelta:Animation | 20.0 |
| 0x1420b6fd8 | fMotionFeedbackMinSpeed:Animation | 5.0 |
| 0x1420b6fa8 | fMotionFeedbackMinSpeedDelta:Animation | 25.0 |
| 0x1420b6ff0 | fMotionFeedbackMinTime:Animation | 0.5 |
| 0x1420b7120 | fMountDismountTimeout:Animation | 8.0 |
| 0x1420b9e60 | fMountedAttackRange:Combat | 135.0 |
| 0x142077808 | fMoveLimitMass:HAVOK | 95.0 |
| 0x1420b6c90 | fNotVisibleNavmeshMoveDist:Actor | 2048.0 |
| 0x14209a328 | fOD:HAVOK | 0.9 |
| 0x1420d1d08 | fOnOffGain:FootIK | 0.5 |
| 0x1420d1d98 | fOriginalGroundHeightMS:FootIK | -0.11 |
| 0x1420b6b48 | fPathLookAtPointTime:HeadTracking | 2.0 |
| 0x1420d1de0 | fPelvisOffsetDamping:FootIK | 0.2 |
| 0x1420d1dc8 | fPelvisUpDownBias:FootIK | 0.75 |
| 0x1420b7300 | fPlayerCharacterAttackComboStartFraction:Animation | 0.5 |
| 0x1420b72e8 | fPlayerCharacterAttackIntroLength:Animation | 0.0 |
| 0x1420b7318 | fPlayerCharacterDrawSheatheTimeout:Animation | 3.0 |
| 0x1420b72d0 | fPlayerCharacterPowerAttackStartTime:Animation | 0.36666667 |
| 0x1420b7378 | fPlayerHealthSaveOnPauseLimit:GamePlay | 0.25 |
| 0x1420b76e8 | fPlayerSunGazeDelta:Gameplay | 0.984808 |
| 0x1420b76d0 | fPlayerSunGazeStartTimer:GamePlay | 0.5 |
| 0x1420d1ae0 | fPositionGain:RagdollAnim | 0.05 |
| 0x1420d1b10 | fPositionMaxAngularVelocity:RagdollAnim | 18.0 |
| 0x1420d1af8 | fPositionMaxLinearVelocity:RagdollAnim | 14.0 |
| 0x1420b9470 | fProjectileDebugDuration:Combat | 5.0 |
| 0x1420b6878 | fQuadrupedPitchMult:HAVOK | 10.0 |
| 0x1420d1ea0 | fRagdollFeedback:FootIK | 0.7 |
| 0x14209a340 | fRF:HAVOK | 1000.0 |
| 0x14209a2f8 | fSD:HAVOK | 0.98 |
| 0x14209a310 | fSE:HAVOK | 0.3 |
| 0x1420d1b28 | fSnapGain:RagdollAnim | 0.1 |
| 0x1420d1b88 | fSnapMaxAngularDistance:RagdollAnim | 1.0 |
| 0x1420d1b58 | fSnapMaxAngularVelocity:RagdollAnim | 0.3 |
| 0x1420d1b70 | fSnapMaxLinearDistance:RagdollAnim | 0.3 |
| 0x1420d1b40 | fSnapMaxLinearVelocity:RagdollAnim | 3.0 |
| 0x1420b7098 | fSpecialIdlePickTime:Animation | 250.0 |
| 0x1420b7608 | fTargetLockXYRange:Gameplay | 7500.0 |
| 0x1420d17c0 | fTimePerSubStep:HAVOK | 0.008 |
| 0x14209e460 | fTrapHitEventDelayMS:Havok | 500.0 |
| 0x14209e478 | fTriggerEventDelayMS:Havok | 500.0 |
| 0x1420d2598 | fUnsupportCastLength:HAVOK | 1.0 |
| 0x1420d2580 | fUnsupportedGravMult:HAVOK | 4.0 |
| 0x1420b6b00 | fUpdateDelayNewTargetSecondsMax:HeadTracking | 8.0 |
| 0x1420b6ae8 | fUpdateDelayNewTargetSecondsMin:HeadTracking | 3.0 |
| 0x1420b6ad0 | fUpdateDelaySecondsMax:HeadTracking | 1.5 |
| 0x1420b6ab8 | fUpdateDelaySecondsMin:HeadTracking | 1.0 |
| 0x1420d1a98 | fVelocityDamping:RagdollAnim | 0.0 |
| 0x1420d1ac8 | fVelocityGain:RagdollAnim | 0.6 |
| 0x1420d1df8 | fVertErrorGain:FootIK | 0.5 |
| 0x1420b6de8 | fVerticalCapsuleOffset:Verlet | 50.0 |
| 0x1420b6ca8 | fVisibleNavmeshMoveDist:Actor | 4096.0 |
| 0x1420d1790 | fWarmStartMaxTime:HAVOK | 4.0 |
| 0x1420b7008 | fWeaponChangeClearTime:Animation | 0.5 |
| 0x1420b7240 | iActorsDismemberedPerFrame:GamePlay | 2 |
| 0x1420b6980 | iDetectionPicks:GamePlay | 21 |
| 0x142077898 | iEntityBatchRemoveRate:HAVOK | 100 |
| 0x1420b6950 | iMaxHiPerfCombatCount:Combat | 4 |
| 0x1420b6c20 | iMinBonesToGenerateWhileSitting:Animation | 5 |
| 0x1420d17d8 | iMinNumSubSteps:HAVOK | 8 |
| 0x1420d1e10 | iNumFramesFootEaseOut:FootIK | 30 |
| 0x1420b72b8 | iPlayerCharacterImagespaceModifierAnimCount:Animation | 2 |
| 0x1420b6908 | iShowHitVector:Combat | 0 |
| 0x14209e2d0 | iSimType:HAVOK | 1 |
| 0x1420b6aa0 | iUpdateActorsPerFrame:HeadTracking | 10 |
| 0x1420c5a38 | sHkxDBNameContextPrefix:Animation | "meshes\\" |
| 0x1420b7288 | sTrackProgressPath:GamePlay | "\\\\vault2\\Fallout\\LevelData\\" |
| 0x1420b6e00 | uCapeClothNumPin:Verlet | 12 |
| 0x1420d18e0 | uMaxNumPhysicsStepsPerUpdate:HAVOK | 3 |
| 0x1420d18f8 | uMaxNumPhysicsStepsPerUpdateComplex:HAVOK | 1 |
| 0x1420b6bd8 | uVariableCacheSize:Animation | 40 |

## Ini settings: [Controls], [Camera], [VATS], [Cart], [MapMenu], [Menu]

The value compiled into `SkyrimSE.exe` for each ini setting: what the game uses when neither `Skyrim.ini` nor `SkyrimPrefs.ini` sets it. `skyrim/ini.zap` keeps the few the port reads; this is the whole table. A setting the game fills at run time holds 0 here (iDifficulty and fAutosaveEveryXMins are two).

Read from the static `SettingT<INISettingCollection>` objects in `.data` (24 bytes: the vtable, the value, the pointer to the name; the vtable's RTTI names the class), found by scanning `.data` for pointers to names and checked against REA's `read_bytes` at 0x1420d9078 (fShadowBiasScale:Display). The address is the object's; the value is decoded by the name's type letter (f float, i int, u unsigned, b bool, s string, r and a 32-bit colors).

| address | setting | value |
|---|---|---|
| 0x1420ce5b0 | bBackgroundMouse:Controls | 0 |
| 0x1420b80f0 | bDampenPlayerControls:Controls | 1 |
| 0x1420ba3e8 | bDisableAutoVanityMode:Camera | 0 |
| 0x1420b3eb0 | bDragonCameraTargetPlayer:Camera | 1 |
| 0x1420b8950 | bEnableGestureDualSwing:Controls | 1 |
| 0x1420b8968 | bEnableGesturePowerAttackByAccel:Controls | 1 |
| 0x1420b8980 | bEnableGesturePowerAttackByInput:Controls | 1 |
| 0x1420b88a8 | bEnableSixaxisBowAiming:Controls | 0 |
| 0x1420bb0b0 | bEnableSixaxisLockpicking:Controls | 0 |
| 0x1420b88c0 | bEnableSixaxisMagicAiming:Controls | 0 |
| 0x1420ba400 | bForceAutoVanityMode:Camera | 0 |
| 0x1420b8120 | bFreezeDirectionOnLargeDelta:Controls | 1 |
| 0x1420b85a8 | bGamepadLookApplyMaxedOutAcceleration:Controls | 1 |
| 0x1420b85c0 | bGamepadLookApplySensitivityThreshold:Controls | 0 |
| 0x1420b8590 | bGamepadLookApplySnapToAxis:Controls | 1 |
| 0x1420b85d8 | bGamepadLookTimeNormalizeInputs:Controls | 1 |
| 0x1420b8938 | bGestureEngageButtonsRequired:Controls | 1 |
| 0x1420bc710 | bInvertMovementThumbstick:Controls | 0 |
| 0x1420b74a0 | bPlayerGraphFeedback:Controls | 0 |
| 0x1420b5d50 | bRecord:CameraPath | 0 |
| 0x1420bb0c8 | bRequireSixaxisLockpickingEngageLeft:Controls | 1 |
| 0x1420ba700 | bReturnTo1stPersonFromVanity:Camera | 0 |
| 0x1420bccd0 | bShowKinectDebugInfo:Controls | 0 |
| 0x1420b8908 | bSixaxisAimingRespectsFOV:Controls | 1 |
| 0x1420b8920 | bSixaxisAimingRespectsTimeMultiplier:Controls | 1 |
| 0x1420b5d38 | bStart:CameraPath | 0 |
| 0x1420ba950 | bUseConsoleHotkeys:Menu | 0 |
| 0x1420b7850 | bVATSAllowNoKill:VATS | 0 |
| 0x1420b9608 | bVatsDebug:VATS | 0 |
| 0x1420b7808 | bVATSDisable:VATS | 0 |
| 0x1420b7820 | bVATSForceRanged:VATS | 0 |
| 0x1420b7868 | bVATSIgnoreProjectileTest:VATS | 0 |
| 0x1420b7838 | bVATSMultipleCombatants:VATS | 0 |
| 0x1420b7880 | bVATSRangedSelective:VATS | 1 |
| 0x1420b68c0 | bVATSSmartCameraCheckDebug:VATS | 0 |
| 0x1420d91a8 | bWorldMapNoSkyDepthBlur:MapMenu | 0 |
| 0x1420b3c28 | fActorFadeOutLimit:Camera | 30.0 |
| 0x1420ba018 | fAutoVanityIncrement:Camera | 0.01 |
| 0x1420ba3d0 | fAutoVanityModeDelay:Camera | 120.0 |
| 0x1420ba448 | fCameraCasterBleedOutSize:Camera | 5.0 |
| 0x1420ba418 | fCameraCasterSize:Camera | 15.0 |
| 0x1420ba430 | fCameraCasterTargetSize:Camera | 20.0 |
| 0x14209e118 | fCartLimitMax:Cart | 0.75 |
| 0x14209e130 | fCartLimitMin:Cart | -0.75 |
| 0x14209e088 | fCartPivotX:Cart | 0.0 |
| 0x14209e0a0 | fCartPivotY:Cart | 3.0 |
| 0x14209e0b8 | fCartPivotZ:Cart | 0.7 |
| 0x14209e190 | fCartRot1:Cart | 10.0 |
| 0x14209e1a8 | fCartRot2:Cart | 10.0 |
| 0x1420ba460 | fCharControllerCheckHeightOffset:Camera | 124.0 |
| 0x1420ba6e8 | fChaseCameraMaxAngle:Camera | 30.0 |
| 0x1420ba6d0 | fChaseCameraSpeed:Camera | 10.0 |
| 0x1420ba6b8 | fCollisionRecoveryMinDist:Camera | 4000.0 |
| 0x1420ba6a0 | fCollisionRecoverySpeed:Camera | 3.0 |
| 0x1420b80c0 | fControllerBufferDepth:Controls | 0.14 |
| 0x1420b8108 | fControllerDampenTime:Controls | 0.18 |
| 0x1420b80d8 | fControllerSampleThreshold:Controls | 0.1 |
| 0x1420ba000 | fDefaultAutoVanityZoom:Camera | 300.0 |
| 0x1420b8698 | fDialogueHardStopAngle1P:Controls | 45.0 |
| 0x1420b86b0 | fDialogueHardStopAngle3P:Controls | 55.0 |
| 0x1420b8668 | fDialogueSoftStopAngle1P:Controls | 20.0 |
| 0x1420b8680 | fDialogueSoftStopAngle3P:Controls | 25.0 |
| 0x1420bb3e0 | fDirectionalDeadzone:Controls | 0.5 |
| 0x1420b3ee0 | fDragonCameraDollyTime:Camera | 0.75 |
| 0x1420b3e98 | fDragonMaxAngleBeforeTurn:Camera | 90.0 |
| 0x1420b8890 | fDualCastChordTime:Controls | 0.05 |
| 0x1420ba048 | fFirstPersonDisablePOVLerpDPS:Camera | 2.0 |
| 0x1420ba078 | fFirstPersonSittingAngleLimit:Camera | 1.5707964 |
| 0x1420ba060 | fFirstPersonSittingRotationSpeed:Camera | 0.1 |
| 0x1420ba208 | fFreeCameraRotationSpeed:Camera | 3.0 |
| 0x1420ba220 | fFreeCameraRunSpeed:Camera | 2.0 |
| 0x1420ba1f0 | fFreeCameraTranslationSpeed:Camera | 20.0 |
| 0x1420ba238 | fFreeCameraTriggerDeadzone:Camera | 0.1 |
| 0x1420ba580 | fFreeRotationSpeed:Camera | 3.0 |
| 0x1420b8138 | fFreezeDirectionDefaultAngleThreshold:Controls | 60.0 |
| 0x1420b8150 | fFreezeDirectionDefaultSpeedThreshold:Controls | 100.0 |
| 0x14209e250 | fFriction:Cart | 100.0 |
| 0x1420ba268 | fFurnitureCameraAngle:Camera | 0.3926991 |
| 0x1420ba250 | fFurnitureCameraZoom:Camera | 250.0 |
| 0x1420bc4c8 | fGamepadCursorSensitivity:MapMenu | 2.0 |
| 0x1420b83f8 | fGamepadHeadingSensitivityDefault:Controls | 0.66672 |
| 0x1420bc950 | fGamepadHeadingSensitivityMax:Controls | 1.5556 |
| 0x1420bc938 | fGamepadHeadingSensitivityMin:Controls | 0.4445 |
| 0x1420b8428 | fGamepadHeadingXScale:Controls | 1.0 |
| 0x1420b8440 | fGamepadHeadingYScale:Controls | 0.5625 |
| 0x1420b8548 | fGamepadLookAccelPitchMult:Controls | 2.5 |
| 0x1420b8518 | fGamepadLookAccelSec:Controls | 0.92 |
| 0x1420b8530 | fGamepadLookAccelYawMult:Controls | 2.5 |
| 0x1420b8560 | fGamepadLookMultExponent:Controls | 0.0 |
| 0x1420b8998 | fGesturePowerAttackAccelThreshhold:Controls | 4.0 |
| 0x14209e238 | fGravMult:Cart | 3.5 |
| 0x1420b8338 | fHeadingAxisDeadzone:Controls | 0.15 |
| 0x1420b8168 | fHorseClampAngle:Controls | 10.0 |
| 0x1420b7708 | fHorseControlsDampenTime:Controls | 1.0 |
| 0x1420ba4d8 | fHorseDismountYawCorrection:Camera | 0.32 |
| 0x1420b8620 | fHorseHeadingMovementMult:Controls | 1.0 |
| 0x1420ba3a0 | fHorseMaxAngleBeforeTurn:Camera | 90.0 |
| 0x14209e040 | fHorseOffsetX:Cart | 0.0 |
| 0x14209e058 | fHorseOffsetY:Cart | 200.0 |
| 0x14209e070 | fHorseOffsetZ:Cart | 0.0 |
| 0x14209e0d0 | fHorsePivotX:Cart | 0.0 |
| 0x14209e0e8 | fHorsePivotY:Cart | 0.0 |
| 0x14209e100 | fHorsePivotZ:Cart | 0.0 |
| 0x1420babf8 | fHotKeyDelay:Controls | 0.25 |
| 0x1420b8350 | fInitialPowerAttackDelay:Controls | 0.3 |
| 0x1420b8380 | fInitialPowerBashDelay:Controls | 0.3 |
| 0x1420bb0f8 | fLockResetSixaxisWiggleRoom:Controls | 0.08 |
| 0x1420bb0e0 | fLockTurnSixaxisMinThreshhold:Controls | 0.06 |
| 0x1420b8458 | fLookCurveSensitivityThreshold:Controls | 0.1 |
| 0x1420b84b8 | fLookGraphCoefficient1:Controls | 0.115141 |
| 0x1420b84d0 | fLookGraphCoefficient2:Controls | -0.382666 |
| 0x1420b84e8 | fLookGraphCoefficient3:Controls | 2.02865 |
| 0x1420b8500 | fLookGraphCoefficient4:Controls | -0.754499 |
| 0x1420b87a0 | fLookGraphX1:Controls | 0.4 |
| 0x1420b87d0 | fLookGraphX2:Controls | 0.6 |
| 0x1420b8800 | fLookGraphX3:Controls | 0.8 |
| 0x1420b8830 | fLookGraphX4:Controls | 0.9 |
| 0x1420b87b8 | fLookGraphY1:Controls | 0.1 |
| 0x1420b87e8 | fLookGraphY2:Controls | 0.2 |
| 0x1420b8818 | fLookGraphY3:Controls | 0.3 |
| 0x1420b8848 | fLookGraphY4:Controls | 0.6 |
| 0x1420ba478 | fLookingSpeed:Camera | 0.1 |
| 0x1420b8578 | fLookSnapToAxisStrength:Controls | 0.15 |
| 0x1420b8608 | fLookTimeNormalizingFloorFramerate:Controls | 20.0 |
| 0x1420b85f0 | fLookTimeNormalizingTargetFramerate:Controls | 30.0 |
| 0x1420ccd80 | fLThumbDeadzone:Controls | 0.25 |
| 0x1420ccdc8 | fLThumbDeadzoneMax:Controls | 0.97 |
| 0x1420bc4f8 | fMapLocalCursorPanSpeed:MapMenu | 2000.0 |
| 0x1420bc308 | fMapLocalGamepadPanSpeed:MapMenu | 100.0 |
| 0x1420bc2d8 | fMapLocalGamepadZoomSpeed:MapMenu | 0.03 |
| 0x142079f50 | fMapLocalHeight:MapMenu | 40000.0 |
| 0x1420bc338 | fMapLocalMarkerSelectionDist:MapMenu | 0.03 |
| 0x1420bc350 | fMapLocalMinFrustumWidth:MapMenu | 4000.0 |
| 0x1420bc320 | fMapLocalMousePanSpeed:MapMenu | 20.0 |
| 0x1420bc2f0 | fMapLocalMouseZoomSpeed:MapMenu | 0.1 |
| 0x1420bc448 | fMapLookGamepadSpeed:MapMenu | 1.5 |
| 0x1420bc430 | fMapLookMouseSpeed:MapMenu | 3.0 |
| 0x1420bc510 | fMapLoopFadeTimeSeconds:MapMenu | 1.0 |
| 0x1420bc498 | fMapMenuNearClipPlane:MapMenu | 128.0 |
| 0x1420bc5d0 | fMapMenuOverlayNormalSnowStrength:MapMenu | 0.4 |
| 0x1420bc5b8 | fMapMenuOverlayNormalStrength:MapMenu | 1.1 |
| 0x1420bc5e8 | fMapMenuOverlayScale:MapMenu | 3.5e-05 |
| 0x1420bc600 | fMapMenuOverlaySnowScale:MapMenu | 4.5e-05 |
| 0x1420bc478 | fMapMoveKeyboardSpeed:MapMenu | 0.02 |
| 0x1420bc370 | fMapTransitionSpeed:MapMenu | 0.75 |
| 0x1420bc4e0 | fMapWorldCursorMoveArea:MapMenu | 0.9 |
| 0x1420bc418 | fMapWorldHeightAdjustmentForce:MapMenu | 4.0 |
| 0x1420bc3a0 | fMapWorldMaxPanSpeed:MapMenu | 75000.0 |
| 0x1420bc3e8 | fMapWorldMaxPitch:MapMenu | 75.0 |
| 0x1420bc388 | fMapWorldMinPanSpeed:MapMenu | 60000.0 |
| 0x1420bc3d0 | fMapWorldMinPitch:MapMenu | 15.0 |
| 0x1420bc570 | fMapWorldTransitionHeight:MapMenu | 10000.0 |
| 0x1420bc400 | fMapWorldYawRange:MapMenu | 80.0 |
| 0x1420bc3b8 | fMapWorldZoomSpeed:MapMenu | 2.0 |
| 0x1420bc460 | fMapZoomMouseSpeed:MapMenu | 2.0 |
| 0x14209e268 | fMass:Cart | 130.0 |
| 0x1420b8308 | fMaxLookRampUpDelta:Controls | 0.13 |
| 0x1420bc4b0 | fMaxMarkerSelectionDist:MapMenu | 0.003 |
| 0x1420b82f0 | fMaxMoveRampDownDelta:Controls | 500.0 |
| 0x1420ba568 | fMinCurrentZoom:Camera | -0.2 |
| 0x1420bc920 | fMouseHeadingSensitivityMax:Controls | 0.05 |
| 0x1420bc908 | fMouseHeadingSensitivityMin:Controls | 0.01 |
| 0x1420b8488 | fMouseHeadingXScale:Controls | 0.02 |
| 0x1420b84a0 | fMouseHeadingYScale:Controls | 0.85 |
| 0x1420ba5b0 | fMouseWheelZoomIncrement:Camera | 0.075 |
| 0x1420ba5e0 | fMouseWheelZoomMinDelta:Camera | 0.005 |
| 0x1420ba5c8 | fMouseWheelZoomSpeed:Camera | 0.8 |
| 0x1420b86f8 | fMoveGraphX1:Controls | 0.2 |
| 0x1420b8728 | fMoveGraphX2:Controls | 0.7 |
| 0x1420b8758 | fMoveGraphX3:Controls | 0.9 |
| 0x1420b8710 | fMoveGraphY1:Controls | 0.1 |
| 0x1420b8740 | fMoveGraphY2:Controls | 0.5 |
| 0x1420b8770 | fMoveGraphY3:Controls | 0.9 |
| 0x1420b8320 | fMovementAxisDeadzone:Controls | 0.15 |
| 0x1420b86c8 | fOutsideDialogueAngleRotationDampen:Controls | 0.33 |
| 0x1420ba658 | fOverShoulderCombatAddY:Camera | -100.0 |
| 0x1420ba628 | fOverShoulderCombatPosX:Camera | 0.0 |
| 0x1420ba640 | fOverShoulderCombatPosZ:Camera | 20.0 |
| 0x1420b3e38 | fOverShoulderDragonAddY:Camera | -600.0 |
| 0x1420b3e08 | fOverShoulderDragonPosX:Camera | 0.0 |
| 0x1420b3e20 | fOverShoulderDragonPosZ:Camera | 0.0 |
| 0x1420ba340 | fOverShoulderHorseAddY:Camera | -300.0 |
| 0x1420ba310 | fOverShoulderHorsePosX:Camera | 0.0 |
| 0x1420ba328 | fOverShoulderHorsePosZ:Camera | 0.0 |
| 0x1420ba5f8 | fOverShoulderPosX:Camera | 30.0 |
| 0x1420ba610 | fOverShoulderPosZ:Camera | -10.0 |
| 0x1420b8860 | fPCDialogueLookSpeed:Controls | 10.0 |
| 0x1420b8878 | fPCDialogueLookStart:Controls | 25.0 |
| 0x1420ba4f0 | fPitchZeroBlendTime:Camera | 0.75 |
| 0x1420ba688 | fPitchZoomOutMaxDist:Camera | 100.0 |
| 0x1420b74b8 | fPlayerThirdPersonDampenTime:Controls | 0.25 |
| 0x14209e1c0 | fPoleZOffset:Cart | -20.0 |
| 0x1420b82c0 | fReverseDirThreshold:Controls | 0.3 |
| 0x1420ccd98 | fRThumbDeadzone:Controls | 0.25 |
| 0x1420ccde0 | fRThumbDeadzoneMax:Controls | 0.97 |
| 0x1420ba670 | fShoulderDollySpeed:Camera | 3.0 |
| 0x1420b88d8 | fSixaxisAlphaMaxThreshold:Controls | 0.05 |
| 0x1420b88f0 | fSixaxisAlphaMin:Controls | 0.15 |
| 0x142077c70 | fSlowVanityIncrement:Camera | 0.02 |
| 0x1420b82d8 | fSprintStopThreshold:Controls | 0.5 |
| 0x1420b8368 | fSubsequentPowerAttackDelay:Controls | 2.0 |
| 0x1420b8398 | fSubsequentPowerBashDelay:Controls | 2.0 |
| 0x14209e148 | fTetherOffsetX:Cart | 50.0 |
| 0x14209e160 | fTetherOffsetY:Cart | 163.0 |
| 0x14209e178 | fTetherOffsetZ:Cart | 13.0 |
| 0x1420ba598 | fThumbstickZoomSpeed:Camera | 0.05 |
| 0x14209e028 | fTipImpulse:Cart | 500.0 |
| 0x1420b8650 | fTogglePOVDelay:Controls | 0.0 |
| 0x1420ccdb0 | fTriggerDeadzone:Controls | 0.05 |
| 0x1420ba718 | fTweenCamRotAngle:Camera | 0.05 |
| 0x1420ba748 | fTweenCamRotClosingSpeed:Camera | 10.0 |
| 0x1420ba730 | fTweenCamRotSpeed:Camera | 4.0 |
| 0x1420ba760 | fTweenCamZoomFOVMod:Camera | 10.0 |
| 0x1420ba778 | fTweenCamZoomSpeed:Camera | 25.0 |
| 0x1420ba538 | fVanityModeMaxDist:Camera | 600.0 |
| 0x1420ba550 | fVanityModeMaxDistFlyMult:Camera | 4.0 |
| 0x1420ba508 | fVanityModeMinDist:Camera | 155.0 |
| 0x1420ba520 | fVanityModeMinDistFly:Camera | 1200.0 |
| 0x1420b95f0 | fVATSCastingAfterKillDelay:VATS | 1.2 |
| 0x1420b77f0 | fVATSFocus:VATS | 3.2 |
| 0x1420b95d8 | fVATSKillMoveEnd:VATS | 4.0 |
| 0x1420b9548 | fVATSLightAngle:VATS | 0.0 |
| 0x1420b95c0 | fVatsLightColorB:VATS | 1.0 |
| 0x1420b95a8 | fVatsLightColorG:VATS | 1.0 |
| 0x1420b9590 | fVatsLightColorR:VATS | 1.0 |
| 0x1420b9560 | fVATSLightDistance:VATS | 100.0 |
| 0x1420b9578 | fVATSLightElevation:VATS | 100.0 |
| 0x1420b9530 | fVATSLightLevelMax:VATS | 40.0 |
| 0x1420b9518 | fVATSLightLevelMin:VATS | 20.0 |
| 0x1420b9698 | fVATSRangedLongDistance:VATS | 2500.0 |
| 0x1420b9620 | fVATSRangedLowHealthPercent:VATS | 5.0 |
| 0x1420b9680 | fVATSRangedPercentMin:VATS | 50.0 |
| 0x1420b9638 | fVATSRangedPercentSneakKill:VATS | 20.0 |
| 0x1420b9650 | fVATSRangedPercentTargetNoThreat:VATS | 10.0 |
| 0x1420b9668 | fVATSRangedTargetLowLevelMult:VATS | 0.3 |
| 0x14209e280 | fWheelAngDamp:Cart | 0.01 |
| 0x1420ba298 | fWorkbenchCameraPitch:Camera | 0.5 |
| 0x1420ba2c8 | fWorkbenchCameraTranslateX:Camera | 0.0 |
| 0x1420ba2e0 | fWorkbenchCameraTranslateY:Camera | 50.0 |
| 0x1420ba2f8 | fWorkbenchCameraTranslateZ:Camera | -50.0 |
| 0x1420ba2b0 | fWorkbenchCameraYaw:Camera | -1.0 |
| 0x1420ba280 | fWorkbenchCameraZoom:Camera | 100.0 |
| 0x1420bc648 | fWorldMapDepthBlurScale:MapMenu | 0.3 |
| 0x1420bc618 | fWorldMapFocalDepth:MapMenu | 45000.0 |
| 0x1420bc630 | fWorldMapMaximumDepthBlur:MapMenu | 0.45 |
| 0x1420bc660 | fWorldMapNearDepthBlurScale:MapMenu | 4.0 |
| 0x1420b8638 | fZKeyDelay:Controls | 0.2 |
| 0x1420ba4c0 | iAnimatedTransitionMillis:Camera | 1000 |
| 0x1420ba4a8 | iBleedoutTransitionMillis:Camera | 500 |
| 0x1420ba908 | iConsoleHistoryCharBufferSize:Menu | 16384 |
| 0x1420ba8a8 | iConsoleSizeScreenPercent:Menu | 40 |
| 0x1420ba8d8 | iConsoleTextSize:Menu | 20 |
| 0x1420b5d98 | iFPS:CameraPath | 30 |
| 0x1420b89b0 | iGestureShieldTickBuffer:Controls | 200 |
| 0x1420ba490 | iHorseTransitionMillis:Camera | 500 |
| 0x1420b89c8 | iMountedGestureAttackBuffer:Controls | 600 |
| 0x1420bb110 | iNumHotkeys:Controls | 37 |
| 0x1420b8788 | iNumLookGraphSettings:Controls | 4 |
| 0x1420b86e0 | iNumMoveGraphSettings:Controls | 3 |
| 0x1420bc9a8 | iRightStickRepeatRate:MapMenu | 250 |
| 0x1420b5dc8 | iTake:CameraPath | 0 |
| 0x1420ba8f0 | rConsoleHistoryTextColor:Menu | 0x99999999 |
| 0x1420ba8c0 | rConsoleTextColor:Menu | 0xffffffff |
| 0x1420d30b0 | rDebugTextColor:Menu | 0xfffbe9ff |
| 0x1420ba938 | sConsoleDefaultINI:Menu | "SkyrimConsoleDefault.ini" |
| 0x1420ba920 | sConsoleINI:Menu | "SkyrimConsole.ini" |
| 0x1420b5db0 | sDirectoryName:CameraPath | "TestCameraPath" |
| 0x14209e220 | sHarnessBoneCart:Cart | "FrontHorseCarriage01" |
| 0x14209e1f0 | sHarnessBoneLeft:Cart | "HarnessLeftBone" |
| 0x14209e208 | sHarnessBoneRight:Cart | "HarnessRightBone" |
| 0x14209e1d8 | sHorseConnect:Cart | "HorseSpine2" |
| 0x1420bc558 | sMapWorldDefaultWorldSpace:MapMenu | "Tamriel" |
| 0x1420b5d80 | sNif:CameraPath | "Cameras\\CameraTest.nif" |
| 0x1420b5d68 | sOffsetID:CameraPath | "" |
| 0x1420bc5a0 | sWorldMapOverlayNormalSnowTexture:MapMenu | "Data\\Textures\\Terrain\\WorldMapOverlaySnow_n.dds" |
| 0x1420bc588 | sWorldMapOverlayNormalTexture:MapMenu | "Data\\Textures\\Terrain\\WorldMapOverlay_n.dds" |
| 0x1420b3478 | uLockedObjectMapLOD:MapMenu | 16 |
| 0x1420b3460 | uLockedTerrainLOD:MapMenu | 32 |

## Ini settings: [Display]

The value compiled into `SkyrimSE.exe` for each ini setting: what the game uses when neither `Skyrim.ini` nor `SkyrimPrefs.ini` sets it. `skyrim/ini.zap` keeps the few the port reads; this is the whole table. A setting the game fills at run time holds 0 here (iDifficulty and fAutosaveEveryXMins are two).

Read from the static `SettingT<INISettingCollection>` objects in `.data` (24 bytes: the vtable, the value, the pointer to the name; the vtable's RTTI names the class), found by scanning `.data` for pointers to names and checked against REA's `read_bytes` at 0x1420d9078 (fShadowBiasScale:Display). The address is the object's; the value is decoded by the name's type letter (f float, i int, u unsigned, b bool, s string, r and a 32-bit colors).

| address | setting | value |
|---|---|---|
| 0x1420b6848 | bActorSelfShadowing:Display | 0 |
| 0x1420d01e0 | bAllowShaderCache:Display | 1 |
| 0x1420d0418 | bAssertOnShaderCompileAtRuntime:Display | 1 |
| 0x1420cfa08 | bAutoViewDistance:Display | 0 |
| 0x1420d03d0 | bBreakOnValidationError:Display | 1 |
| 0x1420d03e8 | bBreakOnValidationWarning:Display | 0 |
| 0x1420d6ae8 | bCharacterLighting:Display | 1 |
| 0x1420b5828 | bCompensateUnstableFrameTime:Display | 1 |
| 0x1420d9678 | bCompileOnRender:Display | 1 |
| 0x1420d73a8 | bCreateShadowRenderTarget:Display | 0 |
| 0x1420d8938 | bDeactivateAOOnSnow:Display | 1 |
| 0x1420d94c8 | bDirShadowMapFullViewPort:Display | 1 |
| 0x1420d67f0 | bDisableHighTreeShadow:Display | 1 |
| 0x1420d94f8 | bDisableShadowJumps:Display | 1 |
| 0x1420d72e0 | bDisableZPrepassOutput:Display | 0 |
| 0x1420d69f8 | bDo30VFog:Display | 1 |
| 0x1420d8a10 | bDOFApplyCenterWeight:Display | 1 |
| 0x1420d8f00 | bDOFBilateralBlur:Display | 1 |
| 0x1420d6a40 | bDoTestHDR:Display | 0 |
| 0x1420d8780 | bDownSampleNormalSSR:Display | 1 |
| 0x1420b73c0 | bDynamicDOF:Display | 1 |
| 0x1420b5870 | bEnableAutoDynamicResolution:Display | 0 |
| 0x1420d8688 | bEnableDownsampleComputeShader:Display | 1 |
| 0x1420d72c8 | bEnableFrontToBackPrepass:Display | 0 |
| 0x14207b980 | bEnableLandFade:Display | 1 |
| 0x1420d8d58 | bEnableParallaxOcclusion:Display | 0 |
| 0x1420d8d88 | bEnableProjecteUVDiffuseNormalsOnCubemap:Display | 0 |
| 0x1420d8da0 | bEnableSnowMask:Display | 1 |
| 0x1420d8e30 | bEnableSnowRimLighting:Display | 1 |
| 0x1420d6cc8 | bEnableStippleFade:Display | 1 |
| 0x1420d8eb8 | bEnableVolumetricLighting:Display | 0 |
| 0x1420d6a10 | bImageSpaceEffects:Display | 1 |
| 0x1420d8b30 | bIndDownscaled:Display | 0 |
| 0x1420d8b48 | bIndNormalMap:Display | 1 |
| 0x1420b6140 | bLoadMarkers:Display | 1 |
| 0x1420d01f8 | bLockFramerate:Display | 1 |
| 0x1420d6cb0 | bLodZPrepass:Display | 1 |
| 0x1420b7640 | bLowHealthIModEnabled:Display | 1 |
| 0x1420d6d58 | bOutputMissingTexture:Display | 1 |
| 0x1420d8738 | bProjectileOnReflection:Display | 0 |
| 0x1420d8ab8 | bSAO_CS_Downscaled:Display | 0 |
| 0x1420d8860 | bSAOApplyFog:Display | 1 |
| 0x1420d8830 | bSAODownscaled:Display | 0 |
| 0x1420d8848 | bSAONormalMap:Display | 1 |
| 0x1420d6a70 | bShadowsOnGrass:Display | 1 |
| 0x1420b6128 | bShowMarkers:Display | 0 |
| 0x1420b60c8 | bShowMenuTextureUse:Display | 1 |
| 0x1420d9660 | bSimpleLighting:Display | 0 |
| 0x1420d8890 | bSparklesOnly:Display | 0 |
| 0x1420d0358 | bStaticMenuBackground:Display | 1 |
| 0x1420d04d8 | bSynchronizeDynamicWidthAndHeight:Display | 0 |
| 0x1420d8cc8 | bTAAWater:Display | 0 |
| 0x1420d73c0 | bUse16BitsDepthTarget:Display | 1 |
| 0x1420d03b8 | bUseDeviceDebug:Display | 0 |
| 0x1420d7dc0 | bUseFilmicCurve:Display | 0 |
| 0x1420d7da8 | bUseMultipleLuminanceReferences:Display | 1 |
| 0x1420d8968 | bUsePrecomputedNoise:Display | 0 |
| 0x1420b60e0 | bUseSunbeams:Display | 0 |
| 0x1420d0400 | bValidateRenderTargets:Display | 1 |
| 0x1420d7120 | bVolumetricLightingDisableInterior:Display | 1 |
| 0x1420d71f8 | bVolumetricLightingEnableTemporalAccumulation:Display | 1 |
| 0x1420d7108 | bVolumetricLightingUpdateWeather:Display | 1 |
| 0x1420d8750 | fAlphaWeight:Display | 1.0 |
| 0x1420d6b48 | fCharacterLightLumMax:Display | 0.75 |
| 0x1420d6b30 | fCharacterLightLumScale:Display | 2.0 |
| 0x1420d6b00 | fCharacterLightPrimaryLightIntensity:Display | 0.75 |
| 0x1420d6b18 | fCharacterLightSecondaryLightIntensity:Display | 0.3 |
| 0x1420d8768 | fClampScale:Display | 0.4 |
| 0x1420d7d60 | fConstHDRAdaptTimerForMenu:Display | 0.3 |
| 0x1420b7438 | fDDOFAngleThreshold:Display | 2.0 |
| 0x1420b7408 | fDDOFFocusCenterweightExt:Display | 1.6 |
| 0x1420b7420 | fDDOFFocusCenterweightInt:Display | 1.0 |
| 0x1420b73d8 | fDDOFFocusDelay:Display | 500.0 |
| 0x1420b73f0 | fDDOFFocusDuration:Display | 1000.0 |
| 0x1420b7450 | fDDOFPositionThreshold:Display | 5.0 |
| 0x142079280 | fDecalLifetime:Display | 30.0 |
| 0x142079310 | fDecalLOD0:Display | 800.0 |
| 0x1420d04a8 | fDecreaseDRMilliseconds:Display | 32.0 |
| 0x1420cf9f0 | fDefault1stPersonFOV:Display | 80.0 |
| 0x1420d6b80 | fDefaultFOV:Display | 80.0 |
| 0x1420cf9d8 | fDefaultWorldFOV:Display | 80.0 |
| 0x1420d8a28 | fDOFCenterWeight:Display | 0.6 |
| 0x1420d8a40 | fDOFMaxDepthParticipation:Display | 50000.0 |
| 0x1420d04f0 | fDRClampOffset:Display | 0.002 |
| 0x1420d0508 | fDRClampOffsetNeo:Display | 0.0005 |
| 0x1420bc8f0 | fDynamicDOFBlurMultiplierMax:Display | 1.0 |
| 0x1420bc8d8 | fDynamicDOFBlurMultiplierMin:Display | 0.0 |
| 0x1420d8f90 | fDynamicDOFFarBlur:Display | 0.7 |
| 0x1420d8f30 | fDynamicDOFFarDist:Display | 1000.0 |
| 0x1420d8f60 | fDynamicDOFFarRange:Display | 10000.0 |
| 0x1420d8f78 | fDynamicDOFNearBlur:Display | 1.0 |
| 0x1420d8f18 | fDynamicDOFNearDist:Display | 100.0 |
| 0x1420d8f48 | fDynamicDOFNearRange:Display | 100.0 |
| 0x1420d9160 | fExponentialShadowMapScale:Display | 10.0 |
| 0x1420d7df0 | fFilmicWhiteScale:Display | 1.4 |
| 0x1420d8fe0 | fFilteringAlphaThreshold:Display | 0.01 |
| 0x1420d8fc8 | fFilteringWaterDepthThreshold:Display | 0.005 |
| 0x1420d9468 | fFirstSliceDistance:Display | 1250.0 |
| 0x1420bc800 | fGammaMax:Display | 1.4 |
| 0x1420bc7e8 | fGammaMin:Display | 0.6 |
| 0x1420d7d00 | fGlobalBloomThresholdBoost:Display | 0.0 |
| 0x1420d7628 | fGlobalBrightnessBoost:Display | 0.0 |
| 0x1420d7cd0 | fGlobalContrastBoost:Display | 0.0 |
| 0x1420d7d78 | fGlobalEyeAdaptSpeedScale:Display | 2.0 |
| 0x1420d7d90 | fGlobalEyeAdaptStrengthScale:Display | 0.4 |
| 0x1420d7d18 | fGlobalMapBloomThresholdBoost:Display | 0.25 |
| 0x1420d7d48 | fGlobalMapBrightnessBoost:Display | 0.25 |
| 0x1420d7d30 | fGlobalMapContrastBoost:Display | -0.3 |
| 0x1420d7ce8 | fGlobalSaturationBoost:Display | 0.0 |
| 0x1420d8640 | fIBLFAnamorphicsIntensity:Display | 0.1 |
| 0x1420d8658 | fIBLFAnamorphicsIntensityFar:Display | 1.0 |
| 0x1420d8610 | fIBLFBloomIntensity:Display | 0.0 |
| 0x1420d8580 | fIBLFChannelsDistortionBlue:Display | -2.0 |
| 0x1420d8568 | fIBLFChannelsDistortionGreen:Display | 0.0 |
| 0x1420d8550 | fIBLFChannelsDistortionRed:Display | 2.0 |
| 0x1420d8508 | fIBLFFlaresDispersal:Display | 0.3 |
| 0x1420d8670 | fIBLFGlobalIntensity:Display | 0.7 |
| 0x1420d8598 | fIBLFHaloFetch:Display | 0.5 |
| 0x1420d85b0 | fIBLFHaloWidthPow:Display | 3.0 |
| 0x1420d8538 | fIBLFLightsBurn:Display | 1.0 |
| 0x1420d8520 | fIBLFLightsRangeDownshift:Display | 1.0 |
| 0x1420d04c0 | fIncreaseDRMilliseconds:Display | 30.0 |
| 0x1420d8b18 | fIndBias:Display | 2.5 |
| 0x1420d8ae8 | fIndIntensity:Display | 50.0 |
| 0x1420d8b00 | fIndRadius:Display | 100.0 |
| 0x1420d6aa0 | fLightLODDefaultStartFade:Display | 1000.0 |
| 0x1420d6ad0 | fLightLODRange:Display | 500.0 |
| 0x142079628 | fLinePrimitiveWidth:Display | 8.0 |
| 0x1420d0448 | fLowestDynamicHeightRatio:Display | 1.0 |
| 0x1420d0430 | fLowestDynamicWidthRatio:Display | 0.7 |
| 0x1420b7658 | fLowHealthIModInterval:Display | 2.0 |
| 0x1420b7688 | fLowHealthIModStrengthMax:Display | 1.5 |
| 0x1420b7670 | fLowHealthIModStrengthMin:Display | 0.8 |
| 0x1420d9190 | fMaxFocusShadowMapDistance:Display | 450.0 |
| 0x1420d67d8 | fMaxHeightShadowCastingTrees:Display | 5000.0 |
| 0x1420d6758 | fMeshLODFadeTime:Display | 1.0 |
| 0x1420d6a58 | fMipBias:Display | 0.0 |
| 0x1420cf9c0 | fNear1stPersonDistance:Display | 5.0 |
| 0x1420cf9a8 | fNearDistance:Display | 15.0 |
| 0x1420cf978 | fNoLODFarDistanceMax:Display | 10240.0 |
| 0x1420cf960 | fNoLODFarDistanceMin:Display | 100.0 |
| 0x1420cf990 | fNoLODFarDistancePct:Display | 1.0 |
| 0x1420d8908 | fNonSpecularSparklesIntensity:Display | 0.4 |
| 0x1420d9148 | fPoissonRadiusScale:Display | 4.0 |
| 0x1420d0478 | fRatioDecreasePerSeconds:Display | 0.07 |
| 0x1420d0460 | fRatioIncreasePerSeconds:Display | 0.03 |
| 0x1420d8708 | fReflectionMarchingRadius:Display | 0.4 |
| 0x1420d8720 | fReflectionRayThickness:Display | 0.001 |
| 0x1420d86c0 | fReflectionsIntensityScale:Display | 0.8 |
| 0x1420d8d40 | fReflectionsMotionVectorScale:Display | 1.0 |
| 0x1420d7dd8 | fReinhardWhiteScale:Display | 1.1 |
| 0x1420d8aa0 | fSAO_CS_Bias:Display | 2.5 |
| 0x1420d8a70 | fSAO_CS_Intensity:Display | 10.0 |
| 0x1420d8a88 | fSAO_CS_Radius:Display | 250.0 |
| 0x1420d87e8 | fSAOBias:Display | 2.5 |
| 0x1420d8800 | fSAOExpFactor:Display | 0.11 |
| 0x1420d87b8 | fSAOIntensity:Display | 15.0 |
| 0x1420d87d0 | fSAORadius:Display | 250.0 |
| 0x1420d8818 | fSAOValueDiffFactor:Display | 0.3 |
| 0x1420b60f8 | fScopeScissorAmount:Display | 0.3 |
| 0x1420d9078 | fShadowBiasScale:Display | 1.0 |
| 0x1420d6d40 | fShadowClampValue:Display | 0.3 |
| 0x1420d9510 | fShadowDirectionalBiasScale:Display | 0.3 |
| 0x1420d8980 | fShadowSparkleIntensity:Display | 0.25 |
| 0x1420d8e00 | fSnowGeometrySpecPower:Display | 3.0 |
| 0x1420d8e18 | fSnowNormalSpecPower:Display | 2.0 |
| 0x1420d8de8 | fSnowRimLightIntensity:Display | 0.3 |
| 0x1420d89e0 | fSnowSparklesColorB:Display | 1.0 |
| 0x1420d89c8 | fSnowSparklesColorG:Display | 1.0 |
| 0x1420d89b0 | fSnowSparklesColorR:Display | 1.0 |
| 0x1420d8b90 | fSnowSSSColorB:Display | 0.08 |
| 0x1420d8b78 | fSnowSSSColorG:Display | 0.0 |
| 0x1420d8b60 | fSnowSSSColorR:Display | 0.0 |
| 0x1420d8bc0 | fSnowSSSDepthDiff:Display | 0.5 |
| 0x1420d8ba8 | fSnowSSSStrength:Display | 50.0 |
| 0x1420d88c0 | fSparklesDensity:Display | 0.85 |
| 0x1420d88a8 | fSparklesIntensity:Display | 1.0 |
| 0x1420d8950 | fSparklesMaxDistance:Display | 1000.0 |
| 0x1420d88f0 | fSparklesSize:Display | 6.0 |
| 0x1420d88d8 | fSparklesSpecularPower:Display | 2.0 |
| 0x1420d86d8 | fSpecMaskBegin:Display | 0.1 |
| 0x1420d86f0 | fSpecMaskSpan:Display | 0.0 |
| 0x1420d8920 | fSpecularSparklesIntensity:Display | 1.0 |
| 0x1420d94e0 | fSplitOverlap:Display | 100.0 |
| 0x1420d9498 | fSunShadowUpdateTime:Display | 1.0 |
| 0x1420d94b0 | fSunStaticTimeUpdateScale:Display | 0.1 |
| 0x1420d9480 | fSunUpdateThreshold:Display | 0.5 |
| 0x1420d8cb0 | fTAAEffectThreshold:Display | 0.1 |
| 0x1420d8c68 | fTAAHighFreq:Display | 0.8 |
| 0x1420d8c50 | fTAALowFreq:Display | 0.5 |
| 0x1420d8c98 | fTAAPostOverlay:Display | 0.21 |
| 0x1420d8c80 | fTAAPostSharpen:Display | 0.21 |
| 0x1420d8c38 | fTAASharpen:Display | 1.0 |
| 0x1420d7138 | fVolumetricLightingCustomColorContribution:Display | 0.0 |
| 0x1420d7150 | fVolumetricLightingDensityContribution:Display | 0.3 |
| 0x1420d7168 | fVolumetricLightingDensityScale:Display | 300.0 |
| 0x1420d70d8 | fVolumetricLightingIntensity:Display | 2.0 |
| 0x1420d71b0 | fVolumetricLightingPhaseContribution:Display | 0.83 |
| 0x1420d71c8 | fVolumetricLightingPhaseScattering:Display | 0.85 |
| 0x1420d71e0 | fVolumetricLightingRangeFactor:Display | 40.0 |
| 0x1420d7210 | fVolumetricLightingTemporalAccumulationFactor:Display | 0.75 |
| 0x1420d7198 | fVolumetricLightingWindFallingSpeed:Display | 0.3 |
| 0x1420d7180 | fVolumetricLightingWindSpeedScale:Display | 15.0 |
| 0x1420d8e80 | fWaterSSRBlurAmount:Display | 0.3 |
| 0x1420d8e68 | fWaterSSRIntensity:Display | 1.3 |
| 0x1420d8e98 | fWaterSSRNormalPerturbationScale:Display | 0.05 |
| 0x1420d6d28 | fWindGrassMultiplier:Display | 1.0 |
| 0x1420cfa38 | iAutoViewHiFrameRate:Display | 40 |
| 0x1420cfa20 | iAutoViewLowFrameRate:Display | 20 |
| 0x1420cfa50 | iAutoViewMinDistance:Display | 2000 |
| 0x1420d3098 | iDebugTextLeftRightOffset:Display | 10 |
| 0x1420b60b0 | iDebugTextSubPage:Display | 0 |
| 0x1420d3080 | iDebugTextTopBottomOffset:Display | 20 |
| 0x1420d6cf8 | iEnableShadowCastingFlag:Display | 2 |
| 0x1420d8e48 | iLandscapeMultiNormalTilingFactor:Display | 4 |
| 0x1420d90d8 | iShaderPackageMemoryCap:Display | 409600 |
| 0x1420d8998 | iSnowSparklesColor:Display | 2 |
| 0x1420d8bf0 | iSnowSSSCurrentColor:Display | 2 |
| 0x1420d6a28 | iTrilinearThreshold:Display | 3 |
| 0x1420b5840 | iUnstableFrameTimeHistorySize:Display | 8 |
| 0x1420d70a8 | iVolumetricLightingNoiseTextureDepth:Display | 32 |
| 0x1420d7090 | iVolumetricLightingNoiseTextureHeight:Display | 32 |
| 0x1420d7078 | iVolumetricLightingNoiseTextureWidth:Display | 32 |
| 0x1420d7048 | iVolumetricLightingTextureDepthHigh:Display | 90 |
| 0x1420d6f88 | iVolumetricLightingTextureDepthLow:Display | 50 |
| 0x1420d6fe8 | iVolumetricLightingTextureDepthMedium:Display | 70 |
| 0x1420d7060 | iVolumetricLightingTextureFormatHigh:Display | 1 |
| 0x1420d6fa0 | iVolumetricLightingTextureFormatLow:Display | 0 |
| 0x1420d7000 | iVolumetricLightingTextureFormatMedium:Display | 1 |
| 0x1420d7030 | iVolumetricLightingTextureHeightHigh:Display | 192 |
| 0x1420d6f70 | iVolumetricLightingTextureHeightLow:Display | 96 |
| 0x1420d6fd0 | iVolumetricLightingTextureHeightMedium:Display | 128 |
| 0x1420d7018 | iVolumetricLightingTextureWidthHigh:Display | 320 |
| 0x1420d6f58 | iVolumetricLightingTextureWidthLow:Display | 160 |
| 0x1420d6fb8 | iVolumetricLightingTextureWidthMedium:Display | 224 |
| 0x1420b6098 | sDebugText:Display | "VATS" |
| 0x1420b6450 | sScreenShotBaseName:Display | "ScreenShot" |
| 0x1420d85f8 | uIBLFBloomRadius:Display | 2 |
| 0x1420d85c8 | uIBLFBlurRadiusX:Display | 7 |
| 0x1420d85e0 | uIBLFBlurRadiusY:Display | 2 |
| 0x1420d8628 | uIBLFLateralRepeat:Display | 0 |
| 0x1420d84f0 | uIBLFLensesCount:Display | 3 |
| 0x1420d6b60 | uShadowFilterType:Display | 3 |

## Ini settings: [General], [Archive], [Language], [Messages], [Papyrus], [SaveGame] and the rest without a section

The value compiled into `SkyrimSE.exe` for each ini setting: what the game uses when neither `Skyrim.ini` nor `SkyrimPrefs.ini` sets it. `skyrim/ini.zap` keeps the few the port reads; this is the whole table. A setting the game fills at run time holds 0 here (iDifficulty and fAutosaveEveryXMins are two).

Read from the static `SettingT<INISettingCollection>` objects in `.data` (24 bytes: the vtable, the value, the pointer to the name; the vtable's RTTI names the class), found by scanning `.data` for pointers to names and checked against REA's `read_bytes` at 0x1420d9078 (fShadowBiasScale:Display). The address is the object's; the value is decoded by the name's type letter (f float, i int, u unsigned, b bool, s string, r and a 32-bit colors).

| address | setting | value |
|---|---|---|
| 0x1420b5858 | bActivateFromSave:General | 0 |
| 0x1420cf710 | bAllowFileWrite:MESSAGES | 0 |
| 0x1420b5468 | bAllowProfileTransfer:SaveGame | 0 |
| 0x1420b5480 | bAllowScriptedAutosave:SaveGame | 1 |
| 0x1420b5498 | bAllowScriptedForceSave:SaveGame | 1 |
| 0x1420b62a8 | bAllowYesToAll:MESSAGES | 1 |
| 0x1420b58b8 | bAlwaysActive:General | 0 |
| 0x142078038 | bAnimateDoorPhysics:General | 0 |
| 0x1420b5918 | bAssertsWithoutDebugger:Messages | 0 |
| 0x1420bc9c0 | bAutoSaveOnUserStale:SaveGame | 1 |
| 0x14207b790 | bBackgroundCellLoads:BackgroundLoad | 1 |
| 0x1420b6860 | bBackgroundLoadLipFiles:BackgroundLoad | 1 |
| 0x142078f20 | bBackgroundLoadVMData:General | 0 |
| 0x1420b6248 | bBlockMessageBoxes:MESSAGES | 0 |
| 0x1420b7488 | bBorderRegionsEnabled:General | 1 |
| 0x14207af30 | bCalculateArmorMeshAndTextureFileCounts:General | 1 |
| 0x1420b5ba0 | bChangeTimeMultSlowly:General | 1 |
| 0x14207be08 | bCheckCellOffsetsOnInit:General | 0 |
| 0x142077988 | bCheckPurgedTextureList:General | 0 |
| 0x1420b5ff0 | bCheckRuntimeCollisions:Archive | 0 |
| 0x1420b5688 | bCompressBuffer:SaveGame | 0 |
| 0x1420b54b0 | bConvertNonUtilitySaves:SaveGame | 0 |
| 0x1420b54c8 | bCopySaveGameToHostOrMemStick:SaveGame | 0 |
| 0x1420b58e8 | bCRTMemoryChecks:General | 0 |
| 0x1420cf7a0 | bCullingJobEnablePlaneOptimization:General | 0 |
| 0x1420b07a0 | bDebugFaceGenCriticalSection:Debug | 0 |
| 0x1420b0788 | bDebugFaceGenMultithreading:Debug | 0 |
| 0x1420b7560 | bDebugFlyingMountLeash:Debug | 0 |
| 0x1420b8aa0 | bDebugSpectatorThreats:General | 0 |
| 0x14207ba98 | bDefaultCOCPlacement:General | 0 |
| 0x1420b6a10 | bDisableAllGore:General | 0 |
| 0x1420b6278 | bDisableAssertQueuing:MESSAGES | 1 |
| 0x1420b54e0 | bDisableAutoSave:SaveGame | 0 |
| 0x142077ce8 | bDisableDuplicateReferenceCheck:General | 1 |
| 0x14209c9b8 | bDisableGearedUp:General | 1 |
| 0x1420b6290 | bDisableWarningWindows:General | 0 |
| 0x1420b5d08 | bDisplayBoundingVolumes:General | 0 |
| 0x1420b54f8 | bDisplayMissingContentDialogue:SaveGame | 1 |
| 0x1420b5d20 | bEnableBoundingVolumeOcclusion:General | 1 |
| 0x1420b5900 | bEnableFileCaching:General | 0 |
| 0x1420b6170 | bEnableFriendHenchman:General | 0 |
| 0x142079f20 | bEnableLipLookup | 1 |
| 0x1420bca08 | bEnableLogging:Papyrus | 0 |
| 0x1420bcaf8 | bEnableProfiling:Papyrus | 0 |
| 0x1420bcbc0 | bEnableTrace:Papyrus | 0 |
| 0x14207bdd8 | bExternalLODDataFiles:General | 1 |
| 0x1420b07e0 | bFacegenDisableMorphs:General | 0 |
| 0x1420b07b8 | bFaceGenWarnings:MESSAGES | 0 |
| 0x142077d60 | bFileCheckModelCollision:TestAllCells | 0 |
| 0x14207bca8 | bFileControllerOnRoot:TestAllCells | 1 |
| 0x142077d78 | bFileGoneMessage:TestAllCells | 1 |
| 0x142077d90 | bFileNeededMessage:TestAllCells | 1 |
| 0x142077df0 | bFileShowIcons:TestAllCells | 1 |
| 0x142077e08 | bFileShowTextures:TestAllCells | 1 |
| 0x142077dd8 | bFileSkipIconChecks:TestAllCells | 0 |
| 0x142077d48 | bFileSkipModelChecks:TestAllCells | 0 |
| 0x142077da8 | bFileTestLoad:TestAllCells | 0 |
| 0x142077dc0 | bFileUnusedObject:TestAllCells | 0 |
| 0x142078158 | bFixAIPackagesOnLoad:General | 0 |
| 0x1420b7500 | bFlyingMountFastTravelCruiseEnabled:GENERAL | 0 |
| 0x1420ced30 | bForceAsync:Archive | 0 |
| 0x1420a1370 | bHealthRegenFromRacePlayerOnly:General | 1 |
| 0x1420b6068 | bInvalidateOlderFiles:Archive | 1 |
| 0x1420ceaa8 | bJoblistActiveWait:General | 1 |
| 0x1420795a8 | bKeepDLStringBlocksLoaded:General | 0 |
| 0x1420795c0 | bKeepILStringBlocksLoaded:General | 1 |
| 0x142077eb8 | bKeepPluginWhenMerging:General | 0 |
| 0x1420cec88 | bLoadArchiveInMemory:Archive | 0 |
| 0x1420b0728 | bLoadBackgroundFaceGen:BackgroundLoad | 0 |
| 0x1420bcae0 | bLoadDebugInformation:Papyrus | 0 |
| 0x142077fe0 | bLoadEsmInMemory:Archive | 1 |
| 0x142079dc0 | bLoadHelmetsInBackground:BackgroundLoad | 1 |
| 0x1420bb328 | bModManagerMenuEnabled:General | 1 |
| 0x1420b5810 | bNoBreaksForAsserts:Messages | 0 |
| 0x1420b5510 | bOutputSaveGameScreenshot:SaveGame | 1 |
| 0x1420b7ff8 | bParallelAnimUpdate:General | 0 |
| 0x1420b58d0 | bPauseWhenConstrained:General | 1 |
| 0x1420b5df8 | bPreCullActors:General | 1 |
| 0x142077730 | bPreemptivelyUnloadCells:General | 0 |
| 0x1420d3c68 | bPreloadIntroSequence:General | 1 |
| 0x14207bab0 | bPreloadLinkedInteriors:General | 0 |
| 0x14207bb80 | bPrimitivesOn | 0 |
| 0x1420779a0 | bQueueWarnings:General | 0 |
| 0x1420795d8 | bReconstructIDTags:General | 0 |
| 0x1420b5960 | bResetGameAfterStreamingInstall:StreamInstall | 0 |
| 0x1420b8028 | bRunMiddleLowLevelProcess:General | 1 |
| 0x1420b5b70 | bRunVTuneTest:General | 0 |
| 0x1420776b8 | bSelectivePurgeUnusedOnFastTravel:BackgroundLoad | 0 |
| 0x1420b6398 | bShowCheckMemoryOutput:General | 0 |
| 0x1420b77d8 | bShowGunTarget:General | 0 |
| 0x142077790 | bShowLoadingAreaMessage:General | 0 |
| 0x1420cc900 | bShowMissingAudioWarnings:MESSAGES | 1 |
| 0x1420b68a8 | bShowMissingLipWarnings:MESSAGES | 1 |
| 0x1420b62f0 | bSkipInitializationFlows:MESSAGES | 1 |
| 0x1420b62c0 | bSkipProgramFlows:MESSAGES | 1 |
| 0x1420b8010 | bTaskletActorSceneGraphUpdates:General | 1 |
| 0x1420b64a8 | bTaskletCellTransformsUpdate:General | 1 |
| 0x1420b68f0 | bTrackAllDeaths:General | 0 |
| 0x142077b98 | bTrackFileLoading:Archive | 0 |
| 0x1420b58a0 | bUseArchives:Archive | 1 |
| 0x1420b5fc0 | bUseBackgroundFileLoader:BackgroundLoad | 0 |
| 0x142079dd8 | bUseBodyMorphs:General | 1 |
| 0x1420b0710 | bUseEyeEnvMapping:General | 1 |
| 0x1420b06b0 | bUseFaceGenPreprocessedHeads:General | 1 |
| 0x1420b5de0 | bUseHardDriveCache:General | 0 |
| 0x1420b6a58 | bUseMovementBlockedPackage:General | 0 |
| 0x14207ba68 | bUseMultibounds:General | 1 |
| 0x1420b06f8 | bUseMultiThreadedFaceGen:BackgroundLoad | 1 |
| 0x1420779b8 | bUseMultiThreadedTrees:BackgroundLoad | 1 |
| 0x142079030 | bUseOptimizedTextureLoading:General | 1 |
| 0x1420b5408 | bUseSaveGameHistory:SaveGame | 0 |
| 0x1420b5be8 | bUseThreadedMorpher:General | 0 |
| 0x1420b5bd0 | bUseThreadedParticleSystem:General | 0 |
| 0x1420b5bb8 | bUseThreadedTempEffects:General | 1 |
| 0x1420b3770 | bUseWaterHDR | 1 |
| 0x1420b6260 | bUseWindowsMessageBox:MESSAGES | 0 |
| 0x1420d90f0 | bWarnOnMaterialCollisions:General | 0 |
| 0x142079018 | bWarnOnMissingFileEntry:General | 0 |
| 0x142077bb0 | bWriteTACOutputToFile:Debug | 0 |
| 0x1420b5888 | fArchiveInitBufferMB:Papyrus | 8.0 |
| 0x14207b0c0 | fAutoDoorFadeSecs:General | 0.5 |
| 0x1420b7138 | fBetaDeferredKillTimer:General | 15.0 |
| 0x1420cf628 | fBSTaskTime:General | 2.0 |
| 0x1420b48d0 | fCloakEffectUpdateInterval:General | 0.5 |
| 0x1420b7080 | fDragonLandingForPlayerNavMeshSize:GENERAL | 250.0 |
| 0x1420b7068 | fDragonLandingForPlayerSearchDist:GENERAL | 3000.0 |
| 0x1420b76b8 | fEncumberedReminderTimer:General | 30.0 |
| 0x1420bca68 | fExtraTaskletBudgetMS:Papyrus | 1.2 |
| 0x1420d9178 | fFadingFracStart | 0.25 |
| 0x1420bc528 | fFastTravelFadeSecs:General | 0.5 |
| 0x14207ba80 | fFlickeringLightDistance:General | 1024.0 |
| 0x1420b6e78 | fFlyingMountDismountOffset:GENERAL | 30.0 |
| 0x1420b75c0 | fFlyingMountFastTravelArrivalHeight:GENERAL | 1000.0 |
| 0x1420b75d8 | fFlyingMountFastTravelDragonSpeed:GENERAL | 7000.0 |
| 0x1420b75a8 | fFlyingMountLandingRequestTimer:GENERAL | 3.0 |
| 0x1420b7590 | fFlyingMountSlowestSpeedMult:GENERAL | 0.25 |
| 0x1420b75f0 | fFlyingMountTutorialMessageDelay:GENERAL | 15.0 |
| 0x1420bb268 | fJoyConStrapInstructionDelay:General | 5.0 |
| 0x1420bcce8 | fKinectMaxAllyTradeDistance:Kinect | 60000.0 |
| 0x1420bcd30 | fKinectMinConfidence:Kinect | 0.3 |
| 0x1420bcd18 | fKinectMinReportConfidence:Kinect | 0.01 |
| 0x1420bcd48 | fKinectMinReportShoutConfidence:Kinect | 0.005 |
| 0x1420bcd00 | fKinectMinRuleConfidence:Kinect | 0.25 |
| 0x1420bcd60 | fKinectMinShoutConfidence:Kinect | 0.0075 |
| 0x1420bc6f8 | fLoadGameFadeSecs:General | 1.0 |
| 0x1420b9de8 | fLowPerfCombatantVoiceDistance | 1000.0 |
| 0x1420bc540 | fMapWorldTargetTransitionTime | 0.5 |
| 0x14207b0f0 | fNormalDoorFadeSecs:General | 0.4 |
| 0x14207b0d8 | fNormalDoorFadeWait:General | 0.01 |
| 0x1420b7518 | fPlayerFlyingMountBaseTargetSpeed:GENERAL | 700.0 |
| 0x1420b7530 | fPlayerFlyingMountFastBaseTargetSpeed:GENERAL | 1400.0 |
| 0x1420b7548 | fPlayerFlyingMountNothingLoadingMult:GENERAL | 10.0 |
| 0x1420b18a8 | fPlayerFlyingMountTravelMaxHeight:GENERAL | 400.0 |
| 0x1420b1890 | fPlayerFlyingMountTravelMinHeight:GENERAL | 200.0 |
| 0x1420bca80 | fPostLoadUpdateTimeMS:Papyrus | 2000.0 |
| 0x1420b7fe0 | fProcessListsUpdateHighFrameRate:General | 30.0 |
| 0x1420b7fc8 | fProcessListsUpdateLowFrameRate:General | 10.0 |
| 0x1420b7f98 | fProcessListsUpdateTimeMax:General | 5.0 |
| 0x1420b7fb0 | fProcessListsUpdateTimeMin:General | 0.5 |
| 0x14207e518 | fQuestScriptDelayTime:MAIN | 5.0 |
| 0x1420d8bd8 | fSnowSSSDarkColorIntensity | 0.1 |
| 0x1420b3b88 | fStoryTellerQuestFindTime:General | 2.0 |
| 0x1420bca50 | fUpdateBudgetMS:Papyrus | 1.2 |
| 0x1420b5528 | iAutoSaveCount:SaveGame | 3 |
| 0x1420b69b0 | iDetectionHighNumPicks | 40 |
| 0x1420b0ed8 | iEnumRefsAllowedPerFrame:General | 1 |
| 0x1420b6080 | iFileLogging:MESSAGES | 0 |
| 0x1420b7578 | iFlyingMountSlowestQueuedRefCount:GENERAL | 250 |
| 0x1420b5b88 | iFPSClamp:General | 0 |
| 0x1420d1808 | iHWThread1:General | 4 |
| 0x1420d1820 | iHWThread2:General | 4 |
| 0x1420d1838 | iHWThread3:General | 4 |
| 0x1420d1850 | iHWThread4:General | 5 |
| 0x1420d1868 | iHWThread5:General | 5 |
| 0x1420d1880 | iHWThread6:General | 5 |
| 0x1420d3c98 | iIntroSequencePriority:General | 3 |
| 0x142077c58 | iLargeIntRefCount:General | 1000 |
| 0x1420b7f80 | iLowProcessingMilliseconds:General | 2 |
| 0x1420bcac8 | iMaxAllocatedMemoryBytes:Papyrus | 153600 |
| 0x1420b57f8 | iMaxJobThreads:General | 32 |
| 0x1420bcab0 | iMaxMemoryPageSize:Papyrus | 512 |
| 0x1420b74d0 | iMaxQuestObjectives | 3000 |
| 0x1420bca98 | iMinMemoryPageSize:Papyrus | 128 |
| 0x1420b6488 | iNumBitsForFullySeen:General | 248 |
| 0x142077778 | iNumHWThreads:General | 4 |
| 0x1420cf640 | iPostProcessMilliseconds:BackgroundLoad | 2 |
| 0x1420cf670 | iPostProcessMillisecondsEditor:BackgroundLoad | 50 |
| 0x1420cf658 | iPostProcessMillisecondsLoadingQueuedPriority:BackgroundLoad | 20 |
| 0x1420cf688 | iPostProcessTaskWarningMilliseconds:BackgroundLoad | 20 |
| 0x1420d3c80 | iPreloadSizeLimit:General | 26214400 |
| 0x1420b6008 | iRetainDirectoryStringTable:Archive | 1 |
| 0x1420b6038 | iRetainFilenameOffsetTable:Archive | 1 |
| 0x1420b6020 | iRetainFilenameStringTable:Archive | 1 |
| 0x1420b5540 | iSaveGameBackupCount:SaveGame | 1 |
| 0x1420d89f8 | iSnowNoiseTextureSize | 512 |
| 0x1420b0ef0 | iUpdateDetectionsAllowedPerFrame:General | 100 |
| 0x1420b5978 | sArchiveList:Archive | "Skyrim - Textures.bsa, Skyrim - Meshes.bsa, Skyrim - Voices.bsa" |
| 0x1420ceca0 | sArchiveToLoadInMemoryList:Archive | "Skyrim - Animations.bsa, Skyrim - Interface.bsa, Skyrim - Misc.bsa, Skyrim - Sounds.bsa" |
| 0x1420bb298 | sCharGenQuest:General | "0003372b" |
| 0x1420ccd10 | sControlsDefinitionFile | "Interface/Controls/PC/ControlMap.txt" |
| 0x1420ce8a0 | sControlsDefinitionFile | "Interface/Controls/PC/GamepadOrbis.txt" |
| 0x1420ccd28 | sControlsRemapFile | "ControlMap_Custom.txt" |
| 0x1420b5fa8 | sCopyProtectionMessage2:CopyProtectionStrings | "Insert the Skyrim Disc." |
| 0x1420b5f78 | sCopyProtectionMessage:CopyProtectionStrings | "Unable to find a CD-ROM/DVD drive on this computer." |
| 0x1420b5f90 | sCopyProtectionTitle2:CopyProtectionStrings | "Skyrim Disc Not Found" |
| 0x1420b5f60 | sCopyProtectionTitle:CopyProtectionStrings | "CD-ROM Drive Not Found" |
| 0x1420b62d8 | sDisabledProgramFlowContexts:MESSAGES | "" |
| 0x142077ff8 | sEsmToLoadInMemoryList:Archive | "Skyrim.esm, Update.esm, Dawnguard.esm, HearthFires.esm, Dragonborn.esm" |
| 0x1420b5930 | sEssentialFileCacheList:General | "" |
| 0x142077a00 | sFailureMessage:LANGUAGE | "Something is broken" |
| 0x14209cd50 | sFileTypeGame:Voice | "wav" |
| 0x14209cd80 | sFileTypeLip:Voice | "lip" |
| 0x14209cd98 | sFileTypeLTF:Voice | "ltf" |
| 0x14209cd68 | sFileTypeSource:Voice | "wav" |
| 0x1420d2fd8 | sFontConfigFile:Fonts | "Interface\\FontConfig.txt" |
| 0x1420ba9c0 | sGameCode:OAuth | "" |
| 0x1420ccd68 | sGamepadDefinitionFile | "Interface/Controls/PC/Gamepad.txt" |
| 0x1420bb310 | sGamerIconTextureName:General | "BGSUserIcon" |
| 0x142077d30 | sGeneralMasterMismatchWarning:GeneralWarnings | "One or more plugins could not find the correct versions of the master files they depend on. Errors may occur during load or game play. Check the \"Warnings.txt\" file for more information.\r\n" |
| 0x1420b5750 | sIntroMovie:General | "" |
| 0x1420b5720 | sIntroSequence:General | "BGS_Logo.bik" |
| 0x1420b6050 | sInvalidationFile:Archive | "ArchiveInvalidation.txt" |
| 0x1420ce568 | sKeyboardDefinitionFile | "Interface/Controls/PC/Keyboard_" |
| 0x1420779e8 | sLanguage:General | "ENGLISH" |
| 0x142077cd0 | sLocalCharacterDataPath:General | "Saves\\Character\\" |
| 0x142077ca0 | sLocalMasterPath:General | "Data\\" |
| 0x142077cb8 | sLocalSavePath:General | "Saves\\" |
| 0x1420b5738 | sMainMenuMovieIntro:General | "" |
| 0x1420bb2b0 | sMainMenuMusic:General | "\\Data\\Music\\Special\\MUS_MainTheme.xwm" |
| 0x142077d18 | sMasterMismatchWarning:GeneralWarnings | "One of the files that \"%s\" is dependent on has changed since the last save." |
| 0x1420ce590 | sMouseDefinitionFile | "Interface/Controls/PC/Mouse.txt" |
| 0x1420b59a8 | sResourceArchiveList2:Archive | "" |
| 0x1420b5990 | sResourceArchiveList:Archive | "Skyrim - Misc.bsa, Skyrim - Shaders.bsa, Skyrim - Textures.bsa, Skyrim - Meshes.bsa, Skyrim - Animations.bsa, Skyrim - Voices.bsa, Skyrim - VoicesExtra.bsa, Skyrim - Interface.bsa, Skyrim - Sounds.bsa, MarketplaceTextures.bsa, Skyrim - Patch.bsa" |
| 0x1420b59c0 | sResourceArchiveListBeta:Archive | "" |
| 0x1420b59f0 | sResourceArchiveRetainFileNameList:Archive | "" |
| 0x1420b59d8 | sResourcePrefixList:Archive | "TEXTURES\\, MESHES\\, FACEGEN\\, INTERFACE\\ , MUSIC\\, SOUND\\, SCRIPTS\\, MAXHEIGHTS\\, VIS\\, GRASS\\, STRINGS\\, SHADERSFX\\" |
| 0x1420b5558 | sSaveGameGameVersionOutdated:SaveGame | "This save game was created on a later version of Skyrim. Please download any updates." |
| 0x1420b5570 | sSaveGameSafeMarkerID:SaveGame | "1DC0A" |
| 0x1420b53f0 | sSaveGameScreenshotName | "BGSSaveLoadHeader_Screenshot" |
| 0x1420b5af8 | sStartingCell:General | "" |
| 0x1420b5b28 | sStartingCellX:General | "" |
| 0x1420b5b40 | sStartingCellY:General | "" |
| 0x1420b5b58 | sStartingConsoleCommand:General | "" |
| 0x1420b5b10 | sStartingWorld:General | "" |
| 0x142077a30 | sSysUtil_AutoSaveWarning:LANGUAGE | "No Default string.  Must be loaded from INIFile" |
| 0x142077b38 | sSysUtil_AwardsConfiguring:LANGUAGE | "No Default string.  Must be loaded from INIFile" |
| 0x142077b08 | sSysUtil_AwardsInstalling:LANGUAGE | "No Default string.  Must be loaded from INIFile" |
| 0x142077af0 | sSysUtil_AwardsLoading:LANGUAGE | "No Default string.  Must be loaded from INIFile" |
| 0x142077b20 | sSysUtil_AwardsReinstalling:LANGUAGE | "No Default string.  Must be loaded from INIFile" |
| 0x142077b50 | sSysUtil_AwardsUpdating:LANGUAGE | "No Default string.  Must be loaded from INIFile" |
| 0x142077ad8 | sSysUtil_DirtyDisc:LANGUAGE | "No Default string.  Must be loaded from INIFile" |
| 0x142077ac0 | sSysUtil_DiscEject:LANGUAGE | "No Default string.  Must be loaded from INIFile" |
| 0x142077b80 | sSysUtil_GameContentInstalling:LANGUAGE | "No Default string.  Must be loaded from INIFile" |
| 0x142077a60 | sSysUtil_GameDataCorrupt:LANGUAGE | "No Default string.  Must be loaded from INIFile" |
| 0x142077a48 | sSysUtil_GameDataInsufficientSpace:LANGUAGE | "No Default string.  Must be loaded from INIFile" |
| 0x142077b68 | sSysUtil_NPDRMInstalling:LANGUAGE | "No Default string.  Must be loaded from INIFile" |
| 0x142077a18 | sSysUtil_Retry:LANGUAGE | "No Default string.  Must be loaded from INIFile" |
| 0x142077a78 | sSysUtil_SaveDataCreateNew:LANGUAGE | "No Default string.  Must be loaded from INIFile" |
| 0x142077a90 | sSysUtil_SaveDataInsufficientSpace:LANGUAGE | "No Default string.  Must be loaded from INIFile" |
| 0x142077aa8 | sSysUtil_SaveDataOwnershipWarning:LANGUAGE | "No Default string.  Must be loaded from INIFile" |
| 0x1420b5ae0 | sTestFile10:General | "" |
| 0x1420b5a08 | sTestFile1:General | "Skyrim.esm" |
| 0x1420b5a20 | sTestFile2:General | "" |
| 0x1420b5a38 | sTestFile3:General | "" |
| 0x1420b5a50 | sTestFile4:General | "" |
| 0x1420b5a68 | sTestFile5:General | "" |
| 0x1420b5a80 | sTestFile6:General | "" |
| 0x1420b5a98 | sTestFile7:General | "" |
| 0x1420b5ab0 | sTestFile8:General | "" |
| 0x1420b5ac8 | sTestFile9:General | "" |
| 0x1420b5948 | sUnessentialFileCacheList:General | "" |
| 0x142079ea8 | uGridsToLoad:General | 5 |
| 0x14207b638 | uLMaxCellDemotePerFrame:General | 1 |
| 0x1420bb2e0 | uMainMenuMusicAttnmB:General | 1200 |
| 0x1420bb2c8 | uMainMenuMusicFadeTimeMS:General | 1500 |
| 0x1420bb2f8 | uModMenuMusicAttnmB:General | 2000 |
| 0x1420bccb8 | uTraceStatusOfQuest:Papyrus | 0 |

## Ini settings: [Interface]

The value compiled into `SkyrimSE.exe` for each ini setting: what the game uses when neither `Skyrim.ini` nor `SkyrimPrefs.ini` sets it. `skyrim/ini.zap` keeps the few the port reads; this is the whole table. A setting the game fills at run time holds 0 here (iDifficulty and fAutosaveEveryXMins are two).

Read from the static `SettingT<INISettingCollection>` objects in `.data` (24 bytes: the vtable, the value, the pointer to the name; the vtable's RTTI names the class), found by scanning `.data` for pointers to names and checked against REA's `read_bytes` at 0x1420d9078 (fShadowBiasScale:Display). The address is the object's; the value is decoded by the name's type letter (f float, i int, u unsigned, b bool, s string, r and a 32-bit colors).

| address | setting | value |
|---|---|---|
| 0x1420bac68 | bShowCrosshair:Interface | 1 |
| 0x1420bc2c0 | bShowHUDMessages:Interface | 1 |
| 0x1420bad10 | bShowInventory3D:Interface | 1 |
| 0x1420bb9d0 | bShowSubtitleSpeakerName:Interface | 1 |
| 0x1420bba40 | bShowTutorials:Interface | 1 |
| 0x1420baf20 | bUseAllNonDefaultLoadScreensFirst:Interface | 0 |
| 0x14209e490 | bUseFuzzyPicking:Interface | 1 |
| 0x1420bb410 | bUserClosesLoadingMenu:Interface | 0 |
| 0x1420d3110 | bWriteTranslationFile:Interface | 0 |
| 0x14209e4c0 | fActivatePickLength:Interface | 180.0 |
| 0x14209e4a8 | fActivatePickRadius:Interface | 16.0 |
| 0x1420ba810 | fBookDistance:Interface | 110.0 |
| 0x1420bbd80 | fBookLight2DiffuseColorB:Interface | 0.83 |
| 0x1420bbd68 | fBookLight2DiffuseColorG:Interface | 0.95 |
| 0x1420bbd50 | fBookLight2DiffuseColorR:Interface | 0.98 |
| 0x1420bbdb0 | fBookLight2DimmerValue:Interface | 1.0 |
| 0x1420bbd98 | fBookLight2Radius:Interface | 400.0 |
| 0x1420bbd08 | fBookLight2X:Interface | 10.0 |
| 0x1420bbd20 | fBookLight2Y:Interface | -75.0 |
| 0x1420bbd38 | fBookLight2Z:Interface | 10.0 |
| 0x1420bbcc0 | fBookLightDiffuseColorB:Interface | 0.83 |
| 0x1420bbca8 | fBookLightDiffuseColorG:Interface | 0.95 |
| 0x1420bbc90 | fBookLightDiffuseColorR:Interface | 0.98 |
| 0x1420bbcf0 | fBookLightDimmerValue:Interface | 1.75 |
| 0x1420bbcd8 | fBookLightRadius:Interface | 400.0 |
| 0x1420bbc48 | fBookLightX:Interface | 100.0 |
| 0x1420bbc60 | fBookLightY:Interface | -350.0 |
| 0x1420bbc78 | fBookLightZ:Interface | 100.0 |
| 0x1420ba840 | fBookOpenTime:Interface | 1000.0 |
| 0x1420ba7e0 | fBookPosHeightPercentage:Interface | 0.445 |
| 0x1420ba7f8 | fBookPosWidthPercentage:Interface | 0.5 |
| 0x1420ba858 | fBookXRotation:Interface | -25.0 |
| 0x1420ba9f0 | fCrafting3DItemPosX:Interface | 0.0 |
| 0x1420baa50 | fCrafting3DItemPosXWide:Interface | 0.0 |
| 0x1420baa08 | fCrafting3DItemPosY:Interface | -500.0 |
| 0x1420baa68 | fCrafting3DItemPosYWide:Interface | -500.0 |
| 0x1420baa20 | fCrafting3DItemPosZ:Interface | 16.0 |
| 0x1420baa80 | fCrafting3DItemPosZWide:Interface | 12.0 |
| 0x1420baa38 | fCrafting3DItemScale:Interface | 1.87 |
| 0x1420baa98 | fCrafting3DItemScaleWide:Interface | 1.5 |
| 0x1420d2ff0 | fDebugFontSize:Interface | 13.0 |
| 0x142077958 | fFadeToBlackFadeSeconds:Interface | 1.0 |
| 0x1420d30e8 | fGamepadCursorSpeed:Interface | 11.0 |
| 0x1420bae90 | fInventory3DBoundRadiusScale:Interface | 12.5 |
| 0x1420bad70 | fInventory3DItemPosScale:Interface | 1.87 |
| 0x1420badd0 | fInventory3DItemPosScaleWide:Interface | 1.5 |
| 0x1420bad28 | fInventory3DItemPosX:Interface | -38.0 |
| 0x1420bad88 | fInventory3DItemPosXWide:Interface | -29.0 |
| 0x1420bad40 | fInventory3DItemPosY:Interface | -500.0 |
| 0x1420bada0 | fInventory3DItemPosYWide:Interface | -500.0 |
| 0x1420bad58 | fInventory3DItemPosZ:Interface | 16.0 |
| 0x1420badb8 | fInventory3DItemPosZWide:Interface | 12.0 |
| 0x1420bae78 | fInventory3DItemRotMouseSpeed:Interface | 50.0 |
| 0x1420bae60 | fInventory3DItemRotSpeed:Interface | 3.0 |
| 0x1420bae48 | fInventory3DItemZoomScale:Interface | 2.25 |
| 0x1420bade8 | fInventory3DItemZoomSpeed:Interface | 1.5 |
| 0x1420bae00 | fInventory3DItemZoomX:Interface | 0.0 |
| 0x1420bae18 | fInventory3DItemZoomY:Interface | -500.0 |
| 0x1420bae30 | fInventory3DItemZoomZ:Interface | 0.0 |
| 0x1420bbc00 | fInventoryLight2DiffuseColorB:Interface | 0.83 |
| 0x1420bbbe8 | fInventoryLight2DiffuseColorG:Interface | 0.95 |
| 0x1420bbbd0 | fInventoryLight2DiffuseColorR:Interface | 0.98 |
| 0x1420bbc30 | fInventoryLight2DimmerValue:Interface | 1.75 |
| 0x1420bbc18 | fInventoryLight2Radius:Interface | 0.0 |
| 0x1420bbb40 | fInventoryLightDiffuseColorB:Interface | 0.83 |
| 0x1420bbb28 | fInventoryLightDiffuseColorG:Interface | 0.95 |
| 0x1420bbb10 | fInventoryLightDiffuseColorR:Interface | 0.98 |
| 0x1420bbb70 | fInventoryLightDimmerValue:Interface | 1.75 |
| 0x1420bbb58 | fInventoryLightRadius:Interface | 400.0 |
| 0x1420bbb88 | fInventoryMenuLight2X:Interface | 100.0 |
| 0x1420bbba0 | fInventoryMenuLight2Y:Interface | -350.0 |
| 0x1420bbbb8 | fInventoryMenuLight2Z:Interface | 100.0 |
| 0x1420bbac8 | fInventoryMenuLightX:Interface | 100.0 |
| 0x1420bbae0 | fInventoryMenuLightY:Interface | -350.0 |
| 0x1420bbaf8 | fInventoryMenuLightZ:Interface | 100.0 |
| 0x1420bc990 | fJournalLongRepeatRate:Interface | 0.2 |
| 0x1420bc978 | fJournalShortRepeatRate:Interface | 0.075 |
| 0x14209e4d8 | fLargeActivatePickLength_G:Interface | 500.0 |
| 0x1420bb050 | fLockCenterOffset:Interface | 9.0 |
| 0x1420bafd8 | fLockMaxAngle:Interface | 90.0 |
| 0x1420bc278 | fLockpickLightDiffuseColorB:Interface | 0.83 |
| 0x1420bc260 | fLockpickLightDiffuseColorG:Interface | 0.95 |
| 0x1420bc248 | fLockpickLightDiffuseColorR:Interface | 0.98 |
| 0x1420bc2a8 | fLockpickLightDimmerValue:Interface | 1.75 |
| 0x1420bc290 | fLockpickLightRadius:Interface | 400.0 |
| 0x1420bc200 | fLockpickLightX:Interface | 100.0 |
| 0x1420bc218 | fLockpickLightY:Interface | -1000.0 |
| 0x1420bc230 | fLockpickLightZ:Interface | 100.0 |
| 0x1420baff0 | fLockPositionX:Interface | 0.0 |
| 0x1420bb008 | fLockPositionY:Interface | -1100.0 |
| 0x1420bb020 | fLockPositionYWide:Interface | -1300.0 |
| 0x1420bb038 | fLockPositionZ:Interface | 3.0 |
| 0x1420bafc0 | fLockRotationSpeed:Interface | 80.0 |
| 0x1420bb068 | fLockRotCenterOffsetX:Interface | -14.5 |
| 0x1420bb080 | fLockRotCenterOffsetZ:Interface | 3.0 |
| 0x1420bb1b8 | fMagic3DItemPosScale:Interface | 1.87 |
| 0x1420bb218 | fMagic3DItemPosScaleWide:Interface | 1.75 |
| 0x1420bb170 | fMagic3DItemPosX:Interface | 34.7 |
| 0x1420bb1d0 | fMagic3DItemPosXWide:Interface | 26.0 |
| 0x1420bb188 | fMagic3DItemPosY:Interface | -500.0 |
| 0x1420bb1e8 | fMagic3DItemPosYWide:Interface | -500.0 |
| 0x1420bb1a0 | fMagic3DItemPosZ:Interface | 8.0 |
| 0x1420bb200 | fMagic3DItemPosZWide:Interface | 6.0 |
| 0x1420bb9b8 | fMaxSubtitleDistance:Interface | 1250.0 |
| 0x1420bb3c8 | fMenuKeyRepeatLong:Interface | 0.5 |
| 0x1420bb3b0 | fMenuKeyRepeatShort:Interface | 0.1 |
| 0x142077970 | fMinSecondsForLoadFadeIn:Interface | 1.5 |
| 0x1420ba828 | fNoteDistance:Interface | 90.0 |
| 0x1420ba9a8 | fPackratRatio:Interface | 0.0 |
| 0x1420baf90 | fPickMouseRotationSpeed:Interface | 15.0 |
| 0x1420baf78 | fPickRotationSpeed:Interface | 400.0 |
| 0x1420bb7e0 | fPlayerBodyEditDistance:Interface | 175.0 |
| 0x1420bb7f8 | fPlayerFaceEditDistance:Interface | 100.0 |
| 0x1420bb810 | fPlayerRotationAngle:Interface | 30.0 |
| 0x1420bb828 | fPlayerZoomTime:Interface | 1000.0 |
| 0x1420bb840 | fRSMCameraLookAtPercent:Interface | 0.955 |
| 0x1420bb858 | fRSMLookAtOnGain:Interface | 0.06 |
| 0x1420d2fa0 | fSafeZoneX:Interface | 15.0 |
| 0x1420d2f70 | fSafeZoneXWide:Interface | 15.0 |
| 0x1420d2fb8 | fSafeZoneY:Interface | 15.0 |
| 0x1420d2f88 | fSafeZoneYWide:Interface | 15.0 |
| 0x1420bb8f8 | fSleepFaderTime:Interface | 0.7 |
| 0x1420bba80 | fTweenLongRepeatRate:Interface | 0.2 |
| 0x1420bba68 | fTweenShortRepeatRate:Interface | 0.1 |
| 0x1420bb488 | fUIAltLogoModel_TranslateX_G:Interface | 0.0 |
| 0x1420bb4a0 | fUIAltLogoModel_TranslateY_G:Interface | 0.0 |
| 0x1420bb4b8 | fUIAltLogoModel_TranslateZ_G:Interface | 0.0 |
| 0x1420bbe28 | fUICameraFarDistance:Interface | 20480.0 |
| 0x1420bbe10 | fUICameraNearDistance:Interface | 15.0 |
| 0x1420bb500 | fUILogoModel_AutoRotateSpeed:Interface | 0.1 |
| 0x1420bb4e8 | fUILogoModel_FadeSecs:Interface | 0.0001 |
| 0x1420bb530 | fUILogoModel_MouseThreshold:Interface | 2.0 |
| 0x1420bb578 | fUILogoModel_MouseToPanSpeed:Interface | 1.0 |
| 0x1420bb518 | fUILogoModel_MouseToRotateSpeed:Interface | 0.02 |
| 0x1420bb5a8 | fUILogoModel_MouseToZoomSpeed:Interface | 0.6 |
| 0x1420bb560 | fUILogoModel_RotationPauseDuration:Interface | 0.25 |
| 0x1420bb590 | fUILogoModel_ThumbstickToPanSpeed:Interface | 8.0 |
| 0x1420bb548 | fUILogoModel_ThumbstickToRotateSpeed:Interface | 0.45 |
| 0x1420bb5c0 | fUILogoModel_ThumbstickToZoomSpeed:Interface | 5.0 |
| 0x1420bb668 | fUIMistMenu_CameraFOV_G:Interface | 75.0 |
| 0x1420bb620 | fUIMistMenu_CameraLookAtX_G:Interface | -50.0 |
| 0x1420bb638 | fUIMistMenu_CameraLookAtY_G:Interface | 0.0 |
| 0x1420bb650 | fUIMistMenu_CameraLookAtZ_G:Interface | 0.0 |
| 0x1420bb5d8 | fUIMistMenu_CameraX_G:Interface | -50.0 |
| 0x1420bb5f0 | fUIMistMenu_CameraY_G:Interface | 600.0 |
| 0x1420bb608 | fUIMistMenu_CameraZ_G:Interface | 80.0 |
| 0x1420bb710 | fUIMistMenu_DefaultLogoNIFScale:Interface | 1.0 |
| 0x1420bb740 | fUIMistMenu_LogoOnscreenPanThresholdX:Interface | 0.5 |
| 0x1420bb758 | fUIMistMenu_LogoOnscreenPanThresholdY:Interface | 0.33 |
| 0x1420bb7b8 | fUIMistMenu_LogoOnscreenZoomMaxFOV:Interface | 95.0 |
| 0x1420bb7a0 | fUIMistMenu_LogoOnscreenZoomMinFOV:Interface | 60.0 |
| 0x1420bb788 | fUIMistMenu_LogoOnscreenZoomThresholdFar:Interface | 0.1 |
| 0x1420bb770 | fUIMistMenu_LogoOnscreenZoomThresholdNear:Interface | 3.5 |
| 0x1420bb4d0 | fUIMistModel_FadeOutTime:Interface | 0.0 |
| 0x1420bb470 | fUIMistModel_RotateZ_G:Interface | -180.0 |
| 0x1420bb428 | fUIMistModel_TranslateX_G:Interface | 0.0 |
| 0x1420bb440 | fUIMistModel_TranslateY_G:Interface | 0.0 |
| 0x1420bb458 | fUIMistModel_TranslateZ_G:Interface | 0.0 |
| 0x1420bbf78 | fUIPlayerSceneLight2DiffuseColorB:Interface | 0.8 |
| 0x1420bbf60 | fUIPlayerSceneLight2DiffuseColorG:Interface | 0.81 |
| 0x1420bbf48 | fUIPlayerSceneLight2DiffuseColorR:Interface | 0.7 |
| 0x1420bbfa8 | fUIPlayerSceneLight2DimmerValue:Interface | 3.0 |
| 0x1420bbf90 | fUIPlayerSceneLight2Radius:Interface | 1024.0 |
| 0x1420bbf00 | fUIPlayerSceneLight2X:Interface | 160.0 |
| 0x1420bbf18 | fUIPlayerSceneLight2Y:Interface | -96.0 |
| 0x1420bbf30 | fUIPlayerSceneLight2Z:Interface | 160.0 |
| 0x1420bc038 | fUIPlayerSceneLight3DiffuseColorB:Interface | 1.0 |
| 0x1420bc020 | fUIPlayerSceneLight3DiffuseColorG:Interface | 1.0 |
| 0x1420bc008 | fUIPlayerSceneLight3DiffuseColorR:Interface | 1.0 |
| 0x1420bc068 | fUIPlayerSceneLight3DimmerValue:Interface | 0.1 |
| 0x1420bc050 | fUIPlayerSceneLight3Radius:Interface | 1024.0 |
| 0x1420bbfc0 | fUIPlayerSceneLight3X:Interface | 128.0 |
| 0x1420bbfd8 | fUIPlayerSceneLight3Y:Interface | 160.0 |
| 0x1420bbff0 | fUIPlayerSceneLight3Z:Interface | -96.0 |
| 0x1420bbeb8 | fUIPlayerSceneLightDiffuseColorB:Interface | 0.82 |
| 0x1420bbea0 | fUIPlayerSceneLightDiffuseColorG:Interface | 0.96 |
| 0x1420bbe88 | fUIPlayerSceneLightDiffuseColorR:Interface | 0.96 |
| 0x1420bbee8 | fUIPlayerSceneLightDimmerValue:Interface | 1.6 |
| 0x1420bbed0 | fUIPlayerSceneLightRadius:Interface | 1500.0 |
| 0x1420bbe40 | fUIPlayerSceneLightX:Interface | -160.0 |
| 0x1420bbe58 | fUIPlayerSceneLightY:Interface | 160.0 |
| 0x1420bbe70 | fUIPlayerSceneLightZ:Interface | 128.0 |
| 0x1420bc1b8 | fUIRaceSexLight2DiffuseColorB:Interface | 0.83 |
| 0x1420bc1a0 | fUIRaceSexLight2DiffuseColorG:Interface | 0.95 |
| 0x1420bc188 | fUIRaceSexLight2DiffuseColorR:Interface | 0.98 |
| 0x1420bc1e8 | fUIRaceSexLight2DimmerValue:Interface | 1.75 |
| 0x1420bc1d0 | fUIRaceSexLight2Radius:Interface | 1400.0 |
| 0x1420bc140 | fUIRaceSexLight2X:Interface | 0.5 |
| 0x1420bc158 | fUIRaceSexLight2Y:Interface | -150.0 |
| 0x1420bc170 | fUIRaceSexLight2Z:Interface | 60.5 |
| 0x1420bc0f8 | fUIRaceSexLightDiffuseColorB:Interface | 0.83 |
| 0x1420bc0e0 | fUIRaceSexLightDiffuseColorG:Interface | 0.95 |
| 0x1420bc0c8 | fUIRaceSexLightDiffuseColorR:Interface | 0.98 |
| 0x1420bc128 | fUIRaceSexLightDimmerValue:Interface | 0.65 |
| 0x1420bc110 | fUIRaceSexLightRadius:Interface | 1400.0 |
| 0x1420bc080 | fUIRaceSexLightX:Interface | 0.5 |
| 0x1420bc098 | fUIRaceSexLightY:Interface | -600.0 |
| 0x1420bc0b0 | fUIRaceSexLightZ:Interface | 60.5 |
| 0x1420bb098 | fUnlockDoorDelay:Interface | 1.5 |
| 0x1420bab58 | iCreditsFileMaxLinesLength:Interface | 1000 |
| 0x1420bc680 | iFavoriteItemQueueSize:Interface | 100 |
| 0x14209e4f0 | iMaxViewCasterPicksFuzzy:Interface | 5 |
| 0x14209e520 | iMaxViewCasterPicksGamebryo:Interface | 10 |
| 0x14209e508 | iMaxViewCasterPicksHavok:Interface | 10 |
| 0x1420bb9e8 | iSubtitleSpeakerNameColor:Interface | 8947848 |
| 0x1420bb680 | rUIMistMenu_AmbientXNegRGB:Interface | 0x00000000 |
| 0x1420bb698 | rUIMistMenu_AmbientXPosRGB:Interface | 0x00000000 |
| 0x1420bb6b0 | rUIMistMenu_AmbientYNegRGB:Interface | 0x00000000 |
| 0x1420bb6c8 | rUIMistMenu_AmbientYPosRGB:Interface | 0x00000000 |
| 0x1420bb6e0 | rUIMistMenu_AmbientZNegRGB:Interface | 0x00000000 |
| 0x1420bb6f8 | rUIMistMenu_AmbientZPosRGB:Interface | 0x00000000 |
| 0x1420bab28 | sCreditsFile:Interface | "Interface/Credits.txt" |
| 0x1420bab40 | sCreditsFilePLRU:Interface | "Interface/Credits_PLRU.txt" |
| 0x1420baf38 | sForcedLoadScreenEditorID:Interface | "" |
| 0x1420bb870 | sPosePlayerRaceSexMenu:Interface | "OffsetBoundStandingPlayerInstant" |
| 0x1420bb728 | sUIMistMenu_DefaultLogoCameraPath:Interface | "" |
| 0x1420baab0 | uMaxCustomItemNameLength:Interface | 32 |
| 0x1420bba98 | uTweenSaveDelay:Interface | 6 |

## Ini settings: [Pathfinding] and navmesh

The value compiled into `SkyrimSE.exe` for each ini setting: what the game uses when neither `Skyrim.ini` nor `SkyrimPrefs.ini` sets it. `skyrim/ini.zap` keeps the few the port reads; this is the whole table. A setting the game fills at run time holds 0 here (iDifficulty and fAutosaveEveryXMins are two).

Read from the static `SettingT<INISettingCollection>` objects in `.data` (24 bytes: the vtable, the value, the pointer to the name; the vtable's RTTI names the class), found by scanning `.data` for pointers to names and checked against REA's `read_bytes` at 0x1420d9078 (fShadowBiasScale:Display). The address is the object's; the value is decoded by the name's type letter (f float, i int, u unsigned, b bool, s string, r and a 32-bit colors).

| address | setting | value |
|---|---|---|
| 0x1420d49f0 | bAvoidBoxTriggersFailure:Pathfinding | 0 |
| 0x1420b3208 | bBackgroundNavmeshUpdate:Pathfinding | 1 |
| 0x1420d4018 | bBackgroundPathing:Pathfinding | 1 |
| 0x1420d4228 | bCreateDebugInfo:Pathfinding | 0 |
| 0x1420b3250 | bCutDoors:Pathfinding | 1 |
| 0x1420d4030 | bDisableUnloadedPaths:Pathfinding | 0 |
| 0x1420d47c8 | bFacePathVector:Pathfinding | 1 |
| 0x1420b31a0 | bFixNavmeshInfosOnLoad:Pathfinding | 0 |
| 0x1420b3038 | bGlobalNavMeshCheck:NavMeshGeneration | 0 |
| 0x1420b3050 | bGlobalNavMeshCheckDeleteWarningTriangles:NavMeshGeneration | 0 |
| 0x1420d4aa0 | bIgnoreThresholds:Pathfinding | 0 |
| 0x1420d4240 | bRebuildPathIfSmootherFailed:Pathfinding | 1 |
| 0x1420d4608 | bSlowDownForActorAvoidance:Pathfinding | 0 |
| 0x1420d4408 | bStaticAvoidanceTriggerMovementBlocked:Pathfinding | 0 |
| 0x1420d44d0 | bUseActorAvoidance:Pathfinding | 1 |
| 0x1420d49c0 | bUseActorAvoidBox:Pathfinding | 1 |
| 0x1420d4288 | bUseAlternateSmoothingForPrime:Pathfinding | 1 |
| 0x1420d4258 | bUseOldPathSmoothing:Pathfinding | 0 |
| 0x1420d4210 | bUsePathSmoothing:Pathfinding | 1 |
| 0x1420d4270 | bUseRayCasts:Pathfinding | 1 |
| 0x1420d41f8 | bUseStraightLineCheckFirst:Pathfinding | 1 |
| 0x1420d42a0 | bUseTangentSmoothing:Pathfinding | 1 |
| 0x1420b31b8 | bUseTaskletsToRecomputeBounds:Pathfinding | 0 |
| 0x1420d4a28 | bUseTweenedAnimations:Pathfinding | 1 |
| 0x1420b6a70 | bUseVelocityObstacles:Pathfinding | 1 |
| 0x1420d3da8 | bWarnIfHighLevelSearchFails:Pathfinding | 0 |
| 0x1420b81e0 | bWarpOnConsecutiveFailures:Pathfinding | 1 |
| 0x1420d4468 | fAcceptableErrorRatio:Pathfinding | 0.9 |
| 0x1420b8098 | fAICombatTurnSpeedScale:Pathfinding | 2.5 |
| 0x1420b8080 | fAITurnSpeedScale:Pathfinding | 1.5 |
| 0x1420d3f18 | fAvoidanceDistanceRadiusMult:Pathfinding | 1.0 |
| 0x1420d4560 | fAvoidanceTimeDelta:Pathfinding | 3.0 |
| 0x1420d45c0 | fAvoidNodeCost:Pathfinding | 24.0 |
| 0x1420d45a8 | fAvoidNodeRadiusAdd:Pathfinding | 11.0 |
| 0x1420d4100 | fAvoidPreferredTriangleCrossingMultiplier:Pathfinding | 10.0 |
| 0x1420d40e8 | fAvoidPreferredTriangleMultiplier:Pathfinding | 3.0 |
| 0x1420d4918 | fBackPedalAngle:Pathfinding | 160.0 |
| 0x1420d4118 | fBadTriangleMultiplier:Pathfinding | 100.0 |
| 0x1420d49d8 | fDefaultAvoidBoxAvoidNodeRadius:Pathfinding | 32.0 |
| 0x1420d4480 | fDefaultAvoidNodeCost:Pathfinding | 32.0 |
| 0x1420d4c58 | fDefaultPreferredFactor:Pathfinding | 0.5 |
| 0x1420d4498 | fDefaultStaticAvoidNodeRadius:Pathfinding | 32.0 |
| 0x1420d4c70 | fDefaultTangentSmoothingFactor:Pathfinding | 1.0 |
| 0x1420d4ce8 | fDistFromPathForFollowingRadiusMult:Pathfinding | 2.0 |
| 0x1420d3d40 | fFindClosestEdgesRadius:BSPathing | 512.0 |
| 0x1420d3fd0 | fFindMaxSpeedMinParamIncrementPercent:Pathfinding | 0.1 |
| 0x1420b6c38 | fFollowerTeleportOffsetFudge:Pathfinding | 10.0 |
| 0x1420d3ea0 | fHeadingToPathTangentMaxAngle:Pathfinding | 15.0 |
| 0x1420b7038 | fINIDetectDoorsForPathingTime:Pathing | 0.5 |
| 0x1420d3d70 | fLedgeJumpHeightBuffer:Pathfinding | 16.0 |
| 0x1420d4548 | fMaxAvoidanceRadius:Pathfinding | 512.0 |
| 0x1420d47b0 | fMaxCollisionTime:Pathfinding | 1.0 |
| 0x1420d4bf0 | fMaxDistanceFromNavmeshMult:Pathfinding | 0.25 |
| 0x1420d44e8 | fMaxDistanceMoved:Pathfinding | 5.0 |
| 0x1420d4500 | fMaxDistanceMoved:Pathfinding | 50.0 |
| 0x1420d3e88 | fMaxDistFromPathRadiusMult:Pathfinding | 5.0 |
| 0x1420d4130 | fMaxEdgeLength:Pathfinding | 512.0 |
| 0x1420d4198 | fMaxFitnessMultiplier:Pathfinding | 2.0 |
| 0x1420d4d60 | fMaxHeightFromNavmeshToObstacleBoxBottom:Pathfinding | 128.0 |
| 0x1420d4d78 | fMaxHeightFromObstacleBoxToToNavmesh:Pathfinding | -16.0 |
| 0x1420d4590 | fMaxTimeBlockedByActors:Pathfinding | 1.0 |
| 0x1420d4518 | fMaxTimeSizeAvoidNode:Pathfinding | 1.0 |
| 0x1420d4530 | fMinAvoidanceRadius:Pathfinding | 256.0 |
| 0x1420d4798 | fMinCollisionTime:Pathfinding | 0.25 |
| 0x1420d3ed0 | fMinDist:Pathfinding | 50.0 |
| 0x1420b8258 | fMinFailureDistance:Pathfinding | 50.0 |
| 0x1420d3f00 | fMinFrictionSpeed:Pathfinding | 2.0 |
| 0x1420d3dc0 | fMinimalUsePathingCost:Pathfinding | 409600.0 |
| 0x1420d3e70 | fMinNormalizedSpeedForSlowdown:Pathfinding | 0.75 |
| 0x1420b81c8 | fMinStairSpeed:Pathfinding | 80.0 |
| 0x1420d3ee8 | fMinTimeToNextPoint:Pathfinding | 0.3 |
| 0x1420b7108 | fMovementBlockedTimer:Pathfinding | 0.02 |
| 0x1420d4988 | fNavmeshBoundsActorRadiusMultiplier:Pathfinding | 1.0 |
| 0x1420d4970 | fNavmeshBoundsMinTimeOfImpact:Pathfinding | 0.0333 |
| 0x1420b89f8 | fNodeDistanceThreshold:Pathfinding | 25.0 |
| 0x1420b3268 | fObstacleManagerMinHeight:Pathfinding | 48.0 |
| 0x1420b3280 | fObstacleManagerMinWidth:Pathfinding | 16.0 |
| 0x1420b3220 | fObstacleUpdateDeltaWhenMoving:Pathfinding | 1.0 |
| 0x1420b3238 | fObstacleUpdateDeltaWhenUnknown:Pathfinding | 5.0 |
| 0x1420d40b8 | fPathingLargeActorRadius:Pathfinding | 80.0 |
| 0x1420d4078 | fPathManagerDebugInfoWindow:Pathfinding | 1.0 |
| 0x1420d4ab8 | fPathToAnimLengthMaxMultiplier:Pathfinding | 2.0 |
| 0x1420d4b88 | fPOVSmootherAvoidNodeCost:Pathfinding | 7.0 |
| 0x1420d40d0 | fPreferredTriangleMultiplier:Pathfinding | 0.01 |
| 0x1420d3e58 | fRotateTowardsPathThreshold:Pathfinding | 5.0 |
| 0x1420d3e40 | fShortPathRadiusMult:Pathfinding | 2.0 |
| 0x1420d47e0 | fSlowDownMultiplier:Pathfinding | 0.5 |
| 0x1420d4c08 | fSmoothingStepHeight:Pathfinding | 25.0 |
| 0x1420b8180 | fSprintAccelerationMult:Pathfinding | 10.0 |
| 0x1420b81b0 | fSprintAngleToPathThreshold:Pathfinding | 5.0 |
| 0x1420b8198 | fSprintDistToPathThresholdRadiusMult:Pathfinding | 0.5 |
| 0x1420d3d58 | fStaticPathTangentSmoothingFactor:Pathfinding | 0.5 |
| 0x1420d3eb8 | fTeleportNodeAngleTolerance:Pathfinding | 5.0 |
| 0x1420d4450 | fTotalDisplacementThresholdRadiusMult:Pathfinding | 0.66 |
| 0x1420d4438 | fTotalTimePadding:Pathfinding | 0.5 |
| 0x1420d4420 | fTotalTimeThreshold:Pathfinding | 1.0 |
| 0x1420d4740 | fTweenerAnimDurationOffset:Pathfinding | 0.1 |
| 0x1420d4390 | fTweeningMaxPercentSpeedDelta:Pathfinding | 0.2 |
| 0x1420b8240 | fWarpMaxTime:Pathfinding | 5.0 |
| 0x1420b8228 | fWarpPathOffset:Pathfinding | 100.0 |
| 0x1420b8210 | fWarpRequestActorRadius:Pathfinding | 5.0 |
| 0x1420d4148 | fWaterTriangleCostMultiplier:Pathfinding | 4.0 |
| 0x1420d4160 | fWaterTriangleCrossingCostMultiplier:Pathfinding | 5.0 |
| 0x1420d4c40 | iDefaultRetryCount:Pathfinding | 3 |
| 0x1420d3fb8 | iFindMaxSpeedMinIterationCount:Pathfinding | 10 |
| 0x1420d4578 | iMaxActorsToAvoid:Pathfinding | 10 |
| 0x1420d42f8 | iMaxAvoidBoxCheckPerFrame:Pathfinding | 2 |
| 0x1420d4060 | iMaxHavokRequestsPerFrame:Pathfinding | 2 |
| 0x1420d4318 | iMaxObstacleBuildPerFrame:Pathfinding | 1 |
| 0x1420b0ec0 | iMaxPathRequestsPerFrameTracked:Pathfinding | 32 |
| 0x1420d4048 | iMaxQueuedPathingRequests:Pathfinding | 50 |
| 0x1420b0ea8 | iPathRequestsAllowedPerFrame:Pathfinding | 2 |
| 0x1420b81f8 | iWarpMaxPathFailureCount:Pathfinding | 3 |
| 0x1420b3020 | uNavmeshTriangleCountInteriorWarnThreshold:NavMeshGeneration | 5000 |
| 0x1420b3008 | uNavmeshTriangleCountWarnThreshold:NavMeshGeneration | 3500 |

## Ini pref settings (SkyrimPrefs.ini's own class, INIPrefSettingCollection)

The value compiled into `SkyrimSE.exe` for each ini setting: what the game uses when neither `Skyrim.ini` nor `SkyrimPrefs.ini` sets it. `skyrim/ini.zap` keeps the few the port reads; this is the whole table. A setting the game fills at run time holds 0 here (iDifficulty and fAutosaveEveryXMins are two).

Read from the static `SettingT<INISettingCollection, INIPrefSettingCollection>` objects in `.data` (24 bytes: the vtable, the value, the pointer to the name; the vtable's RTTI names the class), found by scanning `.data` for pointers to names and checked against REA's `read_bytes` at 0x1420d9078 (fShadowBiasScale:Display). The address is the object's; the value is decoded by the name's type letter (f float, i int, u unsigned, b bool, s string, r and a 32-bit colors).

| address | setting | value |
|---|---|---|
| 0x1420b83e0 | bAlwaysRunByDefault:Controls | 1 |
| 0x1420d0328 | bBorderless:Display | 0 |
| 0x1420b5438 | bCheckForMissingContentOnStartup:Gameplay | 1 |
| 0x1420bc8c0 | bCrosshairEnabled | 1 |
| 0x1420792b0 | bDecals:Decals | 1 |
| 0x1420bb9a0 | bDialogueSubtitles:Interface | 0 |
| 0x1420d8ed0 | bDoDepthOfField:Imagespace | 1 |
| 0x14207b838 | bDrawLandShadows:Display | 0 |
| 0x1420d6ce0 | bEnableImprovedSnow:Display | 1 |
| 0x1420d8d70 | bEnableProjecteUVDiffuseNormals:Display | 1 |
| 0x1420b3b08 | bEnableStoryManagerLogging:General | 0 |
| 0x1420d73d8 | bForceCreateTarget:Display | 0 |
| 0x1420bb280 | bFreebiesSeen:General | 0 |
| 0x1420d6a88 | bFXAAEnabled:Display | 0 |
| 0x1420ccd48 | bGamepadEnable | 1 |
| 0x1420b83b0 | bGamePadRumble:Controls | 0 |
| 0x1420bb988 | bGeneralSubtitles:Interface | 0 |
| 0x1420d7e48 | bIBLFEnable:Display | 1 |
| 0x1420d8ad0 | bIndEnable:Display | 0 |
| 0x1420b83c8 | bInvertYValues:Controls | 0 |
| 0x1420d6eb0 | bLensFlare:ImageSpace | 1 |
| 0x1420b4290 | bMusicOn:CreationsMenu | 1 |
| 0x1420b0a18 | bRenderSkinnedTrees:Trees | 1 |
| 0x1420d8a58 | bSAO_CS_Enable:Display | 0 |
| 0x1420d87a0 | bSAOEnable:Display | 1 |
| 0x1420bc7d0 | bSaveOnPause | 0 |
| 0x1420bc788 | bSaveOnRest | 0 |
| 0x1420bc7b8 | bSaveOnTravel | 0 |
| 0x1420bc7a0 | bSaveOnWait | 0 |
| 0x1420d86a8 | bScreenSpaceReflectionEnabled:Display | 1 |
| 0x1420bac50 | bShowCompass:Interface | 1 |
| 0x1420bc770 | bShowFloatingQuestMarkers:GamePlay | 0 |
| 0x1420b3388 | bShowLODInEditor:TerrainManager | 1 |
| 0x1420bc758 | bShowQuestMarkers:GamePlay | 1 |
| 0x1420792c8 | bSkinnedDecals:Decals | 1 |
| 0x1420d8878 | bToggleSparkles:Display | 1 |
| 0x1420b0a78 | bTreesReceiveShadows:Display | 1 |
| 0x1420b5268 | bUpsellOwned:General | 0 |
| 0x1420d7378 | bUse64bitsHDRRenderTarget:Display | 0 |
| 0x1420b47c8 | bUseKinect:Controls | 0 |
| 0x14209e570 | bUsePrecipitationOcclusion:Display | 1 |
| 0x1420d8c20 | bUseTAA:Display | 1 |
| 0x1420b3788 | bUseWaterDepth:Water | 1 |
| 0x1420b39c8 | bUseWaterDisplacements:Water | 1 |
| 0x1420b37a0 | bUseWaterReflections:Water | 1 |
| 0x1420b38d8 | bUseWaterRefractions:Water | 1 |
| 0x1420d70f0 | bVolumetricLightingEnable:Display | 1 |
| 0x1420b4c28 | fAudioMasterVolume:AudioMenu | 1.0 |
| 0x1420b5450 | fAutosaveEveryXMins:SaveGame | 0.0 |
| 0x1420b33e8 | fBlockLevel0Distance:TerrainManager | 35000.0 |
| 0x1420b3400 | fBlockLevel1Distance:TerrainManager | 70000.0 |
| 0x1420b3418 | fBlockMaximumDistance:TerrainManager | 250000.0 |
| 0x1420b3db8 | fCloudLevel0Distance:Clouds | 16384.0 |
| 0x1420b3dd0 | fCloudLevel1Distance:Clouds | 32768.0 |
| 0x1420b3de8 | fCloudLevel2Distance:Clouds | 262144.0 |
| 0x1420b3da0 | fCloudNearFadeDistance:Clouds | 9000.0 |
| 0x1420d8fa8 | fDynamicDOFBlurMultiplier:Display | 0.8 |
| 0x1420b8410 | fGamepadHeadingSensitivity:Controls | 0.0 |
| 0x1420d0340 | fGamma:Display | 1.0 |
| 0x1420793c8 | fGrassMaxStartFadeDistance:Grass | 7000.0 |
| 0x1420793b0 | fGrassMinStartFadeDistance:Grass | 400.0 |
| 0x1420793e0 | fGrassStartFadeDistance:Grass | 7000.0 |
| 0x1420bc818 | fHUDOpacity | 0.0 |
| 0x1420d9030 | fInteriorShadowDistance:Display | 3000.0 |
| 0x1420d67c0 | fLeafAnimDampenDistEnd:Display | 4600.0 |
| 0x1420d67a8 | fLeafAnimDampenDistStart:Display | 3600.0 |
| 0x1420d8d10 | fLightingOutputColourClampPostEnv:General | 1.0 |
| 0x1420d8cf8 | fLightingOutputColourClampPostLit:General | 1.0 |
| 0x1420d8d28 | fLightingOutputColourClampPostSpec:General | 1.0 |
| 0x1420d6ab8 | fLightLODStartFade:Display | 0.0 |
| 0x142077bf8 | fLODFadeOutMultActors:LOD | 6.0 |
| 0x142077c10 | fLODFadeOutMultItems:LOD | 3.0 |
| 0x142077c28 | fLODFadeOutMultObjects:LOD | 5.0 |
| 0x142077c40 | fLODFadeOutMultSkyCell:LOD | 1.0 |
| 0x1420d6728 | fMeshLODFadeBoundDefault:Display | 256.0 |
| 0x1420d6740 | fMeshLODFadePercentDefault:Display | 1.2 |
| 0x1420d66c8 | fMeshLODLevel1FadeDist:Display | 9999999.0 |
| 0x1420d66f8 | fMeshLODLevel1FadeTreeDistance:Display | 2844.0 |
| 0x1420d66e0 | fMeshLODLevel2FadeDist:Display | 9999999.0 |
| 0x1420d6710 | fMeshLODLevel2FadeTreeDistance:Display | 2048.0 |
| 0x1420d30d0 | fMouseCursorSpeed:Interface | 1.0 |
| 0x1420b8470 | fMouseHeadingSensitivity:Controls | 0.0125 |
| 0x1420d8db8 | fProjectedUVDiffuseNormalTilingScale:Display | 0.5 |
| 0x1420d8dd0 | fProjectedUVNormalDetailTilingScale:Display | 1.2 |
| 0x1420d9450 | fShadowDistance:Display | 8000.0 |
| 0x1420d6770 | fSkyCellRefFadeDistance | 150000.0 |
| 0x1420b33d0 | fSplitDistanceMult:TerrainManager | 1.5 |
| 0x1420b3430 | fTreeLoadDistance:TerrainManager | 75000.0 |
| 0x1420d6790 | fTreesMidLODSwitchDist:Display | 3600.0 |
| 0x1420b7270 | iDifficulty:GamePlay | 0 |
| 0x142079208 | iMaxDecalsPerFrame:Display | 100 |
| 0x1420b5fd8 | iMaxDesired:Particles | 750 |
| 0x142079220 | iMaxSkinDecalsPerFrame:Display | 25 |
| 0x1420d9060 | iNumFocusShadow:Display | 4 |
| 0x1420d9048 | iNumSplits:Display | 2 |
| 0x1420d7390 | iReflectionResolutionDivider:Display | 2 |
| 0x1420d7330 | iSaveGameScreenShotHeight:Display | 192 |
| 0x1420d7360 | iSaveGameScreenShotHeighWSt:Display | 192 |
| 0x1420d7318 | iSaveGameScreenShotWidth:Display | 256 |
| 0x1420d7348 | iSaveGameScreenShotWidthWS:Display | 320 |
| 0x1420b6468 | iScreenShotIndex:Display | 0 |
| 0x1420d9000 | iShadowMapResolution:Display | 2048 |
| 0x1420d7300 | iShadowMaskQuarter:Display | 4 |
| 0x1420b3b20 | iStoryManagerLoggingEvent:General | -1 |
| 0x1420d70c0 | iVolumetricLightingQuality:Display | 1 |
| 0x1420d03a0 | iVSyncPresentInterval:Display | 1 |
| 0x1420d73f0 | uBookRatio:Display | 2 |
| 0x14207b620 | uLargeRefLODGridSize:General | 9 |
| 0x142079238 | uMaxDecals:Decals | 1000 |
| 0x142079250 | uMaxSkinDecals:Decals | 100 |

## Ini settings: [Water], [LOD], [Grass], [Trees], [Landscape], [Weather], [LightingShader], [Decals], [BudgetCaps] and the other render sections

The value compiled into `SkyrimSE.exe` for each ini setting: what the game uses when neither `Skyrim.ini` nor `SkyrimPrefs.ini` sets it. `skyrim/ini.zap` keeps the few the port reads; this is the whole table. A setting the game fills at run time holds 0 here (iDifficulty and fAutosaveEveryXMins are two).

Read from the static `SettingT<INISettingCollection>` objects in `.data` (24 bytes: the vtable, the value, the pointer to the name; the vtable's RTTI names the class), found by scanning `.data` for pointers to names and checked against REA's `read_bytes` at 0x1420d9078 (fShadowBiasScale:Display). The address is the object's; the value is decoded by the name's type letter (f float, i int, u unsigned, b bool, s string, r and a 32-bit colors).

| address | setting | value |
|---|---|---|
| 0x1420794a0 | bAllowCreateGrass:Grass | 1 |
| 0x1420792f8 | bAllowDecalsOnAlpha:Decals | 1 |
| 0x1420794b8 | bAllowLoadGrass:Grass | 0 |
| 0x1420b3818 | bAutoWaterSilhouetteReflections:Water | 0 |
| 0x1420b2ef8 | bBackgroundInitializeGeometryDecals:Decals | 0 |
| 0x142079f68 | bBloodSplatterEnabled:ScreenSplatter | 1 |
| 0x14207b878 | bCurrentCellOnly:Landscape | 0 |
| 0x142079298 | bDecalMultithreaded:Decals | 0 |
| 0x142079328 | bDecalOcclusionQuery:Decals | 0 |
| 0x1420b33a0 | bDisplayCloudLOD:TerrainManager | 1 |
| 0x1420b5e28 | bDisplayLODLand:LOD | 1 |
| 0x1420d9110 | bDoRadialBlur:Imagespace | 1 |
| 0x142079398 | bDrawShaderGrass:Grass | 1 |
| 0x1420794e8 | bEnableGrassFade:Grass | 1 |
| 0x1420b09e8 | bEnableTreeAnimations:Trees | 1 |
| 0x1420b09d0 | bEnableTrees:Trees | 1 |
| 0x14209e850 | bFogEnabled:Weather | 1 |
| 0x1420792e0 | bForceAllDecals:Decals | 0 |
| 0x1420b0a00 | bForceFullDetail:Trees | 0 |
| 0x1420b3830 | bForceHighDetailReflections:Water | 0 |
| 0x1420b3848 | bForceLowDetailReflections:Water | 0 |
| 0x1420d6d80 | bForceLowDetailWater:Water | 0 |
| 0x142079488 | bGenerateGrassDataFiles:Grass | 0 |
| 0x142079410 | bGrassPointLighting:Grass | 0 |
| 0x1420b3448 | bKeepLowDetailTerrain:TerrainManager | 1 |
| 0x14207b968 | bLandSpecular:Landscape | 1 |
| 0x14207ad90 | bOutQuadInLin:bLightAttenuation | 0 |
| 0x1420b0a30 | bPickSkinnedTrees:Trees | 1 |
| 0x14209e838 | bPrecipitation:Weather | 1 |
| 0x1420b3800 | bReflectExplosions:Water | 0 |
| 0x1420b3878 | bReflectLODLand:Water | 1 |
| 0x1420b3890 | bReflectLODObjects:Water | 1 |
| 0x1420b38a8 | bReflectLODTrees:Water | 1 |
| 0x1420b38c0 | bReflectSky:Water | 1 |
| 0x1420b39e0 | bUseBulletWaterDisplacements:Water | 1 |
| 0x14207add8 | bUseConstant:bLightAttenuation | 0 |
| 0x1420b37d0 | bUseCubeMapReflections:Water | 1 |
| 0x14207adf0 | bUseLinear:bLightAttenuation | 0 |
| 0x1420b3370 | bUseNewTerrainSystem:TerrainManager | 1 |
| 0x14207ae08 | bUseQuadratic:bLightAttenuation | 1 |
| 0x1420b3728 | bUseWater:Water | 1 |
| 0x1420b3758 | bUseWaterHiRes:Water | 0 |
| 0x1420b39f8 | bUseWaterLOD:Water | 1 |
| 0x1420b37b8 | bUseWaterReflectionBlur:Water | 0 |
| 0x1420b3740 | bUseWaterShader:Water | 1 |
| 0x1420bc8a8 | fActorLODMax:LOD | 15.0 |
| 0x1420bc890 | fActorLODMin:LOD | 5.0 |
| 0x1420777f0 | fAlphaReduce:Weather | 1.0 |
| 0x1420b33b8 | fCameraAboveMaxHeightThreshold:TerrainManager | 2048.0 |
| 0x1420b3d88 | fCloudAtlasWidth:Clouds | 1.0 |
| 0x14207ad78 | fConstantValue:bLightAttenuation | 0.0 |
| 0x1420b3860 | fCubeMapRefreshRate:Water | 0.0 |
| 0x1420b9420 | fDebrisDecalTimer:Decals | 0.005 |
| 0x1420d6c50 | fDecalLODFadeEnd:LightingShader | 0.06 |
| 0x1420d6c38 | fDecalLODFadeStart:LightingShader | 0.05 |
| 0x1420b73a8 | fDialogueRotationPitchOffset:Dialogue | 0.17 |
| 0x1420b7390 | fDialogueRotationSecs:Dialogue | 1.0 |
| 0x1420778e0 | fDistanceMultiplier:LOD | 1.0 |
| 0x1420d6c20 | fEnvmapLODFadeEnd:LightingShader | 0.1 |
| 0x1420d6c08 | fEnvmapLODFadeStart:LightingShader | 0.09 |
| 0x1420b3998 | fExteriorWaterReflectionThreshold:Water | 300.0 |
| 0x1420d6c98 | fEyeEnvmapLODEnd:LightingShader | 0.05 |
| 0x142077910 | fFadeInThreshold:LOD | 0.7 |
| 0x142077928 | fFadeInTime:LOD | 1.2 |
| 0x1420778f8 | fFadeOutThreshold:LOD | 0.3 |
| 0x142077940 | fFadeOutTime:LOD | 2.0 |
| 0x1420794d0 | fGrassFadeInTime:Grass | 1.8 |
| 0x1420793f8 | fGrassFadeRange:Grass | 1000.0 |
| 0x142079440 | fGrassWindMagnitudeMax:Grass | 125.0 |
| 0x142079458 | fGrassWindMagnitudeMin:Grass | 5.0 |
| 0x1420b3310 | fHDLODSnowThresholdAngle:Terrain | 87.0 |
| 0x1420b39b0 | fInteriorWaterReflectionThreshold:Water | 10.0 |
| 0x1420bc878 | fItemLODMax:LOD | 10.0 |
| 0x1420bc860 | fItemLODMin:LOD | 1.5 |
| 0x14207b950 | fLandFriction:Landscape | 2.5 |
| 0x14207b860 | fLandTextureTilingMult:Landscape | 3.0 |
| 0x1420d6ec8 | fLensFlareFalloffRange:ImageSpace | 256.0 |
| 0x1420d6ee0 | fLensFlareGlobalIntensity:ImageSpace | 1.0 |
| 0x14207ae38 | fLightEnableDisableFadeTime:Light | 1.0 |
| 0x14207ada8 | fLinearRadiusMult:bLightAttenuation | 1.0 |
| 0x14207ad48 | fLinearValue:bLightAttenuation | 3.0 |
| 0x1420b5e40 | fLocalTreeMipMapLODBias:SpeedTree | -0.25 |
| 0x142077668 | fLODBoundRadiusMult:LOD | 10.0 |
| 0x1420b06c8 | fLodDistance:LOD | 500.0 |
| 0x1420b5f00 | fLODFadeOutActorMultCity:LOD | 1.0 |
| 0x1420b5eb8 | fLODFadeOutActorMultComplex:LOD | 1.0 |
| 0x1420b5f48 | fLODFadeOutActorMultInterior:LOD | 1.0 |
| 0x1420b5ee8 | fLODFadeOutItemMultCity:LOD | 1.0 |
| 0x1420b5ea0 | fLODFadeOutItemMultComplex:LOD | 1.0 |
| 0x1420b5f30 | fLODFadeOutItemMultInterior:LOD | 1.0 |
| 0x1420b5ed0 | fLODFadeOutObjectMultCity:LOD | 1.0 |
| 0x1420b5e88 | fLODFadeOutObjectMultComplex:LOD | 1.0 |
| 0x1420b5f18 | fLODFadeOutObjectMultInterior:LOD | 1.0 |
| 0x142077680 | fLODFadeOutPercent:LOD | 0.6 |
| 0x1420b5e70 | fLODLandDropAmount:LOD | 230.0 |
| 0x1420b5e10 | fLODLandVerticalBias:LOD | 0.0 |
| 0x1420d6698 | fLODMultTrees:LOD | 0.5 |
| 0x1420b32f8 | fLODSnowThresholdAngle:Terrain | 100.0 |
| 0x1420b5e58 | fLODTreeMipMapLODBias:SpeedTree | -0.75 |
| 0x142079d00 | fMaxMsUsagePerFrame:BudgetCaps | 28.0 |
| 0x142079bf8 | fMsActiveRefCount:BudgetCaps | 0.05 |
| 0x142079be0 | fMsActorRefCount:BudgetCaps | 0.245 |
| 0x142079c10 | fMsAnimatedObjectsCount:BudgetCaps | 0.05 |
| 0x142079cd0 | fMsDecalCount:BudgetCaps | 0.001 |
| 0x142079c40 | fMsEmittersCount:BudgetCaps | 0.01 |
| 0x142079c58 | fMsGeometryCount:BudgetCaps | 0.01 |
| 0x142079ce8 | fMsHavokTriCount:BudgetCaps | 0.001 |
| 0x142079cb8 | fMsLightCount:BudgetCaps | 0.01 |
| 0x142079ca0 | fMsLightExcessGeometry:BudgetCaps | 0.01 |
| 0x142079c28 | fMsParticlesCount:BudgetCaps | 0.001 |
| 0x142079bc8 | fMsRefCount:BudgetCaps | 0.021 |
| 0x142079c70 | fMsTriangleCount:BudgetCaps | 0.0001 |
| 0x142079c88 | fMsWaterCount:BudgetCaps | 0.1 |
| 0x1420bc848 | fObjectLODMax:LOD | 30.0 |
| 0x1420bc830 | fObjectLODMin:LOD | 5.0 |
| 0x14207adc0 | fQuadraticRadiusMult:bLightAttenuation | 1.0 |
| 0x14207ad60 | fQuadraticValue:bLightAttenuation | 16.0 |
| 0x1420d6c80 | fRefractionLODFadeEnd:LightingShader | 0.03 |
| 0x1420d6c68 | fRefractionLODFadeStart:LightingShader | 0.025 |
| 0x1420b3a40 | fRefractionWaterPlaneBias:Water | 3.0 |
| 0x1420d8ee8 | fRenderDepthMaxDepth:Imagespace | 10000.0 |
| 0x1420d6bf0 | fSpecularLODFadeEnd:LightingShader | 0.1 |
| 0x1420d6bd8 | fSpecularLODFadeStart:LightingShader | 0.09 |
| 0x14209e8c8 | fSunBaseSize:Weather | 425.0 |
| 0x14209e8f8 | fSunBoost:Weather | 1.0 |
| 0x14209e9b8 | fSunGlareMultiplier:Weather | 2.0 |
| 0x14209e8e0 | fSunGlareSize:Weather | 600.0 |
| 0x1420b38f0 | fSurfaceTileSize:Water | 2048.0 |
| 0x1420b06e0 | fTalkingDistance:LOD | 2000.0 |
| 0x14207b8a8 | fTexturePctThreshold:Grass | 0.0 |
| 0x1420b3908 | fTileTextureDivisor:Water | 4.75 |
| 0x1420b0a60 | fUpdateBudget:Trees | 1.5 |
| 0x1420b3920 | fWadingWaterQuadSize:Water | 2048.0 |
| 0x1420b3938 | fWadingWaterTextureRes:Water | 512.0 |
| 0x1420b3950 | fWaterGroupHeightRange:Water | 10.0 |
| 0x14207ac80 | fWaveOffsetRange:Grass | 1.75 |
| 0x1420d66b0 | iFadeNodeMinNearDistance:LOD | 500 |
| 0x142079470 | iGrassCellRadius:Grass | 2 |
| 0x14207b8f0 | iLandBorder1B:Landscape | 0 |
| 0x14207b8d8 | iLandBorder1G:Landscape | 255 |
| 0x14207b8c0 | iLandBorder1R:Landscape | 255 |
| 0x14207b938 | iLandBorder2B:Landscape | 0 |
| 0x14207b920 | iLandBorder2G:Landscape | 0 |
| 0x14207b908 | iLandBorder2R:Landscape | 0 |
| 0x14207b890 | iMaxGrassTypesPerTexure:Grass | 2 |
| 0x142079428 | iMinGrassSize:Grass | 20 |
| 0x1420d9128 | iRadialBlurLevel:Imagespace | 0 |
| 0x1420b37e8 | iWaterBlurAmount:Water | 1 |
| 0x14207bd88 | iWaterNoiseResolution:Water | 256 |
| 0x1420777d8 | sBumpFadeColor:Weather | "255,255,255,255" |
| 0x1420b3d70 | sCloudInstanceMesh:Clouds | "Meshes\\CloudInstance.NIF" |
| 0x14207b808 | sDefaultLandDiffuseTexture:Landscape | "Dirt02.dds" |
| 0x14207b820 | sDefaultLandNormalTexture:Landscape | "Dirt02_N.dds" |
| 0x1420777a8 | sEnvReduceColor:Weather | "255,255,255,255" |
| 0x1420777c0 | sLerpCloseColor:Weather | "255,255,255,255" |
| 0x1420b3a28 | sSurfaceTexture:Water | "water" |
| 0x1420798f8 | uActiveRefCount:BudgetCaps | 100 |
| 0x142079a78 | uActiveRefCountInterior:BudgetCaps | 100 |
| 0x142079d60 | uActorMemoryBudgetCap:BudgetCaps | 10485760 |
| 0x1420798e0 | uActorRefCount:BudgetCaps | 20 |
| 0x142079a60 | uActorRefCountInterior:BudgetCaps | 20 |
| 0x142079910 | uAnimatedObjectsCount:BudgetCaps | 50 |
| 0x142079a90 | uAnimatedObjectsCountInterior:BudgetCaps | 50 |
| 0x142079d48 | uCityLODBudgetAdjustment:BudgetCaps | 5242880 |
| 0x142079a18 | uDecalCount:BudgetCaps | 500 |
| 0x142079b98 | uDecalCountInterior:BudgetCaps | 500 |
| 0x1420b3338 | uDistantTreeBlockCacheSizePerCell:TerrainManager | 1 |
| 0x142079940 | uEmittersCount:BudgetCaps | 50 |
| 0x142079ac0 | uEmittersCountInterior:BudgetCaps | 50 |
| 0x142079958 | uGeometryCount:BudgetCaps | 1000 |
| 0x142079ad8 | uGeometryCountInterior:BudgetCaps | 1000 |
| 0x1420799a0 | uGeometryMemory:BudgetCaps | 5242880 |
| 0x142079b20 | uGeometryMemoryInterior:BudgetCaps | 10485760 |
| 0x142079a30 | uHavokTriCount:BudgetCaps | 5000 |
| 0x142079bb0 | uHavokTriCountInterior:BudgetCaps | 5000 |
| 0x1420799e8 | uLightCount:BudgetCaps | 10 |
| 0x142079b68 | uLightCountInterior:BudgetCaps | 10 |
| 0x142079a00 | uLightExcessGeometry:BudgetCaps | 100 |
| 0x142079b80 | uLightExcessGeometryInterior:BudgetCaps | 5 |
| 0x14207ad18 | uLinearMethod:bLightAttenuation | 1 |
| 0x142079d18 | uLoadedAreaNonActorMemoryBudgetCap:BudgetCaps | 185597952 |
| 0x1420b3968 | uMaxExteriorWaterReflections:Water | 2 |
| 0x1420b3980 | uMaxInteriorWaterReflections:Water | 4 |
| 0x142079268 | uMaxSkinDecalPerActor:Decals | 25 |
| 0x142079928 | uParticlesCount:BudgetCaps | 5000 |
| 0x142079aa8 | uParticlesCountInterior:BudgetCaps | 5000 |
| 0x14207ad30 | uQuadraticMethod:bLightAttenuation | 2 |
| 0x1420798c8 | uRefCount:BudgetCaps | 700 |
| 0x142079a48 | uRefCountInterior:BudgetCaps | 1000 |
| 0x1420b3a10 | uSurfaceFPS:Water | 12 |
| 0x1420799b8 | uTextureMemory:BudgetCaps | 20971520 |
| 0x142079b38 | uTextureMemoryInterior:BudgetCaps | 104857600 |
| 0x142079970 | uTriangleCount:BudgetCaps | 100000 |
| 0x142079af0 | uTriangleCountInterior:BudgetCaps | 100000 |
| 0x142079d30 | uWastelandLODBudgetAdjustment:BudgetCaps | 20971520 |
| 0x142079988 | uWaterCount:BudgetCaps | 10 |
| 0x142079b08 | uWaterCountInterior:BudgetCaps | 10 |
| 0x1420799d0 | uWaterMemory:BudgetCaps | 5242880 |
| 0x142079b50 | uWaterMemoryInterior:BudgetCaps | 10485760 |

## Actors and the player (55 classes, 1 template classes left out)

From the MSVC RTTI of `SkyrimSE.exe`: 7,831 type descriptors (`.?AV...@@` in `.data`), 8,457 complete object locators and 7,159 classes with a vtable in `.rdata`. Here the classes of the inn's systems with their primary vtable (the one at offset 0 of the object) and how many virtual functions follow it before the next vtable (the count includes the slots of the base classes; a class's own slots come last). A secondary vtable (a base at another offset) is listed with that offset. Template classes (`BSTEventSink<...>`, `ConcreteFormFactory<...>`, the behavior tree's `CombatBehaviorTreeNodeObject<...>`) are left out; their count is in the system's heading. The vtable's slot k holds the address of the virtual function, so a function is found as the vtable's address plus 8 k, and `procedure_pseudo_code` on that address gives its code.

The layouts to read a slot by name: CommonLibSSE-NG's headers declare each class's virtual functions in vtable order (`IMenu`: 0 destructor, 1 Accept(CallbackProcessor), 2 PostCreate, 3 Unk_03, 4 ProcessMessage(UIMessage), 5 AdvanceMovie(interval, currentTime), 6 PostDisplay, 7 PreDisplay, 8 RefreshPlatform).

| class | vtable | slots | other vtables (offset: address, slots) |
|---|---|---|---|
| ActivateHandler | 0x141935388 | 9 |  |
| ActiveEffect | 0x1418f5b98 | 25 |  |
| ActiveEffect::ForEachHitEffectVisitor | 0x1418f5b80 | 2 |  |
| ActiveEffectReferenceEffectController | 0x1418f5a60 | 35 |  |
| Actor | 0x14191b548 | 296 | 32: 0x14191be90, 2, 48: 0x14191bea8, 2, 56: 0x14191bec0, 19, 160: 0x14191bf60, 12, 184: 0x14191bfc8, 9, 192: 0x14191c018, 22, 208: 0x14191c0d0, 2, 216: 0x14191c0e8, 2, 224: 0x14191c100, 2 |
| ActorMagicCaster | 0x1418f6150 | 30 | 72: 0x1418f6248, 20, 96: 0x1418f62f0, 2 |
| ActorMover | 0x14192e3d8 | 4 |  |
| ActorValueInfo | 0x1418c2708 | 59 | 32: 0x1418c28e8, 6, 48: 0x1418c2920, 4, 64: 0x1418c2948, 7 |
| ActorValueOwner | 0x14185e6d0 | 9 |  |
| AttackBlockHandler | 0x141935258 | 9 |  |
| AutoMoveHandler | 0x1419353d8 | 7 |  |
| BGSHeadPart | 0x1418554a8 | 59 | 32: 0x141855688, 6, 48: 0x1418556c0, 7 |
| Character | 0x141923258 | 298 | 32: 0x141923bb0, 2, 48: 0x141923bc8, 2, 56: 0x141923be0, 19, 160: 0x141923c80, 12, 184: 0x141923ce8, 9, 192: 0x141923d38, 22, 208: 0x141923df0, 2, 216: 0x141923e08, 2, 224: 0x141923e20, 2 |
| EffectSetting | 0x1417e1468 | 59 | 32: 0x1417e1648, 6, 48: 0x1417e1680, 5, 64: 0x1417e16b0, 6 |
| EffectSettingCollection | 0x1417e1850 | 1 |  |
| EnchantmentItem | 0x1417e1aa0 | 113 | 48: 0x1417e1e30, 6, 64: 0x1417e1e68, 6 |
| FirstPersonState | 0x14196d8f0 | 9 | 32: 0x14196d940, 7 |
| JumpHandler | 0x1419354a8 | 7 |  |
| LookHandler | 0x141935150 | 7 |  |
| MagicCaster | 0x1418f8780 | 29 |  |
| MagicCaster::PostCreationCallback | 0x1418f8768 | 2 |  |
| MagicItem | 0x1417e2ea0 | 113 | 48: 0x1417e3230, 6, 64: 0x1417e3268, 6 |
| MagicItem::PreloadableVisitor | 0x1417e2e88 | 2 |  |
| MagicItemFindFunctor | 0x1417e32b8 | 3 |  |
| MagicItemFindKeywordFunctor | 0x1417e32d8 | 3 |  |
| MagicItemTraversalFunctor | 0x1417e32a0 | 2 |  |
| MagicTarget | 0x1417e9940 | 12 |  |
| MagicTarget::DispelFromBoundObject | 0x1418f8d30 | 2 |  |
| MagicTarget::ForEachActiveEffectVisitor | 0x141840138 | 2 |  |
| MagicTarget::IPostCreationModification | 0x1418f6660 | 2 |  |
| MovementHandler | 0x1419351c8 | 7 |  |
| PlayerCamera | 0x14196d980 | 3 |  |
| PlayerCameraTransitionState | 0x14196db20 | 9 |  |
| PlayerCharacter | 0x1419296c0 | 303 | 32: 0x14192a040, 2, 48: 0x14192a058, 2, 56: 0x14192a070, 19, 160: 0x14192a110, 12, 184: 0x14192a178, 9, 192: 0x14192a1c8, 22, 208: 0x14192a280, 2, 216: 0x14192a298, 2, 224: 0x14192a2b0, 2, 696: 0x14192a2c8, 2, 704: 0x14192a2e0, 2, 712: 0x14192a2f8, 2, 720: 0x14192a310, 2, 728: 0x14192a328, 2 |
| PlayerControls | 0x141935070 | 2 | 8: 0x141935088, 2, 16: 0x1419350a0, 2, 24: 0x1419350b8, 2 |
| PlayerInputHandler | 0x1418ecbc8 | 7 |  |
| ReadyWeaponHandler | 0x141935348 | 7 |  |
| RunHandler | 0x141935458 | 9 |  |
| ShoutHandler | 0x141935528 | 7 |  |
| SneakHandler | 0x1419354e8 | 7 |  |
| SpellItem | 0x1417e5a08 | 113 | 48: 0x1417e5d98, 6, 64: 0x1417e5dd0, 6, 144: 0x1417e5e08, 6, 160: 0x1417e5e40, 5, 176: 0x1417e5e70, 4 |
| SprintHandler | 0x141935208 | 9 |  |
| TESActorBase | 0x14185e720 | 87 | 48: 0x14185e9e0, 9, 136: 0x14185ea30, 4, 160: 0x14185ea58, 4, 176: 0x14185ea80, 4, 216: 0x14185eaa8, 6, 232: 0x14185eae0, 9, 240: 0x14185eb30, 4, 256: 0x14185eb58, 4, 272: 0x14185eb80, 6, 296: 0x14185ebb8, 4, 312: 0x14185ebe0, 4 |
| TESActorBaseData | 0x1417f8b98 | 9 |  |
| TESCamera | 0x1418ebbe0 | 3 |  |
| TESCameraState | 0x141806460 | 9 |  |
| TESForm | 0x1417f9f80 | 59 |  |
| TESNPC | 0x14185ec20 | 87 | 48: 0x14185eee0, 9, 136: 0x14185ef30, 4, 160: 0x14185ef58, 4, 176: 0x14185ef80, 4, 216: 0x14185efa8, 6, 232: 0x14185efe0, 9, 240: 0x14185f030, 4, 256: 0x14185f058, 4, 272: 0x14185f080, 6, 296: 0x14185f0b8, 4, 312: 0x14185f0e0, 4, 336: 0x14185f108, 4, 352: 0x14185f130, 4, 392: 0x14185f158, 2 |
| TESObjectREFR | 0x1418277c0 | 162 | 32: 0x141827cd8, 2, 48: 0x141827cf0, 2, 56: 0x141827d08, 19 |
| TESRace | 0x141861d68 | 59 | 32: 0x141861f48, 6, 48: 0x141861f80, 4, 64: 0x141861fa8, 4, 80: 0x141861fd0, 4, 96: 0x141861ff8, 4, 112: 0x141862020, 6, 136: 0x141862058, 4 |
| TESShout | 0x141851e50 | 59 | 32: 0x141852030, 6, 48: 0x141852068, 5, 64: 0x141852098, 6, 80: 0x1418520d0, 4 |
| TESWordOfPower | 0x141852700 | 59 | 32: 0x1418528e0, 6 |
| ThirdPersonState | 0x1418ecc08 | 16 | 32: 0x1418ecc90, 7 |
| TogglePOVHandler | 0x141935568 | 9 |  |
| ToggleRunHandler | 0x141935418 | 7 |  |

## Animation (the behavior graph) (224 classes, 5 template classes left out)

From the MSVC RTTI of `SkyrimSE.exe`: 7,831 type descriptors (`.?AV...@@` in `.data`), 8,457 complete object locators and 7,159 classes with a vtable in `.rdata`. Here the classes of the inn's systems with their primary vtable (the one at offset 0 of the object) and how many virtual functions follow it before the next vtable (the count includes the slots of the base classes; a class's own slots come last). A secondary vtable (a base at another offset) is listed with that offset. Template classes (`BSTEventSink<...>`, `ConcreteFormFactory<...>`, the behavior tree's `CombatBehaviorTreeNodeObject<...>`) are left out; their count is in the system's heading. The vtable's slot k holds the address of the virtual function, so a function is found as the vtable's address plus 8 k, and `procedure_pseudo_code` on that address gives its code.

The layouts to read a slot by name: CommonLibSSE-NG's headers declare each class's virtual functions in vtable order (`IMenu`: 0 destructor, 1 Accept(CallbackProcessor), 2 PostCreate, 3 Unk_03, 4 ProcessMessage(UIMessage), 5 AdvanceMovie(interval, currentTime), 6 PostDisplay, 7 PreDisplay, 8 RefreshPlatform).

| class | vtable | slots | other vtables (offset: address, slots) |
|---|---|---|---|
| AnimationFileManagerSingleton | 0x141a09890 | 6 |  |
| BSAnimGraphVisit::BShkbVisitor | 0x14183dd68 | 2 |  |
| BSAnimNote | 0x141a5c558 | 38 |  |
| BSAnimNoteReceiver | 0x141803418 | 2 |  |
| BSAnimNotes | 0x141a5c388 | 37 |  |
| BSAnimationGraphChannel | 0x141802f70 | 3 |  |
| BSAnimationGraphLoadScrapper | 0x141a06338 | 2 |  |
| BSAnimationGraphManager | 0x141a05798 | 2 |  |
| BSBoneLODExtraData | 0x141a72468 | 39 |  |
| BSBoneSwitchGenerator | 0x141a03348 | 28 |  |
| BSBoneSwitchGeneratorBoneData | 0x141a03520 | 4 |  |
| BSComputeAddBoneAnimModifier | 0x141a03ca8 | 25 |  |
| BSCyclicBlendTransitionGenerator | 0x141a03548 | 28 |  |
| BSDecomposeVectorModifier | 0x141a03de8 | 25 |  |
| BSDirectAtModifier | 0x141a03eb8 | 25 |  |
| BSDirectAtModifierInterface | 0x14193bb38 | 2 |  |
| BSDistTriggerModifier | 0x141a03fa0 | 25 |  |
| BSEventEveryNEventsModifier | 0x141a04088 | 25 |  |
| BSEventOnDeactivateModifier | 0x141a04280 | 25 |  |
| BSEventOnFalseToTrueModifier | 0x141a04380 | 25 |  |
| BSGetTimeStepModifier | 0x141a04478 | 25 |  |
| BSInterpValueModifier | 0x141a04548 | 25 |  |
| BSIsActiveModifier | 0x141a04618 | 25 |  |
| BSLimbIKModifier | 0x141a046e8 | 25 |  |
| BSLimbIKModifierCastInfo | 0x1419fb7d0 | 1 |  |
| BSLimbIKModifierUtility | 0x1418eab58 | 4 |  |
| BSLimbIKModifierUtilityCastInfo | 0x1418eab48 | 1 |  |
| BSLookAtModifier | 0x141a04898 | 25 |  |
| BSModifyOnceModifier | 0x141a04b10 | 25 |  |
| BSOffsetAnimationGenerator | 0x141a038e8 | 28 |  |
| BSPassByTargetTriggerModifier | 0x141a04c18 | 25 |  |
| BSPassByTargetTriggerModifierInterface | 0x14193bb78 | 4 |  |
| BSRagdollContactListenerModifier | 0x141a03038 | 25 | 80: 0x141a03108, 7 |
| BSRagdollContactListenerModifierInterface | 0x14193bf18 | 2 |  |
| BSSynchronizedClipGenerator | 0x141a02df8 | 28 |  |
| BSSynchronizedClipGenerator::hkbDefaultSynchronizedScene | 0x141a02da0 | 10 |  |
| BSSynchronizedClipGenerator::hkbSynchronizedAnimationScene | 0x1418ea7b8 | 10 |  |
| BSSynchronizedClipGeneratorUtils::FindEventFunctor | 0x141a04fd0 | 2 |  |
| BSTimerModifier | 0x141a04df8 | 25 |  |
| BSTweenerModifier | 0x141a04ec8 | 25 |  |
| BShkbAnimationGraph | 0x141a07d78 | 14 |  |
| BShkbHkxDB::DBData | 0x141a05f70 | 15 |  |
| BShkbHkxDB::ProjectDBData | 0x141a06028 | 15 |  |
| BShkbHkxDB::QueuedHandles | 0x141a06168 | 19 | 56: 0x141a06208, 3 |
| BShkbHkxDB::StreamAdaptor | 0x141a06228 | 13 |  |
| BShkbUtils::GraphInspectionFunctor | 0x141a08db8 | 7 |  |
| BShkbUtils::ProspectiveEventClipAddingFunctor | 0x141a08ee0 | 7 |  |
| BShkbUtils::SaveDataRestoreFunctor | 0x141a12668 | 7 |  |
| BSiStateTaggingGenerator | 0x141a03b98 | 28 |  |
| BSiStateTaggingUtils::BSiStateTaggingStateListener | 0x141a12bc8 | 7 |  |
| ExtraAnimGraphManager | 0x1417ed230 | 3 |  |
| hkbAnimationBindingSet | 0x1419c0f98 | 3 |  |
| hkbAnimationBindingWithTriggers | 0x1419e3f58 | 3 |  |
| hkbAssetLoader | 0x141a08df8 | 5 |  |
| hkbAttachmentFixupSceneModifier | 0x1419e40d0 | 4 |  |
| hkbAttachmentModifier | 0x1419dec30 | 25 |  |
| hkbAttachmentSceneModifier | 0x1419e40a8 | 4 |  |
| hkbAttachmentSetup | 0x1419dd2f8 | 3 |  |
| hkbAttributeModifier | 0x1419ded30 | 25 |  |
| hkbAuxiliaryNodeInfo | 0x141a95a90 | 3 |  |
| hkbBehaviorClient | 0x141a97e60 | 3 | 16: 0x141a97e80, 2 |
| hkbBehaviorEventsInfo | 0x141a95a10 | 3 |  |
| hkbBehaviorGraph | 0x1419c09f0 | 28 |  |
| hkbBehaviorGraph::GlobalTransitionData | 0x1419c09d0 | 3 |  |
| hkbBehaviorGraphData | 0x1419dd7c8 | 3 |  |
| hkbBehaviorGraphInternalState | 0x1419dd818 | 3 |  |
| hkbBehaviorGraphInternalStateInfo | 0x141a95ab0 | 3 |  |
| hkbBehaviorGraphStringData | 0x1419dd7a8 | 3 |  |
| hkbBehaviorInfo | 0x141a959f0 | 3 |  |
| hkbBehaviorReferenceGenerator | 0x1419ddfc0 | 28 |  |
| hkbBindable | 0x1419c07d8 | 4 |  |
| hkbBindable::CacheBindablesCollector | 0x1419c1180 | 2 |  |
| hkbBindableCollector | 0x1419c1168 | 2 |  |
| hkbBlenderGenerator | 0x1419de110 | 28 |  |
| hkbBlenderGeneratorChild | 0x1419de0e8 | 4 |  |
| hkbBlenderGeneratorInternalState | 0x1419de2c0 | 3 |  |
| hkbBlendingTransitionEffect | 0x1419e2d88 | 39 |  |
| hkbBlendingTransitionEffectInternalState | 0x1419e2f20 | 3 |  |
| hkbBoneIndexArray | 0x1419dd8f8 | 4 |  |
| hkbBoneWeightArray | 0x1419dd950 | 4 |  |
| hkbBoolVariableSequencedData | 0x1419e2610 | 4 |  |
| hkbCameraShakeEventPayload | 0x141a95728 | 3 |  |
| hkbCharacter | 0x1419c0fb8 | 5 |  |
| hkbCharacterAddedInfo | 0x141a95970 | 3 |  |
| hkbCharacterControlCommand | 0x141a958b0 | 3 |  |
| hkbCharacterControllerModifier | 0x1419deec8 | 25 |  |
| hkbCharacterControllerModifierInternalState | 0x1419df028 | 3 |  |
| hkbCharacterControllerSceneModifier | 0x1419e4120 | 4 |  |
| hkbCharacterData | 0x1419e4188 | 3 |  |
| hkbCharacterInfo | 0x141a95990 | 3 |  |
| hkbCharacterSetup | 0x1419e4148 | 3 |  |
| hkbCharacterSkinInfo | 0x141a959d0 | 3 |  |
| hkbCharacterSteppedInfo | 0x141a959b0 | 3 |  |
| hkbCharacterStringData | 0x1419dd9c8 | 3 |  |
| hkbClientCharacterState | 0x141a97e40 | 3 |  |
| hkbClipGenerator | 0x1419e3418 | 28 |  |
| hkbClipGeneratorInternalState | 0x1419de470 | 3 |  |
| hkbClipTriggerArray | 0x1419de330 | 3 |  |
| hkbClosestLocalFrameCollector | 0x1419e54f8 | 4 |  |
| hkbCombineTransformsModifier | 0x1419df0a8 | 25 |  |
| hkbCombineTransformsModifierInternalState | 0x1419df1b8 | 3 |  |
| hkbCompiledExpressionSet | 0x1419ddb90 | 3 |  |
| hkbComputeDirectionModifier | 0x1419df238 | 25 |  |
| hkbComputeDirectionModifierInternalState | 0x1419df348 | 3 |  |
| hkbComputeRotationFromAxisAngleModifier | 0x1419df3c8 | 25 |  |
| hkbComputeRotationFromAxisAngleModifierInternalState | 0x1419df4f0 | 3 |  |
| hkbComputeRotationToTargetModifier | 0x1419df580 | 25 |  |
| hkbComputeRotationToTargetModifierInternalState | 0x1419df6a0 | 3 |  |
| hkbCondition | 0x1419ddb68 | 4 |  |
| hkbDampingModifier | 0x1419df728 | 25 |  |
| hkbDampingModifierInternalState | 0x1419df828 | 3 |  |
| hkbDefaultRaycastInterface | 0x1419e5688 | 3 | 16: 0x1419e56a8, 3 |
| hkbDelayedModifier | 0x1419df960 | 25 |  |
| hkbDelayedModifierInternalState | 0x1419dfa60 | 3 |  |
| hkbDetectCloseToGroundModifier | 0x1419dfac8 | 25 |  |
| hkbDetectCloseToGroundModifierInternalState | 0x1419dfbd8 | 3 |  |
| hkbEvaluateExpressionModifier | 0x1419dfc78 | 25 |  |
| hkbEvaluateExpressionModifierInternalState | 0x1419dfe58 | 3 |  |
| hkbEvaluateHandleModifier | 0x1419dfed8 | 25 |  |
| hkbEventDrivenModifier | 0x1419e0040 | 25 |  |
| hkbEventDrivenModifierInternalState | 0x1419e0140 | 3 |  |
| hkbEventPayload | 0x1419dd378 | 3 |  |
| hkbEventPayloadList | 0x1419dd478 | 3 |  |
| hkbEventRaisedInfo | 0x141a95a30 | 3 |  |
| hkbEventRangeDataArray | 0x1419e01b0 | 3 |  |
| hkbEventSequencedData | 0x1419e25c0 | 4 |  |
| hkbEventsFromRangeModifier | 0x1419e01d0 | 25 |  |
| hkbEventsFromRangeModifierInternalState | 0x1419e0340 | 3 |  |
| hkbExpressionCondition | 0x1419ddbb0 | 4 |  |
| hkbExpressionDataArray | 0x1419dfc58 | 3 |  |
| hkbExtractRagdollPoseModifier | 0x1419e1538 | 25 |  |
| hkbFootIkControlsModifier | 0x1419e03e8 | 25 |  |
| hkbFootIkDriver | 0x1419c0f18 | 3 |  |
| hkbFootIkDriverInfo | 0x1419dd9e8 | 3 |  |
| hkbFootIkModifier | 0x1419e0558 | 25 |  |
| hkbFootIkSceneModifier | 0x1419c1048 | 4 |  |
| hkbGenerator | 0x1419c08c0 | 28 |  |
| hkbGeneratorTransitionEffect | 0x1419e2fa0 | 33 |  |
| hkbGeneratorTransitionEffectInternalState | 0x1419e30f0 | 3 |  |
| hkbGetHandleOnBoneModifier | 0x1419e0720 | 25 |  |
| hkbGetUpModifier | 0x1419e0830 | 25 |  |
| hkbGetUpModifierInternalState | 0x1419e0930 | 3 |  |
| hkbGetWorldFromModelModifier | 0x1419e0990 | 25 |  |
| hkbGetWorldFromModelModifierInternalState | 0x1419e0aa0 | 3 |  |
| hkbHandIkControlsModifier | 0x1419e0b58 | 25 |  |
| hkbHandIkDriver | 0x1419e3f78 | 3 |  |
| hkbHandIkDriverInfo | 0x1419dda08 | 3 |  |
| hkbHandIkFixupSceneModifier | 0x1419c1098 | 4 |  |
| hkbHandIkModifier | 0x1419e0cb0 | 25 |  |
| hkbHandIkSceneModifier | 0x1419c1070 | 4 |  |
| hkbHandle | 0x1419dd4b8 | 3 |  |
| hkbIntEventPayload | 0x1419dd3b8 | 3 |  |
| hkbIntVariableSequencedData | 0x1419e2638 | 4 |  |
| hkbKeyframeBonesModifier | 0x1419e1648 | 25 |  |
| hkbLinkedSymbolInfo | 0x141a95a70 | 3 |  |
| hkbLookAtModifier | 0x1419e0ef8 | 25 |  |
| hkbLookAtModifierInternalState | 0x1419e0ff8 | 3 |  |
| hkbManualSelectorGenerator | 0x1419de528 | 28 |  |
| hkbManualSelectorGeneratorInternalState | 0x1419de650 | 3 |  |
| hkbMirrorModifier | 0x1419e1058 | 25 |  |
| hkbMirroredSkeletonInfo | 0x1419dda28 | 3 |  |
| hkbModifier | 0x1419de6c8 | 25 |  |
| hkbModifierGenerator | 0x1419de798 | 28 |  |
| hkbModifierList | 0x1419e0e00 | 25 |  |
| hkbModifierWrapper | 0x1419df890 | 25 |  |
| hkbMoveCharacterModifier | 0x1419e1158 | 25 |  |
| hkbMoveCharacterModifierInternalState | 0x1419e1268 | 3 |  |
| hkbNamedEventPayload | 0x1419dd3f8 | 3 |  |
| hkbNamedIntEventPayload | 0x1419dd438 | 3 |  |
| hkbNamedRealEventPayload | 0x1419dd418 | 3 |  |
| hkbNamedStringEventPayload | 0x1419dd458 | 3 |  |
| hkbNode | 0x1419c0800 | 23 |  |
| hkbNode::BoundVariablesCollector | 0x1419c1198 | 2 |  |
| hkbNodeInternalStateInfo | 0x1419c0ad8 | 3 |  |
| hkbParticleSystemEventPayload | 0x141a95788 | 3 |  |
| hkbPoseMatchingGenerator | 0x1419de8b0 | 28 |  |
| hkbPoseMatchingGeneratorInternalState | 0x1419de9f0 | 3 |  |
| hkbPoweredRagdollControlsModifier | 0x1419e17e8 | 25 |  |
| hkbProjectData | 0x1419e4168 | 3 |  |
| hkbProjectStringData | 0x1419dd5e8 | 3 |  |
| hkbProxyModifier | 0x1419e12d8 | 25 |  |
| hkbRagdollDriver | 0x1419c07b0 | 3 |  |
| hkbRagdollSceneModifier | 0x1419e40f8 | 4 |  |
| hkbRaiseEventCommand | 0x141a958d0 | 3 |  |
| hkbRealEventPayload | 0x1419dd398 | 3 |  |
| hkbRealVariableSequencedData | 0x1419e25e8 | 4 |  |
| hkbReferencePoseGenerator | 0x1419dea60 | 28 |  |
| hkbRegisteredGenerator | 0x1419de4d0 | 4 |  |
| hkbRigidBodyRagdollControlsModifier | 0x1419e1948 | 25 |  |
| hkbRotateCharacterModifier | 0x1419e1aa8 | 25 |  |
| hkbRotateCharacterModifierInternalState | 0x1419e1bb8 | 3 |  |
| hkbSceneModifier | 0x1419c1020 | 4 |  |
| hkbSenseHandleModifier | 0x1419e1c30 | 25 |  |
| hkbSequence | 0x1419e2418 | 25 |  |
| hkbSequenceInternalState | 0x1419e2508 | 3 |  |
| hkbSequenceStringData | 0x1419e23f8 | 3 |  |
| hkbSequencedData | 0x1419e2598 | 4 |  |
| hkbSetBehaviorCommand | 0x141a95930 | 3 |  |
| hkbSetLocalTimeOfClipGeneratorCommand | 0x141a95910 | 3 |  |
| hkbSetNodePropertyCommand | 0x141a95950 | 3 |  |
| hkbSetWordVariableCommand | 0x141a958f0 | 3 |  |
| hkbSetWorldFromModelModifier | 0x1419e1de0 | 25 |  |
| hkbSimulationControlCommand | 0x141a95890 | 3 |  |
| hkbSimulationStateInfo | 0x141a95a50 | 3 |  |
| hkbStateChooser | 0x141a95810 | 4 |  |
| hkbStateListener | 0x1419e28b8 | 7 |  |
| hkbStateMachine | 0x1419e37f0 | 28 |  |
| hkbStateMachine::EventPropertyArray | 0x1419e2948 | 3 |  |
| hkbStateMachine::StateInfo | 0x1419e2968 | 4 |  |
| hkbStateMachine::TransitionInfoArray | 0x1419e2928 | 3 |  |
| hkbStateMachineInternalState | 0x1419e2d28 | 3 |  |
| hkbStringCondition | 0x1419ddc08 | 4 |  |
| hkbStringEventPayload | 0x1419dd3d8 | 3 |  |
| hkbSymbolIdMap | 0x1419e56d8 | 3 |  |
| hkbTestStateChooser | 0x141a95838 | 4 |  |
| hkbTimerModifier | 0x1419e1ef0 | 25 |  |
| hkbTimerModifierInternalState | 0x1419e1ff0 | 3 |  |
| hkbTransformVectorModifier | 0x1419e2050 | 25 |  |
| hkbTransformVectorModifierInternalState | 0x1419e2160 | 3 |  |
| hkbTransitionEffect | 0x1419dd4d8 | 33 |  |
| hkbTwistModifier | 0x1419e21d8 | 25 |  |
| hkbVariableBindingSet | 0x1419dd498 | 3 |  |
| hkbVariableValueSet | 0x1419c09a8 | 3 |  |
| hkbWorld | 0x1419c1000 | 3 |  |

## Combat (118 classes, 265 template classes left out)

From the MSVC RTTI of `SkyrimSE.exe`: 7,831 type descriptors (`.?AV...@@` in `.data`), 8,457 complete object locators and 7,159 classes with a vtable in `.rdata`. Here the classes of the inn's systems with their primary vtable (the one at offset 0 of the object) and how many virtual functions follow it before the next vtable (the count includes the slots of the base classes; a class's own slots come last). A secondary vtable (a base at another offset) is listed with that offset. Template classes (`BSTEventSink<...>`, `ConcreteFormFactory<...>`, the behavior tree's `CombatBehaviorTreeNodeObject<...>`) are left out; their count is in the system's heading. The vtable's slot k holds the address of the virtual function, so a function is found as the vtable's address plus 8 k, and `procedure_pseudo_code` on that address gives its code.

The layouts to read a slot by name: CommonLibSSE-NG's headers declare each class's virtual functions in vtable order (`IMenu`: 0 destructor, 1 Accept(CallbackProcessor), 2 PostCreate, 3 Unk_03, 4 ProcessMessage(UIMessage), 5 AdvanceMovie(interval, currentTime), 6 PostDisplay, 7 PreDisplay, 8 RefreshPlatform).

| class | vtable | slots | other vtables (offset: address, slots) |
|---|---|---|---|
| ArrowProjectile | 0x14193c248 | 196 | 32: 0x14193c870, 2, 48: 0x14193c888, 2, 56: 0x14193c8a0, 19 |
| BGSAttackData | 0x1418c42e0 | 2 |  |
| BGSAttackDataForm | 0x1417f76f0 | 4 |  |
| BGSAttackDataMap | 0x1418c42f8 | 2 |  |
| BarrierProjectile | 0x14193cb90 | 194 | 32: 0x14193d1a8, 2, 48: 0x14193d1c0, 2, 56: 0x14193d1d8, 19 |
| BeamProjectile | 0x14193d630 | 194 | 32: 0x14193dc48, 2, 48: 0x14193dc60, 2, 56: 0x14193dc78, 19, 480: 0x14193dd18, 2 |
| CombatAimController | 0x141943e28 | 11 |  |
| CombatAimControllerBase | 0x141944600 | 5 |  |
| CombatApproachTargetSpeedController | 0x14195a878 | 6 |  |
| CombatArea | 0x141944790 | 12 |  |
| CombatAreaHoldPosition | 0x141944930 | 12 |  |
| CombatAreaRadius | 0x1419447f8 | 12 |  |
| CombatAreaReference | 0x141944860 | 12 |  |
| CombatAreaStandard | 0x1419448c8 | 12 |  |
| CombatBehaviorResource | 0x1419570e8 | 2 |  |
| CombatBehaviorTree | 0x1419574d8 | 1 |  |
| CombatBehaviorTreeAcquireWeapon | 0x1419577b0 | 1 |  |
| CombatBehaviorTreeAction | 0x141958320 | 1 |  |
| CombatBehaviorTreeActionEquipmentSelector | 0x141958348 | 1 |  |
| CombatBehaviorTreeBlock | 0x141959648 | 1 |  |
| CombatBehaviorTreeCheckUnreachableTarget | 0x141962668 | 1 |  |
| CombatBehaviorTreeCloseMovement | 0x141959d40 | 1 |  |
| CombatBehaviorTreeCombat | 0x1419574f8 | 1 |  |
| CombatBehaviorTreeDodgeThreat | 0x141959238 | 1 |  |
| CombatBehaviorTreeExitWater | 0x1419628a8 | 1 |  |
| CombatBehaviorTreeFindAttackLocation | 0x14195b6e0 | 1 |  |
| CombatBehaviorTreeFlankingMovement | 0x14195ca48 | 1 |  |
| CombatBehaviorTreeFlee | 0x14195de48 | 1 |  |
| CombatBehaviorTreeFlight | 0x14195fa40 | 1 |  |
| CombatBehaviorTreeHide | 0x14195e218 | 1 |  |
| CombatBehaviorTreeLinkNode | 0x141957480 | 10 |  |
| CombatBehaviorTreeLowCombat | 0x1419611e8 | 1 |  |
| CombatBehaviorTreeMagic | 0x1419615f8 | 1 |  |
| CombatBehaviorTreeMelee | 0x1419621d8 | 1 |  |
| CombatBehaviorTreeMovement | 0x141963b90 | 1 |  |
| CombatBehaviorTreeNode | 0x141957700 | 10 |  |
| CombatBehaviorTreeRanged | 0x1418ecda0 | 1 |  |
| CombatBehaviorTreeRangedMovement | 0x141963fa8 | 1 |  |
| CombatBehaviorTreeReturnToCombatArea | 0x141962690 | 1 |  |
| CombatBehaviorTreeRootNode | 0x141957428 | 10 |  |
| CombatBehaviorTreeSearch | 0x141964638 | 1 |  |
| CombatBehaviorTreeShout | 0x1419660a0 | 1 |  |
| CombatBehaviorTreeUseCover | 0x141966578 | 1 |  |
| CombatBehaviorTreeUsePotion | 0x1419672c8 | 1 |  |
| CombatBehaviorTreeWrapperNode | 0x141958650 | 10 |  |
| CombatBlackboardKeyBase | 0x141944f40 | 7 |  |
| CombatCoverLocation | 0x1419452d8 | 5 |  |
| CombatCoverSearch | 0x141945278 | 5 |  |
| CombatCoverSearchDebugData | 0x141945308 | 5 |  |
| CombatCoverSearchResult | 0x1419452a8 | 5 |  |
| CombatDisableActionController | 0x141962d30 | 5 |  |
| CombatDisableAimController | 0x141943fa8 | 11 |  |
| CombatFlankingSearchData | 0x14195ca70 | 5 |  |
| CombatGroupDetectionListener | 0x1419468f8 | 6 |  |
| CombatInventoryItem | 0x141947468 | 21 |  |
| CombatInventoryItemComposite | 0x141947518 | 21 |  |
| CombatInventoryItemMagic | 0x141948200 | 23 |  |
| CombatInventoryItemMelee | 0x1419475c8 | 21 |  |
| CombatInventoryItemOneHandedBlock | 0x1419477d8 | 21 |  |
| CombatInventoryItemPotion | 0x141949e40 | 23 |  |
| CombatInventoryItemRanged | 0x141947678 | 21 |  |
| CombatInventoryItemScroll | 0x141949f60 | 23 |  |
| CombatInventoryItemShield | 0x141947728 | 21 |  |
| CombatInventoryItemShout | 0x141949c20 | 23 |  |
| CombatInventoryItemStaff | 0x141949d20 | 23 |  |
| CombatInventoryItemTorch | 0x141947888 | 21 |  |
| CombatMagicCaster | 0x141953718 | 14 |  |
| CombatMagicCasterArmor | 0x14194bcf0 | 14 |  |
| CombatMagicCasterBoundItem | 0x14194bb78 | 14 |  |
| CombatMagicCasterCloak | 0x14194b6f0 | 14 |  |
| CombatMagicCasterDisarm | 0x14194b558 | 14 |  |
| CombatMagicCasterInvisibility | 0x14194ba00 | 14 |  |
| CombatMagicCasterLight | 0x14194b868 | 14 |  |
| CombatMagicCasterOffensive | 0x14194acc0 | 14 |  |
| CombatMagicCasterParalyze | 0x14194c200 | 14 |  |
| CombatMagicCasterReanimate | 0x1419538e0 | 14 |  |
| CombatMagicCasterRestore | 0x14194b0b0 | 14 |  |
| CombatMagicCasterScript | 0x14194c398 | 14 |  |
| CombatMagicCasterStagger | 0x14194b420 | 14 |  |
| CombatMagicCasterSummon | 0x14194b2a8 | 14 |  |
| CombatMagicCasterTargetEffect | 0x14194be88 | 14 |  |
| CombatMagicCasterWard | 0x14194ae58 | 14 |  |
| CombatMagicItemData | 0x1419536e8 | 2 |  |
| CombatMagicItemSkillChecker | 0x141953700 | 2 |  |
| CombatMeleeAimController | 0x141943ee8 | 11 |  |
| CombatNavmeshSearch | 0x1419685a8 | 8 |  |
| CombatObject | 0x1419445d0 | 5 |  |
| CombatPath | 0x1419547a0 | 13 |  |
| CombatPathBuilder | 0x141968530 | 4 |  |
| CombatPathBuilderOpen | 0x141968580 | 4 |  |
| CombatPathBuilderStandard | 0x141968558 | 4 |  |
| CombatPathSpeedController | 0x14195a820 | 6 |  |
| CombatPathingDebugData | 0x1419690c8 | 5 |  |
| CombatPathingRequest | 0x141954488 | 13 |  |
| CombatPathingRequestAdapter | 0x141968878 | 13 |  |
| CombatPathingRequestMultiGoal | 0x141968968 | 13 |  |
| CombatPathingRequestStandard | 0x141968808 | 13 |  |
| CombatProjectileAimController | 0x141943f48 | 11 |  |
| CombatSearchLockData | 0x141964b18 | 7 |  |
| CombatTargetLocation | 0x1419546c8 | 5 |  |
| CombatTargetLocationSearch | 0x1419546f8 | 5 |  |
| CombatTargetLocationSearchResult | 0x141954728 | 5 |  |
| CombatTargetSelector | 0x141955910 | 7 |  |
| CombatTargetSelectorFixed | 0x141955990 | 7 |  |
| CombatTargetSelectorStandard | 0x141955950 | 7 |  |
| CombatThreat | 0x141955f18 | 5 |  |
| CombatTrackTargetAimController | 0x141943e88 | 11 |  |
| ConeProjectile | 0x14193dea0 | 195 | 32: 0x14193e4c0, 2, 48: 0x14193e4d8, 2, 56: 0x14193e4f0, 19 |
| DetectionState | 0x141937990 | 2 |  |
| ExtraCombatStyle | 0x1417ea3b8 | 3 |  |
| FlameProjectile | 0x14193f360 | 194 | 32: 0x14193f978, 2, 48: 0x14193f990, 2, 56: 0x14193f9a8, 19 |
| GrenadeProjectile | 0x14193fb90 | 194 | 32: 0x1419401a8, 2, 48: 0x1419401c0, 2, 56: 0x1419401d8, 19 |
| MissileProjectile | 0x141940e58 | 196 | 32: 0x141941480, 2, 48: 0x141941498, 2, 56: 0x1419414b0, 19 |
| Projectile | 0x141942a10 | 194 | 32: 0x141943028, 2, 48: 0x141943040, 2, 56: 0x141943058, 19 |
| Projectile::LaunchData | 0x1417f63b0 | 1 |  |
| ProjectilePickCache | 0x1419429f8 | 2 |  |
| TESCombatStyle | 0x141810538 | 59 |  |
| bhkCollisionObject | 0x141828388 | 49 |  |

## Dialogue, scenes, packages and AI (188 classes, 1 template classes left out)

From the MSVC RTTI of `SkyrimSE.exe`: 7,831 type descriptors (`.?AV...@@` in `.data`), 8,457 complete object locators and 7,159 classes with a vtable in `.rdata`. Here the classes of the inn's systems with their primary vtable (the one at offset 0 of the object) and how many virtual functions follow it before the next vtable (the count includes the slots of the base classes; a class's own slots come last). A secondary vtable (a base at another offset) is listed with that offset. Template classes (`BSTEventSink<...>`, `ConcreteFormFactory<...>`, the behavior tree's `CombatBehaviorTreeNodeObject<...>`) are left out; their count is in the system's heading. The vtable's slot k holds the address of the virtual function, so a function is found as the vtable's address plus 8 k, and `procedure_pseudo_code` on that address gives its code.

The layouts to read a slot by name: CommonLibSSE-NG's headers declare each class's virtual functions in vtable order (`IMenu`: 0 destructor, 1 Accept(CallbackProcessor), 2 PostCreate, 3 Unk_03, 4 ProcessMessage(UIMessage), 5 AdvanceMovie(interval, currentTime), 6 PostDisplay, 7 PreDisplay, 8 RefreshPlatform).

| class | vtable | slots | other vtables (offset: address, slots) |
|---|---|---|---|
| ActorPackageData | 0x1418d5d38 | 9 |  |
| BGSBaseAlias | 0x1418560f8 | 4 |  |
| BGSDialogueBranch | 0x141853b18 | 59 |  |
| BGSIdleCollection | 0x1417f7ee8 | 4 |  |
| BGSIdleMarker | 0x1418558f8 | 83 | 48: 0x141855b98, 7, 88: 0x141855bd8, 4 |
| BGSPackageDataBool | 0x1418c4770 | 13 |  |
| BGSPackageDataFloat | 0x1418c48d0 | 14 |  |
| BGSPackageDataInt | 0x1418c4a38 | 14 |  |
| BGSPackageDataLocation | 0x1418c4e80 | 5 | 8: 0x1418c4eb0, 13 |
| BGSPackageDataLocationWrapper | 0x1418c5648 | 4 | 8: 0x1418c5670, 13 |
| BGSPackageDataObjectList | 0x1418c5718 | 12 | 8: 0x1418c5780, 13 |
| BGSPackageDataRef | 0x1418c5de0 | 13 | 8: 0x1418c5e50, 13 |
| BGSPackageDataRefOLD | 0x1418c4c68 | 13 | 8: 0x1418c4cd8, 13 |
| BGSPackageDataTargetSelector | 0x1418c4f98 | 14 |  |
| BGSPackageDataTopic | 0x1418c60e8 | 13 |  |
| BGSProcedureAcquire | 0x1418c92c8 | 35 |  |
| BGSProcedureAcquireExecState | 0x1418c9438 | 9 |  |
| BGSProcedureActivate | 0x1418c97a8 | 35 |  |
| BGSProcedureActivateExecState | 0x1418c9918 | 9 |  |
| BGSProcedureBase | 0x1418c8af8 | 34 |  |
| BGSProcedureDialogue | 0x1418c9c28 | 35 |  |
| BGSProcedureDialogueActivate | 0x1418ca140 | 35 |  |
| BGSProcedureDialogueActivateExecState | 0x1418ca2b0 | 9 |  |
| BGSProcedureDialogueExecState | 0x1418c73d0 | 9 |  |
| BGSProcedureDone | 0x1418c8d30 | 35 |  |
| BGSProcedureDoneExecState | 0x1418c6a40 | 9 |  |
| BGSProcedureEat | 0x1418ca588 | 35 |  |
| BGSProcedureEatExecState | 0x1418c7470 | 9 |  |
| BGSProcedureEscort | 0x1418cab40 | 35 |  |
| BGSProcedureEscortExecState | 0x1418cacb0 | 9 |  |
| BGSProcedureFind | 0x1418caff8 | 35 |  |
| BGSProcedureFindExecState | 0x1418c7510 | 9 |  |
| BGSProcedureFlee | 0x1418cb608 | 35 |  |
| BGSProcedureFleeExecState | 0x1418cb778 | 9 |  |
| BGSProcedureFlightGrab | 0x1418cbab0 | 35 |  |
| BGSProcedureFlightGrabExecState | 0x1418cbc20 | 9 |  |
| BGSProcedureFollow | 0x1418cc0d8 | 35 |  |
| BGSProcedureFollowExecState | 0x1418cc488 | 9 |  |
| BGSProcedureFollowTo | 0x1418cc318 | 35 |  |
| BGSProcedureForceGreet | 0x1418cc820 | 35 |  |
| BGSProcedureGuard | 0x1418ccbf8 | 35 |  |
| BGSProcedureGuardExecState | 0x1418c75b0 | 9 |  |
| BGSProcedureHoldPosition | 0x1418ccf38 | 35 |  |
| BGSProcedureHoldPositionExecState | 0x1418c7650 | 9 |  |
| BGSProcedureHover | 0x1418cd320 | 35 |  |
| BGSProcedureHoverExecState | 0x1418cd490 | 9 |  |
| BGSProcedureKeepAnEyeOn | 0x1418cd758 | 35 |  |
| BGSProcedureKeepAnEyeOnExecState | 0x1418c76f0 | 9 |  |
| BGSProcedureLock | 0x1418cdb78 | 35 |  |
| BGSProcedureLockUnlockExecState | 0x1418cdf28 | 9 |  |
| BGSProcedureOrbit | 0x1418ce3d8 | 35 |  |
| BGSProcedureOrbitExecState | 0x1418ce548 | 9 |  |
| BGSProcedurePatrol | 0x1418cebe0 | 35 |  |
| BGSProcedurePatrolExecState | 0x1418ced50 | 9 |  |
| BGSProcedurePursue | 0x1418cf000 | 35 |  |
| BGSProcedureSandbox | 0x1418cf7c0 | 35 |  |
| BGSProcedureSandboxExecState | 0x1418cf930 | 9 |  |
| BGSProcedureSay | 0x1418cfb80 | 35 |  |
| BGSProcedureSayExecState | 0x1418c7790 | 9 |  |
| BGSProcedureShout | 0x1418d0110 | 35 |  |
| BGSProcedureShoutExecState | 0x1418d0298 | 9 | 8: 0x1418d02e8, 2 |
| BGSProcedureSit | 0x1418d0668 | 35 |  |
| BGSProcedureSitSleepExecState | 0x1418d0a18 | 9 |  |
| BGSProcedureSleep | 0x1418d08a8 | 35 |  |
| BGSProcedureTravel | 0x1418d0db0 | 35 |  |
| BGSProcedureTravelExecState | 0x1418d0f20 | 9 |  |
| BGSProcedureTreeBranch | 0x1418c6b20 | 18 |  |
| BGSProcedureTreeConditionalItem | 0x1418c6a90 | 17 |  |
| BGSProcedureTreeOneChildExecState | 0x1418c6bb8 | 10 |  |
| BGSProcedureTreeProcedure | 0x1418d1310 | 17 |  |
| BGSProcedureTreeRandom | 0x1418c7238 | 18 |  |
| BGSProcedureTreeRandomExecState | 0x1418c7328 | 10 |  |
| BGSProcedureTreeSequence | 0x1418c6ca8 | 18 |  |
| BGSProcedureTreeSequenceExecState | 0x1418c6d98 | 10 |  |
| BGSProcedureTreeSimultaneous | 0x1418c7068 | 18 |  |
| BGSProcedureTreeSimultaneousExecState | 0x1418c7150 | 9 |  |
| BGSProcedureTreeStacked | 0x1418c6e88 | 18 |  |
| BGSProcedureTreeStackedExecState | 0x1418c6f78 | 10 |  |
| BGSProcedureUnlock | 0x1418cddb8 | 35 |  |
| BGSProcedureUseIdleMarker | 0x1418d1650 | 35 |  |
| BGSProcedureUseIdleMarkerExecState | 0x1418d17c0 | 9 |  |
| BGSProcedureUseMagic | 0x1418d1bf0 | 35 |  |
| BGSProcedureUseMagicExecState | 0x1418d1d60 | 9 | 8: 0x1418d1db0, 2 |
| BGSProcedureUseWeapon | 0x1418d2420 | 35 |  |
| BGSProcedureUseWeaponExecState | 0x1418d2590 | 9 |  |
| BGSProcedureWait | 0x1418d27d8 | 35 |  |
| BGSProcedureWaitExecState | 0x1418c7830 | 9 |  |
| BGSProcedureWander | 0x1418d2c08 | 35 |  |
| BGSProcedureWanderExecState | 0x1418d2d78 | 9 |  |
| BGSRefAlias | 0x141858618 | 4 |  |
| BGSScene | 0x1418592f8 | 59 |  |
| BGSSceneAction | 0x141859580 | 20 |  |
| BGSSceneActionDialogue | 0x141859628 | 20 |  |
| BGSSceneActionPackage | 0x1418596d0 | 20 |  |
| BGSSceneActionTimer | 0x141859ac0 | 20 |  |
| BGSSceneInfo | 0x141802210 | 1 |  |
| BGSSceneInfo::TextureUse | 0x1418021f8 | 2 |  |
| BGSStoryTeller | 0x1418e8940 | 2 |  |
| BSNavmesh | 0x141abfd50 | 2 |  |
| BSNavmeshInfoMap | 0x141ac02e0 | 6 |  |
| BSNavmeshInfoMap::IRecursiveVisitor | 0x141ac02c0 | 3 |  |
| BSNavmeshInfoMap::IVisitor | 0x1418da7f8 | 2 |  |
| BSNavmeshInfoSearch | 0x141abcd58 | 3 |  |
| BSNavmeshObstacleData | 0x141ac05a8 | 2 |  |
| BSNavmeshObstacleUndoData | 0x141acbd08 | 2 |  |
| BSNavmeshReferenceObstacleArray | 0x1418dbc40 | 2 |  |
| BSNavmeshSearch | 0x141ac1948 | 3 |  |
| BSNavmeshSearchFilters | 0x141ac17f0 | 2 |  |
| BSNavmeshSearchHideFilter | 0x1418de770 | 2 |  |
| BSNavmeshSearchMaxCostFilters | 0x1418de938 | 2 |  |
| BSPathing | 0x141abc9a0 | 9 |  |
| BSPathing::CheckLineOfSightFilter | 0x1418fc068 | 2 |  |
| BSPathing::EdgeFoundVisitor | 0x141abc988 | 2 |  |
| BSPathingCell | 0x1418dd0a8 | 11 |  |
| BSPathingCellManager | 0x1418dcd70 | 11 |  |
| BSPathingDoor | 0x1418dd498 | 18 |  |
| BSPathingLOSGrid | 0x141ac1de8 | 3 |  |
| BSPathingLOSGridCell | 0x141ac1e08 | 3 |  |
| BSPathingLOSGridMap | 0x141ac1dc8 | 3 |  |
| BSPathingLockData | 0x1418dd7e0 | 6 |  |
| BSPathingNumericIDVisitor | 0x1418dd868 | 2 |  |
| BSPathingRequest | 0x141abd278 | 7 |  |
| BSPathingSearchRayCast | 0x141acac00 | 1 |  |
| BSPathingSpace | 0x1418dda28 | 4 |  |
| BSPathingStreamRead | 0x1418d9768 | 20 |  |
| BSPathingStreamSimpleBufferRead | 0x141ac4320 | 20 |  |
| BSPathingStreamSimpleBufferWrite | 0x14192fac8 | 17 |  |
| BSPathingStreamWrite | 0x14192fa38 | 17 |  |
| DialoguePackage | 0x1418d5468 | 64 |  |
| ExtraInfoGeneralTopic | 0x1417ed3b0 | 3 |  |
| ExtraPackage | 0x1417ed3d0 | 3 |  |
| ExtraPackageData | 0x1417ea478 | 3 |  |
| ExtraPackageStartLocation | 0x1417e9c98 | 3 |  |
| ExtraSayToTopicInfo | 0x1417ed570 | 3 |  |
| ExtraSayTopicInfoOnceADay | 0x1417ed550 | 3 |  |
| MovementAgent | 0x141ac6210 | 13 |  |
| MovementAgentActorAvoider | 0x141ac60e0 | 13 | 24: 0x141ac6150, 4, 32: 0x141ac6178, 7, 40: 0x141ac61b8, 3 |
| MovementAgentActorState | 0x141abd018 | 13 | 24: 0x141abd088, 4, 32: 0x141abd0b0, 3, 40: 0x141abd0d0, 3 |
| MovementAgentPathFollowerFlight | 0x141ac7a40 | 14 | 24: 0x141ac7ab8, 4, 32: 0x141ac7ae0, 7, 40: 0x141ac7b20, 21, 48: 0x141ac7bd0, 1 |
| MovementAgentPathFollowerStandard | 0x141abe270 | 13 | 24: 0x141abe2e0, 4, 32: 0x141abe308, 7, 40: 0x141abe348, 21, 48: 0x141abe3f8, 2, 56: 0x141abe410, 4, 64: 0x141abe438, 4 |
| MovementAgentPathFollowerVirtual | 0x141ac7ed0 | 14 | 24: 0x141ac7f48, 4, 32: 0x141ac7f70, 7, 40: 0x141ac7fb0, 21, 48: 0x141ac8060, 2 |
| MovementControllerAI | 0x141ac4220 | 10 |  |
| MovementControllerNPC | 0x14192f0e8 | 21 | 288: 0x14192f198, 4, 296: 0x14192f1c0, 9, 304: 0x14192f210, 6, 312: 0x14192f248, 9, 320: 0x14192f298, 6, 328: 0x14192f2d0, 2 |
| MovementControllerNullDataTracker | 0x141ac43e0 | 2 |  |
| MovementPathManagerAgent | 0x141abeb88 | 13 | 24: 0x141abebf8, 7 |
| MovementPathManagerAgentAvoidBox | 0x141ac9450 | 13 | 24: 0x141ac94c0, 7 |
| MovementPathManagerAgentLoadedAreaMonitor | 0x141ac75b0 | 13 | 24: 0x141ac7620, 7 |
| MovementPathManagerAgentStaticAvoider | 0x141ac5828 | 13 | 24: 0x141ac5898, 7, 32: 0x141ac58d8, 4, 40: 0x141ac5900, 3 |
| MovementPathManagerArbiter | 0x141abece0 | 18 | 24: 0x141abed78, 5, 32: 0x141abeda8, 14 |
| MovementPathManagerNullTracker | 0x141abee98 | 4 |  |
| NavMesh | 0x1418d9388 | 63 | 32: 0x1418d9588, 2, 40: 0x1418d95a0, 2 |
| NavMeshInfoMap | 0x1418da810 | 59 | 32: 0x1418da9f0, 6 |
| NavMeshObstacleManager | 0x1418dbc28 | 2 |  |
| NavMeshSearchClosePoint | 0x1418de238 | 3 |  |
| NavMeshSearchFitSphere | 0x1418de610 | 3 |  |
| NavMeshSearchFlee | 0x1418de6a8 | 3 |  |
| NavMeshSearchHide | 0x1418de750 | 3 |  |
| NavMeshSearchLOS | 0x1418de880 | 3 |  |
| NavMeshSearchMaxCost | 0x1418de918 | 3 |  |
| NavMeshSearchMultipleGoals | 0x1418de9f0 | 3 |  |
| NavMeshSearchSLPoint | 0x1418dea88 | 3 |  |
| PackageList::IPackageVisitor | 0x14191b4f0 | 1 |  |
| PathManagerPositionPlayerAdapter | 0x14190f930 | 2 | 8: 0x14190f948, 2, 16: 0x14190f960, 2, 24: 0x14190f978, 2, 32: 0x14190f990, 2 |
| PathingRequest | 0x1418dd9d8 | 7 |  |
| PathingRequestClosePoint | 0x1418debc8 | 7 |  |
| PathingRequestClosestGoal | 0x1418def58 | 7 |  |
| PathingRequestCover | 0x1418df1a0 | 7 |  |
| PathingRequestFlee | 0x1418df2c8 | 7 |  |
| PathingRequestFly | 0x1418df418 | 7 |  |
| PathingRequestFlyAction | 0x1418df568 | 7 |  |
| PathingRequestFlyHover | 0x1418df780 | 7 |  |
| PathingRequestFlyLand | 0x1418df8d0 | 7 |  |
| PathingRequestFlyOrbit | 0x1418df9f8 | 7 |  |
| PathingRequestFlyTakeOff | 0x1418dfb20 | 7 |  |
| PathingRequestHide | 0x1418dfca0 | 7 |  |
| PathingRequestLOS | 0x1418dfeb8 | 7 |  |
| PathingRequestOptimalLocation | 0x1418dffe0 | 7 |  |
| PathingRequestRotate | 0x1418e0138 | 7 |  |
| PathingRequestSafeStraightLine | 0x1418e0260 | 7 |  |
| PathingRequestStopMoving | 0x1418e0390 | 7 |  |
| ProcessLists::GetActorsFilter | 0x1418f8870 | 2 |  |
| TESFurniture | 0x141811840 | 83 | 48: 0x141811ae0, 6, 64: 0x141811b18, 7, 120: 0x141811b58, 4, 136: 0x141811b80, 4, 144: 0x141811ba8, 6 |
| TESIdleForm | 0x14185c410 | 59 |  |
| TESPackage | 0x1418d5260 | 64 |  |
| TESPackageData | 0x1418d5730 | 6 |  |
| TESQuest | 0x141860910 | 63 | 40: 0x141860b10, 6 |
| TESTopic | 0x141862fe0 | 59 | 32: 0x1418631c0, 6 |
| TESTopicInfo | 0x1418639f0 | 59 |  |

## Havok (the physics) (473 classes, 0 template classes left out)

From the MSVC RTTI of `SkyrimSE.exe`: 7,831 type descriptors (`.?AV...@@` in `.data`), 8,457 complete object locators and 7,159 classes with a vtable in `.rdata`. Here the classes of the inn's systems with their primary vtable (the one at offset 0 of the object) and how many virtual functions follow it before the next vtable (the count includes the slots of the base classes; a class's own slots come last). A secondary vtable (a base at another offset) is listed with that offset. Template classes (`BSTEventSink<...>`, `ConcreteFormFactory<...>`, the behavior tree's `CombatBehaviorTreeNodeObject<...>`) are left out; their count is in the system's heading. The vtable's slot k holds the address of the virtual function, so a function is found as the vtable's address plus 8 k, and `procedure_pseudo_code` on that address gives its code.

The layouts to read a slot by name: CommonLibSSE-NG's headers declare each class's virtual functions in vtable order (`IMenu`: 0 destructor, 1 Accept(CallbackProcessor), 2 PostCreate, 3 Unk_03, 4 ProcessMessage(UIMessage), 5 AdvanceMovie(interval, currentTime), 6 PostDisplay, 7 PreDisplay, 8 RefreshPlatform).

| class | vtable | slots | other vtables (offset: address, slots) |
|---|---|---|---|
| bhkAabbPhantom | 0x141827460 | 51 |  |
| bhkAcousticSpacePhantomCallbackShape | 0x141827db8 | 13 |  |
| bhkAction | 0x141865328 | 51 |  |
| bhkAngularDashpotAction | 0x141a90608 | 54 |  |
| bhkAttachmentCollisionObject | 0x141a826d0 | 49 |  |
| bhkAvoidBox | 0x141a85518 | 51 |  |
| bhkBackfaceContactListener | 0x141866530 | 7 |  |
| bhkBallAndSocketConstraint | 0x141a8a0c0 | 55 |  |
| bhkBallSocketConstraintChain | 0x141a8e688 | 56 |  |
| bhkBinaryAction | 0x141a90450 | 54 |  |
| bhkBipedOrientationController | 0x141a8ab30 | 11 |  |
| bhkBlendCollisionObject | 0x141a85198 | 49 |  |
| bhkBlendController | 0x141a917c0 | 47 |  |
| bhkBoxShape | 0x141828d48 | 54 |  |
| bhkBreakableConstraint | 0x141a90128 | 55 |  |
| bhkBvTreeShape | 0x141865eb0 | 54 |  |
| bhkCachingShapePhantom | 0x141a88de0 | 51 |  |
| bhkCapsuleShape | 0x141a844f8 | 54 |  |
| bhkCartTether | 0x141864db8 | 49 |  |
| bhkCharControllerShape | 0x141a92a38 | 54 |  |
| bhkCharProxyController | 0x141a89540 | 6 | 16: 0x141a89578, 20 |
| bhkCharProxyControllerCinfo | 0x141a89508 | 6 |  |
| bhkCharRigidBodyController | 0x141a89bf0 | 20 | 816: 0x141a89c98, 8 |
| bhkCharRigidBodyControllerCinfo | 0x141a89bb8 | 6 |  |
| bhkCharacterCollisionHandler | 0x14192e428 | 2 |  |
| bhkCharacterController | 0x141a7f7a0 | 20 |  |
| bhkCharacterControllerCinfo | 0x141a7f768 | 6 |  |
| bhkCharacterPointCollector | 0x141a96730 | 3 |  |
| bhkCharacterProxy | 0x141a89370 | 50 |  |
| bhkCharacterProxyCinfo | 0x141a89350 | 3 |  |
| bhkCharacterRigidBody | 0x141a899d8 | 50 |  |
| bhkCharacterRigidBodyCinfo | 0x141a899b8 | 3 |  |
| bhkCharacterState | 0x141a7f718 | 9 |  |
| bhkCharacterStateClimbing | 0x141a7f8a8 | 9 |  |
| bhkCharacterStateFlying | 0x141a7f8f8 | 9 |  |
| bhkCharacterStateInAir | 0x141a925c8 | 9 |  |
| bhkCharacterStateJumping | 0x141a92640 | 9 |  |
| bhkCharacterStateOnGround | 0x141a92808 | 9 |  |
| bhkCharacterStateSwimming | 0x141a92888 | 9 |  |
| bhkCollisionBox | 0x141a7f948 | 52 |  |
| bhkCollisionFilter | 0x141a825f0 | 4 | 16: 0x141a82618, 2, 24: 0x141a82630, 4, 32: 0x141a82658, 2, 40: 0x141a82670, 2 |
| bhkCompressedMeshShape | 0x141a8b820 | 55 |  |
| bhkCompressedMeshShapeData | 0x141a8b6f0 | 37 |  |
| bhkConstraint | 0x141864f78 | 55 |  |
| bhkConstraintChain | 0x141a8e490 | 56 |  |
| bhkContactListener | 0x1418664f0 | 7 |  |
| bhkConvexShape | 0x141827fe0 | 54 |  |
| bhkConvexSweepShape | 0x141a8bb98 | 54 |  |
| bhkConvexTransformShape | 0x141a8bf08 | 54 |  |
| bhkConvexTranslateShape | 0x141a8c278 | 54 |  |
| bhkConvexVerticesShape | 0x141a8c688 | 54 |  |
| bhkCylinderShape | 0x141a8c9f8 | 54 |  |
| bhkDashpotAction | 0x141a90900 | 54 |  |
| bhkEntity | 0x141827120 | 51 |  |
| bhkEntityListener | 0x141863d40 | 10 |  |
| bhkExtraData | 0x141a91ba0 | 39 |  |
| bhkFilteredCdBodyCollector | 0x14191d450 | 3 |  |
| bhkFixedConstraint | 0x141a8f298 | 55 |  |
| bhkGenericConstraint | 0x141a8f0d8 | 55 |  |
| bhkGroupConstraint | 0x141a8e990 | 55 |  |
| bhkHeightFieldShape | 0x141a8d0d8 | 54 |  |
| bhkHingeConstraint | 0x141941580 | 55 |  |
| bhkHingeLimitsConstraint | 0x141a8ed38 | 55 |  |
| bhkICharOrientationController | 0x141a7f848 | 11 |  |
| bhkIWorldStepListener | 0x141a06300 | 3 |  |
| bhkLimitedHingeConstraint | 0x141a82c38 | 55 |  |
| bhkLiquidAction | 0x141a90c20 | 51 |  |
| bhkListShape | 0x141a7fcb0 | 55 |  |
| bhkMalleableConstraint | 0x141a85b30 | 55 |  |
| bhkMemorySystem | 0x141a8add0 | 23 |  |
| bhkMoppBvTreeShape | 0x141a8d9c0 | 54 |  |
| bhkMotorAction | 0x141a90f28 | 51 |  |
| bhkMouseSpringAction | 0x14192a358 | 51 |  |
| bhkMultiSphereShape | 0x141a8cdb8 | 54 |  |
| bhkNiCollisionObject | 0x141a80058 | 49 |  |
| bhkNiTriStripsShape | 0x141a84be8 | 55 |  |
| bhkObstacleDeactivationListener | 0x1418dbc78 | 3 |  |
| bhkObstacleRemovalListener | 0x1418dbc98 | 6 |  |
| bhkOnExitCallback | 0x141a7c370 | 2 |  |
| bhkOnStartupCallback | 0x141a7c358 | 2 |  |
| bhkOrientHingedBodyAction | 0x141a91230 | 52 |  |
| bhkPCollisionObject | 0x141828518 | 49 |  |
| bhkPackedNiTriStripsShape | 0x141a84f60 | 55 |  |
| bhkPhantom | 0x1418272c0 | 51 |  |
| bhkPlaneShape | 0x141a8d290 | 54 |  |
| bhkPointToPathConstraint | 0x141a97c68 | 55 |  |
| bhkPoseArray | 0x141a91df8 | 37 |  |
| bhkPositionConstraintMotor | 0x141a93398 | 25 |  |
| bhkPrismaticConstraint | 0x141865168 | 55 |  |
| bhkQuadOrientationController | 0x141a92d08 | 11 |  |
| bhkRagdollConstraint | 0x141a8a528 | 55 |  |
| bhkRagdollController | 0x141a82090 | 3 |  |
| bhkRagdollLimitsConstraint | 0x141a8f7a8 | 55 |  |
| bhkRagdollPenetrationUtil | 0x141a7ebe8 | 2 |  |
| bhkRagdollShareData | 0x141a81f60 | 37 |  |
| bhkRagdollTemplate | 0x141a8a3b0 | 40 |  |
| bhkRagdollTemplateData | 0x141a8a280 | 37 |  |
| bhkRefObject | 0x141a83508 | 39 |  |
| bhkRigidBody | 0x141828198 | 61 |  |
| bhkRigidBodyT | 0x141a82ef8 | 61 |  |
| bhkSPCollisionObject | 0x14193d278 | 49 |  |
| bhkSerializable | 0x141826cd0 | 50 |  |
| bhkShape | 0x141826ec8 | 54 |  |
| bhkShapeCollection | 0x141a7faf0 | 55 |  |
| bhkShapePhantom | 0x1418286a8 | 51 |  |
| bhkSimpleShapePhantom | 0x141828848 | 51 |  |
| bhkSphereRepShape | 0x141827e28 | 54 |  |
| bhkSphereShape | 0x141828f00 | 54 |  |
| bhkSpringAction | 0x141a91540 | 54 |  |
| bhkSpringDamperConstraintMotor | 0x141a935c8 | 25 |  |
| bhkStiffSpringConstraint | 0x141a7d988 | 55 |  |
| bhkTaskletManagerCallback | 0x141a7c340 | 2 |  |
| bhkTelekinesisListener | 0x141914188 | 7 |  |
| bhkThreadMemorySource | 0x141a96e60 | 11 | 8: 0x141a96ec0, 15 |
| bhkTransformShape | 0x141a8dd58 | 54 |  |
| bhkTrapListener | 0x141867db8 | 10 | 24: 0x141867e10, 5 |
| bhkTriSampledHeightFieldBvTreeShape | 0x141866068 | 54 |  |
| bhkTriangleShape | 0x141a8d588 | 54 |  |
| bhkUnaryAction | 0x1418654c8 | 51 |  |
| bhkVelocityConstraintMotor | 0x141a934b0 | 25 |  |
| bhkWheelConstraint | 0x141a8fcb8 | 55 |  |
| bhkWindListener | 0x141a7e478 | 11 |  |
| bhkWorld | 0x141a7cda8 | 55 |  |
| bhkWorld::bhkConstraintProjector | 0x141a7cd68 | 7 |  |
| bhkWorldCinfo | 0x141824020 | 3 |  |
| bhkWorldM | 0x141a831e8 | 55 |  |
| bhkWorldObject | 0x141a7b808 | 51 |  |
| hkBaseObject | 0x141820b98 | 1 |  |
| hkClassNameRegistry | 0x1419e58b8 | 6 |  |
| hkContainerDebugAllocator::Allocator | 0x1419ba430 | 11 |  |
| hkContainerHeapAllocator::Allocator | 0x1419ba3d0 | 11 |  |
| hkContainerResourceMap | 0x1419e6750 | 2 |  |
| hkContainerTempAllocator::Allocator | 0x1419ba370 | 11 |  |
| hkMemoryAllocator | 0x1419ba2b0 | 11 |  |
| hkMemoryResourceContainer | 0x1419e66c8 | 16 |  |
| hkMemoryResourceHandle | 0x1419e6650 | 14 |  |
| hkMemoryStreamReader | 0x141a1b928 | 12 |  |
| hkMemorySystem | 0x1419c03c8 | 23 |  |
| hkMemoryTrackStreamReader | 0x1419bfb10 | 12 |  |
| hkMemoryTrackStreamWriter | 0x1419bf0c0 | 10 |  |
| hkMemoryTracker | 0x1419c0310 | 9 |  |
| hkReferencedObject | 0x141820ba8 | 3 |  |
| hkReferencedObjectLock | 0x1419ba278 | 3 |  |
| hkResource | 0x141a12040 | 8 |  |
| hkResourceBase | 0x1419e6508 | 5 |  |
| hkResourceContainer | 0x1419e65b0 | 16 |  |
| hkResourceHandle | 0x1419e6538 | 14 |  |
| hkResourceMap | 0x1419e6638 | 2 |  |
| hkaAnimatedReferenceFrame | 0x141a0b800 | 6 |  |
| hkaAnimation | 0x141a0b838 | 16 |  |
| hkaAnimationBinding | 0x141a04fb0 | 3 |  |
| hkaAnimationContainer | 0x141a0c260 | 3 |  |
| hkaAnimationControl | 0x141a0d578 | 14 |  |
| hkaAnimationPreviewColorContainer | 0x141a0bd88 | 3 |  |
| hkaBoneAttachment | 0x141a0c1b0 | 3 |  |
| hkaDefaultAnimatedReferenceFrame | 0x141a0c048 | 6 |  |
| hkaDefaultAnimationControl | 0x141a09e38 | 14 |  |
| hkaDefaultAnimationControlMapperData | 0x141a09eb0 | 3 |  |
| hkaDetectRagdollPenetration | 0x141a922e8 | 3 |  |
| hkaFootPlacementIkSolver | 0x1419ba1e8 | 3 |  |
| hkaFootstepAnalysisInfo | 0x141a162a8 | 3 |  |
| hkaFootstepAnalysisInfoContainer | 0x141a0c0f0 | 3 |  |
| hkaInterleavedUncompressedAnimation | 0x141a0b998 | 16 |  |
| hkaMeshBinding | 0x141a16148 | 3 |  |
| hkaMirroredSkeleton | 0x141a0d430 | 3 |  |
| hkaQuantizedAnimation | 0x141a0ba70 | 16 |  |
| hkaRagdollInstance | 0x141a09e10 | 4 |  |
| hkaRagdollRaycastInterface | 0x141a7ebd0 | 2 |  |
| hkaRaycastInterface | 0x1418e9d00 | 3 |  |
| hkaSkeleton | 0x141a07ce0 | 3 |  |
| hkaSkeletonMapper | 0x141a09ad8 | 3 |  |
| hkaSplineCompressedAnimation | 0x141a0bb88 | 16 |  |
| hkp3AxisSweep | 0x141a0ff38 | 31 |  |
| hkpAabbPhantom | 0x1419ebce8 | 15 |  |
| hkpAction | 0x1419ebee8 | 8 |  |
| hkpAllCdBodyPairCollector | 0x14191d430 | 3 |  |
| hkpAllCdBodyPairTempCollector | 0x141867f78 | 3 |  |
| hkpAllCdPointCollector | 0x141867190 | 3 |  |
| hkpAllCdPointTempCollector | 0x1418683e8 | 3 |  |
| hkpAllRayHitCollector | 0x141a7ebb8 | 2 |  |
| hkpAllRayHitTempCollector | 0x1417fde48 | 2 |  |
| hkpAngularDashpotAction | 0x1419f9fc0 | 8 |  |
| hkpArrayAction | 0x141a1b258 | 8 |  |
| hkpBallAndSocketConstraintData | 0x1419f2a20 | 19 |  |
| hkpBallGun | 0x1419fb268 | 9 |  |
| hkpBallSocketChainData | 0x1419f5b68 | 20 |  |
| hkpBinaryAction | 0x1419f9f78 | 8 |  |
| hkpBoxBoxAgent | 0x141a19a50 | 14 |  |
| hkpBoxMotion | 0x1419eb900 | 26 |  |
| hkpBoxShape | 0x1419e6e00 | 18 |  |
| hkpBreakableConstraintData | 0x1419f5a20 | 19 |  |
| hkpBroadPhase | 0x141a10078 | 31 |  |
| hkpBroadPhaseBorder | 0x1419f5f60 | 5 | 16: 0x1419f5f90, 3, 24: 0x1419f5fb0, 3, 32: 0x1419f5fd0, 3 |
| hkpBroadPhaseBorderListener | 0x1419f4fb8 | 3 | 16: 0x1419f4fd8, 3 |
| hkpBroadPhaseCastCollector | 0x1419f4ef8 | 2 |  |
| hkpBroadPhaseListener | 0x1419f4ed8 | 3 |  |
| hkpBvAgent | 0x141a19b38 | 14 |  |
| hkpBvShape | 0x1419e6bf8 | 11 |  |
| hkpBvTreeAgent | 0x141a19d08 | 14 |  |
| hkpBvTreeShape | 0x1419e9cd8 | 13 |  |
| hkpBvTreeStreamAgent | 0x141a19ea8 | 14 |  |
| hkpCachingShapePhantom | 0x1419f4688 | 19 |  |
| hkpCallbackConstraintMotor | 0x1419f3e78 | 4 |  |
| hkpCapsuleCapsuleAgent | 0x141a1a570 | 14 |  |
| hkpCapsuleShape | 0x1419e7248 | 18 |  |
| hkpCapsuleTriangleAgent | 0x141a1a5f8 | 14 |  |
| hkpCdBodyPairCollector | 0x141867d68 | 3 |  |
| hkpCdPointCollector | 0x141867170 | 3 |  |
| hkpCharacterContext | 0x1419f6900 | 3 |  |
| hkpCharacterControllerCinfo | 0x1419e4a60 | 3 |  |
| hkpCharacterMotion | 0x1419ebab0 | 26 |  |
| hkpCharacterProxy | 0x1419fae40 | 5 | 16: 0x1419fae70, 6, 24: 0x1419faea8, 5 |
| hkpCharacterProxyCinfo | 0x1419e4a80 | 3 |  |
| hkpCharacterProxyListener | 0x141a89318 | 6 |  |
| hkpCharacterRigidBody | 0x1419f69b0 | 6 | 16: 0x1419f69e8, 6, 24: 0x1419f6a20, 3 |
| hkpCharacterRigidBodyCinfo | 0x1419fa2a8 | 3 |  |
| hkpCharacterRigidBodyListener | 0x141a89b70 | 8 |  |
| hkpCharacterState | 0x141a7f6d0 | 8 |  |
| hkpCharacterStateManager | 0x1419f6990 | 3 |  |
| hkpClosestCdPointCollector | 0x1419568f0 | 3 |  |
| hkpClosestRayHitCollector | 0x141867638 | 2 |  |
| hkpCogWheelConstraintData | 0x1419f2b50 | 19 |  |
| hkpCollidableCollidableFilter | 0x1419e68b0 | 2 |  |
| hkpCollidableMediator | 0x141a996c0 | 6 |  |
| hkpCollisionAgent | 0x1419e76c8 | 14 |  |
| hkpCollisionCallbackUtil | 0x1419f4ff8 | 5 | 32: 0x1419f5028, 7 |
| hkpCollisionDispatcher | 0x1419e6840 | 3 |  |
| hkpCollisionFilter | 0x1419e77b8 | 4 | 16: 0x1419e77e0, 2, 24: 0x1419e77f8, 4, 32: 0x1419e7820, 2, 40: 0x1419e7838, 2 |
| hkpCollisionFilterList | 0x1419e99e8 | 4 | 16: 0x1419e9a10, 2, 24: 0x1419e9a28, 4, 32: 0x1419e9a50, 2, 40: 0x1419e9a68, 2 |
| hkpCompressedMeshShape | 0x141a97020 | 13 | 32: 0x141a97090, 7 |
| hkpCompressedSampledHeightFieldShape | 0x1419eabc0 | 15 |  |
| hkpConstrainedSystemFilter | 0x1419fa490 | 4 | 16: 0x1419fa4b8, 2, 24: 0x1419fa4d0, 4, 32: 0x1419fa4f8, 2, 40: 0x1419fa510, 2, 72: 0x1419fa528, 7 |
| hkpConstraintChainData | 0x1419f5ac0 | 20 |  |
| hkpConstraintChainInstance | 0x1419f3bf0 | 7 |  |
| hkpConstraintChainInstanceAction | 0x1419f3c70 | 8 |  |
| hkpConstraintCollisionFilter | 0x1419f27d8 | 4 | 16: 0x1419f2800, 2, 24: 0x1419f2818, 4, 32: 0x1419f2840, 2, 40: 0x1419f2858, 2, 96: 0x1419f2870, 7 |
| hkpConstraintData | 0x1419ebda8 | 19 |  |
| hkpConstraintInstance | 0x1419f2628 | 7 |  |
| hkpConstraintListener | 0x1419f2798 | 7 |  |
| hkpConstraintMotor | 0x1419f3e28 | 4 |  |
| hkpConstraintOwner | 0x1419f5600 | 7 |  |
| hkpConstraintUtils::CollectConstraintsFilter | 0x141a126a8 | 2 |  |
| hkpContactListener | 0x1418664b0 | 7 |  |
| hkpContactMgr | 0x1419f4e00 | 10 |  |
| hkpContactMgrFactory | 0x1419f4dc0 | 4 |  |
| hkpContinuousSimulation | 0x141a96198 | 22 |  |
| hkpConvexListAgent | 0x141a1ad30 | 14 |  |
| hkpConvexListFilter | 0x1419e6860 | 4 |  |
| hkpConvexListShape | 0x1419ea250 | 18 | 40: 0x1419ea2e8, 7 |
| hkpConvexPieceStreamData | 0x1419f6798 | 3 |  |
| hkpConvexShape | 0x1419e6d68 | 18 |  |
| hkpConvexTransformShape | 0x1419e9ed8 | 18 |  |
| hkpConvexTransformShapeBase | 0x1419e6ea0 | 18 |  |
| hkpConvexTranslateShape | 0x1419e9fa8 | 18 |  |
| hkpConvexVerticesConnectivity | 0x1419ea078 | 4 |  |
| hkpConvexVerticesShape | 0x141a11f18 | 18 |  |
| hkpCylinderShape | 0x1419eb208 | 18 |  |
| hkpDashpotAction | 0x1419fa040 | 8 |  |
| hkpDefaultConvexListFilter | 0x1419e6888 | 4 |  |
| hkpDefaultToiResourceMgr | 0x141a97f80 | 8 |  |
| hkpDefaultWorldMaintenanceMgr | 0x1419f6350 | 6 |  |
| hkpDefaultWorldMemoryWatchDog | 0x1419f4898 | 6 |  |
| hkpDeferredConstraintOwner | 0x141a98158 | 7 |  |
| hkpDisableEntityCollisionFilter | 0x1419fa5a8 | 4 | 16: 0x1419fa5d0, 2, 24: 0x1419fa5e8, 4, 32: 0x1419fa610, 2, 40: 0x1419fa628, 2, 72: 0x1419fa640, 6 |
| hkpDisplayBindingData | 0x1419fab38 | 3 |  |
| hkpDisplayBindingData::PhysicsSystem | 0x1419fab18 | 3 |  |
| hkpDisplayBindingData::RigidBody | 0x1419faaf8 | 3 |  |
| hkpDynamicsContactMgr | 0x1419f5ff0 | 19 |  |
| hkpEaseConstraintsAction | 0x141a126d8 | 8 |  |
| hkpEaseConstraintsAction::CollectSupportedConstraints | 0x141a126c0 | 2 |  |
| hkpEasePenetrationAction | 0x141a12920 | 8 |  |
| hkpEndOfStepCallbackUtil | 0x1419f63e0 | 3 | 16: 0x1419f6400, 3 |
| hkpEntity | 0x1419eb6f8 | 7 |  |
| hkpEntityActivationListener | 0x1418dbc58 | 3 |  |
| hkpEntityEntityBroadPhaseListener | 0x1419f5df8 | 3 | 16: 0x1419f5e18, 3 |
| hkpEntityListener | 0x141823fe8 | 6 |  |
| hkpExtendedMeshShape | 0x141a16e90 | 15 | 32: 0x141a16f10, 7 |
| hkpFastMeshShape | 0x141a10cf0 | 14 | 32: 0x141a10d68, 7 |
| hkpFirstCdBodyPairCollector | 0x14192a4f8 | 3 |  |
| hkpFirstPersonGun | 0x1419fb218 | 9 |  |
| hkpFixedBufferCdPointCollector | 0x14193f248 | 3 |  |
| hkpFixedBufferRayHitCollector | 0x141a987e8 | 2 |  |
| hkpFixedRigidMotion | 0x1419eb738 | 29 |  |
| hkpFlagCdBodyPairCollector | 0x141a19bb0 | 3 |  |
| hkpGenericConstraintData | 0x1419f5cb8 | 19 |  |
| hkpGravityGun | 0x1419fb2d8 | 9 |  |
| hkpGroupCollisionFilter | 0x1419fa6c0 | 4 | 16: 0x1419fa6e8, 2, 24: 0x1419fa700, 4, 32: 0x1419fa728, 2, 40: 0x1419fa740, 2 |
| hkpGroupFilter | 0x1419e72f0 | 5 | 16: 0x1419e7320, 2, 24: 0x1419e7338, 4, 32: 0x1419e7360, 2, 40: 0x1419e7378, 2 |
| hkpGskBaseAgent | 0x141a1ee58 | 14 |  |
| hkpGskfAgent | 0x141a1eef0 | 14 |  |
| hkpGunProjectile | 0x1419fb3c8 | 6 | 16: 0x1419fb400, 7 |
| hkpHavokSnapshot::ConvertListener | 0x1419f6948 | 4 |  |
| hkpHeightFieldAgent | 0x141a95f60 | 14 |  |
| hkpHeightFieldShape | 0x1419e7088 | 13 |  |
| hkpHingeConstraintData | 0x1419f2c78 | 19 |  |
| hkpHingeLimitsData | 0x1419f3930 | 19 |  |
| hkpIslandActivationListener | 0x141866678 | 3 |  |
| hkpIterativeLinearCastAgent | 0x141a199d8 | 14 |  |
| hkpKeyframedRigidMotion | 0x1419eb528 | 28 |  |
| hkpLimitedForceConstraintMotor | 0x1419f3e50 | 4 |  |
| hkpLimitedHingeConstraintData | 0x1419f2d88 | 19 |  |
| hkpLinearParametricCurve | 0x1419f2f30 | 14 |  |
| hkpListAgent | 0x141a1abc8 | 14 |  |
| hkpListShape | 0x1419eb078 | 13 | 32: 0x1419eb0e8, 7 |
| hkpMalleableConstraintData | 0x1419f5d58 | 19 |  |
| hkpMapPointsToSubShapeContactMgr | 0x141a11c10 | 10 |  |
| hkpMaxSizeMotion | 0x1419eb610 | 28 |  |
| hkpMeshShape | 0x141a16dc8 | 14 | 32: 0x141a16e40, 7 |
| hkpMoppAgent | 0x141a1a100 | 14 |  |
| hkpMoppAssembler | 0x141a98b88 | 7 |  |
| hkpMoppBvTreeShape | 0x1419e9dc0 | 14 |  |
| hkpMoppCachedShapeMediator | 0x141a98398 | 10 |  |
| hkpMoppCode | 0x141820be0 | 3 |  |
| hkpMoppCodeGenerator | 0x141a98b68 | 3 |  |
| hkpMoppCostFunction | 0x141a983f0 | 3 |  |
| hkpMoppDefaultAssembler | 0x141a98bc8 | 7 |  |
| hkpMoppDefaultSplitter | 0x141a98ab0 | 6 |  |
| hkpMoppMediator | 0x141a982e8 | 10 |  |
| hkpMoppModifier | 0x1419e9c38 | 3 |  |
| hkpMoppNodeMgr | 0x141a98a48 | 5 |  |
| hkpMoppShapeMediator | 0x141a98340 | 10 |  |
| hkpMoppSplitter | 0x141a98a78 | 6 |  |
| hkpMotion | 0x1419eb450 | 26 |  |
| hkpMotorAction | 0x1419fa0b8 | 8 |  |
| hkpMountedBallGun | 0x1419fb358 | 9 |  |
| hkpMouseSpringAction | 0x1419f6a78 | 8 |  |
| hkpMultiRayConvexAgent | 0x141a1a928 | 14 |  |
| hkpMultiRayShape | 0x1419ea430 | 11 |  |
| hkpMultiSphereAgent | 0x141a1af70 | 14 |  |
| hkpMultiSphereShape | 0x1419ea358 | 13 |  |
| hkpMultiSphereTriangleAgent | 0x141a1a808 | 14 |  |
| hkpMultiThreadedSimulation | 0x141a964b8 | 22 |  |
| hkpMultiThreadedSimulation::MtBroadPhaseBorderListener | 0x141a96498 | 3 |  |
| hkpMultiThreadedSimulation::MtEntityEntityBroadPhaseListener | 0x141a96458 | 3 |  |
| hkpMultiThreadedSimulation::MtPhantomBroadPhaseListener | 0x141a96478 | 3 |  |
| hkpNullAgent | 0x1419e7740 | 14 |  |
| hkpNullBroadPhaseListener | 0x141a0fe30 | 3 | 16: 0x141a0fe50, 3 |
| hkpNullCollisionFilter | 0x1419e6920 | 4 | 16: 0x1419e6948, 2, 24: 0x1419e6960, 4, 32: 0x1419e6988, 2, 40: 0x1419e69a0, 2 |
| hkpNullContactMgr | 0x1419f4e58 | 10 |  |
| hkpNullContactMgrFactory | 0x1419f4eb0 | 4 |  |
| hkpPairCollisionFilter | 0x1419f2700 | 4 | 16: 0x1419f2728, 2, 24: 0x1419f2740, 4, 32: 0x1419f2768, 2, 40: 0x1419f2780, 2 |
| hkpParametricCurve | 0x1419f2eb8 | 14 |  |
| hkpPhantom | 0x1419ebc68 | 15 |  |
| hkpPhantomAgent | 0x141a1a270 | 14 |  |
| hkpPhantomBroadPhaseListener | 0x1419f4f78 | 3 | 16: 0x1419f4f98, 3 |
| hkpPhantomCallbackShape | 0x1418270b0 | 13 |  |
| hkpPhantomListener | 0x141867d88 | 5 |  |
| hkpPhantomOverlapListener | 0x1419f5f20 | 3 |  |
| hkpPhysicsData | 0x1419fac20 | 3 |  |
| hkpPhysicsSystem | 0x1419f4a70 | 5 |  |
| hkpPhysicsSystemWithContacts | 0x1419fa790 | 5 |  |
| hkpPlaneShape | 0x1419e70f8 | 13 |  |
| hkpPointToPathConstraintData | 0x1419f3000 | 19 |  |
| hkpPointToPlaneConstraintData | 0x1419f30f0 | 19 |  |
| hkpPositionConstraintMotor | 0x1419f3f10 | 4 |  |
| hkpPoweredChainData | 0x141a11e48 | 20 |  |
| hkpPoweredChainMapper | 0x1419fa3b8 | 3 |  |
| hkpPredGskfAgent | 0x141a19958 | 14 |  |
| hkpPrismaticConstraintData | 0x1419ebe48 | 19 |  |
| hkpProjectileGun | 0x1419fb440 | 11 |  |
| hkpPulleyConstraintData | 0x1419f4080 | 19 |  |
| hkpRackAndPinionConstraintData | 0x1419f32a8 | 19 |  |
| hkpRagdollConstraintData | 0x1419f33d8 | 19 |  |
| hkpRagdollLimitsData | 0x1419f3a38 | 19 |  |
| hkpRayCollidableFilter | 0x1419e68c8 | 2 |  |
| hkpRayHitCollector | 0x1417fde30 | 2 |  |
| hkpRayShapeCollectionFilter | 0x1419e6908 | 2 |  |
| hkpRemoveTerminalsMoppModifier | 0x1419e9c58 | 3 | 16: 0x1419e9c78, 3 |
| hkpRemoveTerminalsMoppModifier2 | 0x1419eb158 | 3 | 16: 0x1419eb178, 3 |
| hkpReorientAction | 0x1419fa150 | 8 |  |
| hkpReportContactMgr | 0x1419f6278 | 19 |  |
| hkpReportContactMgr::Factory | 0x1419f6250 | 4 |  |
| hkpRigidBody | 0x1419ebbe8 | 8 |  |
| hkpRotationalConstraintData | 0x1419f3740 | 19 |  |
| hkpSafeEaseConstraintsAction | 0x141a8aaa8 | 8 | 104: 0x141a8aaf0, 7 |
| hkpSampledHeightFieldShape | 0x1419eab40 | 15 |  |
| hkpSaveContactPointsUtil::EntitySelector | 0x1419fb4a0 | 2 |  |
| hkpSerializedAgentNnEntry | 0x1419fa800 | 3 |  |
| hkpSerializedDisplayMarker | 0x1419fa958 | 3 |  |
| hkpSerializedDisplayMarkerList | 0x1419fa9b8 | 3 |  |
| hkpSerializedDisplayRbTransforms | 0x1419faa18 | 3 |  |
| hkpShape | 0x141826e68 | 11 |  |
| hkpShapeCollection | 0x1419eade8 | 13 | 32: 0x1419eae58, 7 |
| hkpShapeCollectionAgent | 0x141a1aee0 | 14 |  |
| hkpShapeCollectionFilter | 0x1419e68e0 | 4 |  |
| hkpShapeContainer | 0x1419e6b78 | 7 |  |
| hkpShapeInfo | 0x1419ea630 | 3 |  |
| hkpShapePhantom | 0x1419f45e8 | 19 |  |
| hkpSimpleClosestContactCollector | 0x141a19bd0 | 3 |  |
| hkpSimpleConstraintContactMgr | 0x1419f6168 | 20 |  |
| hkpSimpleConstraintContactMgr::Factory | 0x1419f6140 | 4 |  |
| hkpSimpleContactConstraintData | 0x1419f6090 | 21 |  |
| hkpSimpleMeshShape | 0x141a98958 | 13 | 32: 0x141a989c8, 7 |
| hkpSimpleShapePhantom | 0x1419f4778 | 19 |  |
| hkpSimpleWorldRayCaster | 0x1419f4f10 | 2 |  |
| hkpSimulation | 0x1419f4930 | 19 |  |
| hkpSimulationIsland | 0x1419f5e38 | 7 |  |
| hkpSingleShapeContainer | 0x1419e6bb8 | 7 |  |
| hkpSphereBoxAgent | 0x141a1a708 | 14 |  |
| hkpSphereCapsuleAgent | 0x141a1a370 | 14 |  |
| hkpSphereMotion | 0x1419eb828 | 26 |  |
| hkpSphereRepShape | 0x1419e6cf8 | 13 |  |
| hkpSphereShape | 0x1419e7178 | 18 |  |
| hkpSphereSphereAgent | 0x141a1a2e8 | 14 |  |
| hkpSphereTriangleAgent | 0x141a1a470 | 14 |  |
| hkpSpringAction | 0x1419fa1c8 | 8 |  |
| hkpSpringDamperConstraintMotor | 0x1419f3f78 | 4 |  |
| hkpStiffSpringChainData | 0x1419f5c10 | 20 |  |
| hkpStiffSpringConstraintData | 0x1419f3500 | 19 |  |
| hkpStorageExtendedMeshShape | 0x141a10478 | 15 | 32: 0x141a104f8, 7 |
| hkpStorageExtendedMeshShape::MeshSubpartStorage | 0x141a10438 | 3 |  |
| hkpStorageExtendedMeshShape::ShapeSubpartStorage | 0x141a10458 | 3 |  |
| hkpStorageMeshShape | 0x141a10378 | 14 | 32: 0x141a103f0, 7 |
| hkpStorageMeshShape::SubpartStorage | 0x141a10358 | 3 |  |
| hkpStorageSampledHeightFieldShape | 0x1419ead18 | 15 |  |
| hkpSuspendInactiveAgentsUtil | 0x141a8b060 | 3 | 16: 0x141a8b080, 3, 24: 0x141a8b0a0, 3 |
| hkpSymmetricAgentFlipBodyCollector | 0x141a19b18 | 3 |  |
| hkpSymmetricAgentFlipCastCollector | 0x141a19af8 | 3 |  |
| hkpSymmetricAgentFlipCollector | 0x141a19ad8 | 3 |  |
| hkpThinBoxMotion | 0x1419eb9d8 | 26 |  |
| hkpToiResourceMgr | 0x141a97f38 | 8 |  |
| hkpTransformAgent | 0x141a1aa40 | 14 |  |
| hkpTransformShape | 0x1419ea508 | 11 |  |
| hkpTriSampledHeightFieldBvTreeShape | 0x1419eae98 | 14 |  |
| hkpTriSampledHeightFieldCollection | 0x1419eaf10 | 13 | 32: 0x1419eaf80, 7 |
| hkpTriangleShape | 0x1419ea130 | 18 |  |
| hkpTriggerVolume | 0x1419fb010 | 5 | 16: 0x1419fb040, 7, 24: 0x1419fb080, 3, 32: 0x1419fb0a0, 6 |
| hkpUnaryAction | 0x1419ebf30 | 8 |  |
| hkpVelocityConstraintMotor | 0x1419f3fe0 | 4 |  |
| hkpWheelConstraintData | 0x1419f3630 | 19 |  |
| hkpWorld | 0x1419f4f58 | 3 |  |
| hkpWorldCinfo | 0x141823fc8 | 3 |  |
| hkpWorldDeletionListener | 0x1419f5f40 | 3 |  |
| hkpWorldExtension | 0x1419f63b0 | 5 |  |
| hkpWorldLinearCaster | 0x1419f4f40 | 2 |  |
| hkpWorldMaintenanceMgr | 0x1419f6318 | 6 |  |
| hkpWorldObject | 0x1419eb418 | 6 |  |
| hkpWorldPostSimulationListener | 0x1419189f8 | 3 |  |
| hkpWorldRayCaster | 0x1419f4f28 | 2 |  |
| hkxAnimatedFloat | 0x141a150f8 | 3 |  |
| hkxAnimatedMatrix | 0x141a15148 | 3 |  |
| hkxAnimatedQuaternion | 0x141a15198 | 3 |  |
| hkxAnimatedVector | 0x141a151e8 | 3 |  |
| hkxAttributeHolder | 0x141a15328 | 3 |  |
| hkxCamera | 0x141a15490 | 3 |  |
| hkxEdgeSelectionChannel | 0x141a15828 | 3 |  |
| hkxEnum | 0x141a15298 | 3 |  |
| hkxEnvironment | 0x141a1b2c0 | 3 |  |
| hkxIndexBuffer | 0x141a15a58 | 3 |  |
| hkxLight | 0x141a15598 | 3 |  |
| hkxMaterial | 0x141a155e0 | 3 |  |
| hkxMaterialEffect | 0x141a15698 | 3 |  |
| hkxMaterialShader | 0x141a156e8 | 3 |  |
| hkxMaterialShaderSet | 0x141a1b590 | 3 |  |
| hkxMesh | 0x141a1b5d0 | 3 |  |
| hkxMesh::UserChannelInfo | 0x141a15ad0 | 3 |  |
| hkxMeshSection | 0x141a15ab0 | 3 |  |
| hkxNode | 0x141a15528 | 3 |  |
| hkxNodeSelectionSet | 0x141a15c68 | 3 |  |
| hkxScene | 0x141a15ca8 | 3 |  |
| hkxSkinBinding | 0x141a15c88 | 3 |  |
| hkxSparselyAnimatedBool | 0x141a15258 | 3 |  |
| hkxSparselyAnimatedEnum | 0x141a152b8 | 3 |  |
| hkxSparselyAnimatedInt | 0x141a15278 | 3 |  |
| hkxSparselyAnimatedString | 0x141a152d8 | 3 |  |
| hkxTextureFile | 0x141a15798 | 3 |  |
| hkxTextureInplace | 0x141a157d8 | 3 |  |
| hkxTriangleSelectionChannel | 0x141a15880 | 3 |  |
| hkxVertexBuffer | 0x141a1b5b0 | 3 |  |
| hkxVertexFloatDataChannel | 0x141a158e0 | 3 |  |
| hkxVertexIntDataChannel | 0x141a15940 | 3 |  |
| hkxVertexSelectionChannel | 0x141a15998 | 3 |  |
| hkxVertexVectorDataChannel | 0x141a159f8 | 3 |  |

## Items and inventory (39 classes, 5 template classes left out)

From the MSVC RTTI of `SkyrimSE.exe`: 7,831 type descriptors (`.?AV...@@` in `.data`), 8,457 complete object locators and 7,159 classes with a vtable in `.rdata`. Here the classes of the inn's systems with their primary vtable (the one at offset 0 of the object) and how many virtual functions follow it before the next vtable (the count includes the slots of the base classes; a class's own slots come last). A secondary vtable (a base at another offset) is listed with that offset. Template classes (`BSTEventSink<...>`, `ConcreteFormFactory<...>`, the behavior tree's `CombatBehaviorTreeNodeObject<...>`) are left out; their count is in the system's heading. The vtable's slot k holds the address of the virtual function, so a function is found as the vtable's address plus 8 k, and `procedure_pseudo_code` on that address gives its code.

The layouts to read a slot by name: CommonLibSSE-NG's headers declare each class's virtual functions in vtable order (`IMenu`: 0 destructor, 1 Accept(CallbackProcessor), 2 PostCreate, 3 Unk_03, 4 ProcessMessage(UIMessage), 5 AdvanceMovie(interval, currentTime), 6 PostDisplay, 7 PreDisplay, 8 RefreshPlatform).

| class | vtable | slots | other vtables (offset: address, slots) |
|---|---|---|---|
| AlchemyItem | 0x1417df570 | 113 | 48: 0x1417df900, 6, 64: 0x1417df938, 6, 144: 0x1417df970, 7, 200: 0x1417df9b0, 7, 216: 0x1417df9f0, 4, 240: 0x1417dfa18, 4, 256: 0x1417dfa40, 6, 272: 0x1417dfa78, 4, 288: 0x1417dfaa0, 4 |
| BGSEquipSlot | 0x141854f98 | 59 |  |
| BGSEquipType | 0x1417f7d20 | 6 |  |
| BGSOutfit | 0x14180e338 | 59 |  |
| ExtraCharge | 0x1417e9c18 | 3 |  |
| ExtraContainerChanges | 0x1417ed310 | 3 |  |
| ExtraCount | 0x1417e9b38 | 3 |  |
| ExtraEnchantment | 0x1417e9fd8 | 3 |  |
| ExtraHealth | 0x1417e9bb8 | 3 |  |
| ExtraHealthPerc | 0x1417e9bd8 | 3 |  |
| ExtraHotkey | 0x1417e9c78 | 3 |  |
| ExtraLeveledItem | 0x1417e9d18 | 3 |  |
| ExtraLeveledItemBase | 0x1417e9e78 | 3 |  |
| ExtraOwnership | 0x1417e9ad8 | 3 |  |
| ExtraPoison | 0x1417e9fb8 | 3 |  |
| ExtraReferenceHandle | 0x1417e9cb8 | 3 |  |
| ExtraTextDisplayData | 0x1417ea638 | 3 |  |
| ExtraWorn | 0x1417e9b58 | 3 |  |
| ExtraWornLeft | 0x1417e9b78 | 3 |  |
| IngredientItem | 0x1417e22d0 | 113 | 48: 0x1417e2660, 6, 64: 0x1417e2698, 6, 144: 0x1417e26d0, 7, 200: 0x1417e2710, 7, 216: 0x1417e2750, 4, 232: 0x1417e2778, 6, 248: 0x1417e27b0, 4, 264: 0x1417e27d8, 4, 288: 0x1417e2800, 4 |
| Inventory3DManager | 0x1419778d8 | 8 |  |
| Inventory::StatInventoryVisitor | 0x141805930 | 4 |  |
| InventoryChanges::FindBestSoulGemVisitor | 0x14191dec0 | 4 |  |
| InventoryChanges::IItemChangeVisitor | 0x141805898 | 4 |  |
| InventoryUpdateData | 0x141984978 | 1 |  |
| InventoryUtils::ItemFilter | 0x141805880 | 2 |  |
| InventoryUtils::QuestItemFilter | 0x14180bfd0 | 2 |  |
| ScrollItem | 0x1417e52b0 | 113 | 48: 0x1417e5640, 6, 64: 0x1417e5678, 6, 144: 0x1417e56b0, 6, 160: 0x1417e56e8, 5, 176: 0x1417e5718, 4, 232: 0x1417e5740, 7, 288: 0x1417e5780, 4, 304: 0x1417e57a8, 4, 328: 0x1417e57d0, 4, 344: 0x1417e57f8, 4 |
| TESAmmo | 0x14180fc30 | 83 | 48: 0x14180fed0, 6, 64: 0x14180ff08, 7, 120: 0x14180ff48, 7, 136: 0x14180ff88, 4, 160: 0x14180ffb0, 4, 176: 0x14180ffd8, 4, 192: 0x141810000, 4, 208: 0x141810028, 4, 232: 0x141810050, 4, 248: 0x141810078, 6 |
| TESContainer | 0x1417f92a8 | 4 |  |
| TESKey | 0x1418123f0 | 86 | 48: 0x1418126a8, 6, 64: 0x1418126e0, 7, 120: 0x141812720, 7, 136: 0x141812760, 4, 152: 0x141812788, 4, 168: 0x1418127b0, 4, 184: 0x1418127d8, 4, 208: 0x141812800, 4, 232: 0x141812828, 6 |
| TESLevItem | 0x141813018 | 83 | 48: 0x1418132b8, 8 |
| TESLeveledList | 0x1417faaa8 | 8 |  |
| TESObjectARMO | 0x141816580 | 83 | 48: 0x141816820, 6, 64: 0x141816858, 4, 80: 0x141816880, 5, 104: 0x1418168b0, 4, 120: 0x1418168d8, 4, 136: 0x141816900, 4, 152: 0x141816928, 4, 176: 0x141816950, 4, 416: 0x141816978, 6, 432: 0x1418169b0, 4, 448: 0x1418169d8, 4, 472: 0x141816a00, 6, 496: 0x141816a38, 4 |
| TESObjectBOOK | 0x141816de0 | 83 | 48: 0x141817080, 6, 64: 0x1418170b8, 7, 120: 0x1418170f8, 7, 136: 0x141817138, 4, 152: 0x141817160, 4, 168: 0x141817188, 4, 184: 0x1418171b0, 4, 200: 0x1418171d8, 4, 224: 0x141817200, 4, 248: 0x141817228, 6 |
| TESObjectLIGH | 0x1418140f0 | 83 | 48: 0x141814390, 6, 64: 0x1418143c8, 7, 120: 0x141814408, 7, 136: 0x141814448, 4, 160: 0x141814470, 4, 176: 0x141814498, 4, 192: 0x1418144c0, 4, 208: 0x1418144e8, 6 |
| TESObjectMISC | 0x141818860 | 86 | 48: 0x141818b18, 6, 64: 0x141818b50, 7, 120: 0x141818b90, 7, 136: 0x141818bd0, 4, 152: 0x141818bf8, 4, 168: 0x141818c20, 4, 184: 0x141818c48, 4, 208: 0x141818c70, 4, 232: 0x141818c98, 6 |
| TESObjectWEAP | 0x14181a620 | 83 | 48: 0x14181a8c0, 6, 64: 0x14181a8f8, 7, 120: 0x14181a938, 7, 136: 0x14181a978, 5, 160: 0x14181a9a8, 4, 176: 0x14181a9d0, 4, 192: 0x14181a9f8, 5, 208: 0x14181aa28, 4, 224: 0x14181aa50, 6, 240: 0x14181aa88, 5, 248: 0x14181aab8, 4, 272: 0x14181aae0, 4, 296: 0x14181ab08, 4, 320: 0x14181ab30, 6, 344: 0x14181ab68, 4 |
| TESSoulGem | 0x14181b240 | 86 | 48: 0x14181b4f8, 6, 64: 0x14181b530, 7, 120: 0x14181b570, 7, 136: 0x14181b5b0, 4, 152: 0x14181b5d8, 4, 168: 0x14181b600, 4, 184: 0x14181b628, 4, 208: 0x14181b650, 4, 232: 0x14181b678, 6 |

## Menus and the UI (100 classes, 0 template classes left out)

From the MSVC RTTI of `SkyrimSE.exe`: 7,831 type descriptors (`.?AV...@@` in `.data`), 8,457 complete object locators and 7,159 classes with a vtable in `.rdata`. Here the classes of the inn's systems with their primary vtable (the one at offset 0 of the object) and how many virtual functions follow it before the next vtable (the count includes the slots of the base classes; a class's own slots come last). A secondary vtable (a base at another offset) is listed with that offset. Template classes (`BSTEventSink<...>`, `ConcreteFormFactory<...>`, the behavior tree's `CombatBehaviorTreeNodeObject<...>`) are left out; their count is in the system's heading. The vtable's slot k holds the address of the virtual function, so a function is found as the vtable's address plus 8 k, and `procedure_pseudo_code` on that address gives its code.

The layouts to read a slot by name: CommonLibSSE-NG's headers declare each class's virtual functions in vtable order (`IMenu`: 0 destructor, 1 Accept(CallbackProcessor), 2 PostCreate, 3 Unk_03, 4 ProcessMessage(UIMessage), 5 AdvanceMovie(interval, currentTime), 6 PostDisplay, 7 PreDisplay, 8 RefreshPlatform).

| class | vtable | slots | other vtables (offset: address, slots) |
|---|---|---|---|
| BSImagespaceShaderISLightingCompositeMenu | 0x141b3aa48 | 15 | 16: 0x141b3aac8, 2, 24: 0x141b3aae0, 1, 144: 0x141b3aaf0, 10 |
| BSScaleformFileOpener | 0x141a9b450 | 4 |  |
| BSScaleformImageLoader | 0x141a9af88 | 2 |  |
| BSScaleformMovieLoadTask | 0x141a9c860 | 107 |  |
| BSScaleformTranslator | 0x141a9aa10 | 4 |  |
| BSUIMessageData | 0x141915648 | 1 |  |
| BSUIScaleformData | 0x141a998a0 | 1 |  |
| BarterMenu | 0x14196f408 | 9 |  |
| BookMenu | 0x14196fd90 | 9 | 48: 0x14196fde0, 20, 72: 0x14196fe88, 2 |
| ConsoleNativeUIMenu | 0x1419711d8 | 9 |  |
| ContainerMenu | 0x141971a90 | 9 |  |
| ContentMenu | 0x1418eec08 | 1 |  |
| CraftingMenu | 0x141973868 | 9 |  |
| CraftingSubMenus::AlchemyMenu | 0x141973ff8 | 8 | 16: 0x141974040, 2 |
| CraftingSubMenus::ConstructibleObjectMenu | 0x141973a60 | 8 | 16: 0x141973aa8, 2 |
| CraftingSubMenus::CraftingSubMenu | 0x1419738b8 | 8 | 16: 0x141973900, 2 |
| CraftingSubMenus::EnchantConstructMenu | 0x141973df0 | 8 | 16: 0x141973e38, 2 |
| CraftingSubMenus::SmithingMenu | 0x141973c40 | 8 | 16: 0x141973c88, 2 |
| CreditsMenu | 0x141974498 | 9 | 48: 0x1419744e8, 2 |
| CursorMenu | 0x141974588 | 9 | 48: 0x1419745d8, 8 |
| DialogueMenu | 0x141974998 | 9 | 48: 0x1419749e8, 2 |
| FaderMenu | 0x141974c00 | 9 |  |
| FavoritesMenu | 0x141975188 | 9 | 48: 0x1419751d8, 8 |
| GFxExternalInterface | 0x141a9c2a8 | 2 |  |
| GFxFileOpenerBase | 0x141a9b428 | 4 |  |
| GFxFunctionHandler | 0x1418ef260 | 2 |  |
| GFxImageLoader | 0x141a9af70 | 2 |  |
| GFxLog | 0x141a9aa50 | 2 | 24: 0x141a9aa68, 2 |
| GFxState | 0x141a9a998 | 1 |  |
| GFxTranslator | 0x141a9a9a8 | 4 |  |
| GFxZlibSupport | 0x141a9a9f0 | 3 |  |
| GFxZlibSupportBase | 0x141a9a9d0 | 3 |  |
| GiftMenu | 0x141975538 | 9 |  |
| HUDChargeMeter | 0x141976890 | 5 |  |
| HUDData | 0x1419847e8 | 1 |  |
| HUDMenu | 0x141976708 | 9 | 48: 0x141976758, 2, 56: 0x141976770, 2 |
| HUDMeter | 0x1419767e8 | 6 |  |
| HUDNotifications | 0x1419767b8 | 5 |  |
| HUDObject | 0x141976788 | 5 |  |
| IMenu | 0x141a9a1f0 | 9 |  |
| InventoryMenu | 0x141978208 | 9 |  |
| JournalMenu | 0x141989d98 | 9 | 48: 0x141989de8, 8, 64: 0x141989e30, 2 |
| KinectMenu | 0x1418f4df0 | 9 | 48: 0x1418f4e40, 2 |
| LevelUpMenu | 0x1419788b0 | 9 |  |
| LoadingMenu | 0x141978d40 | 9 |  |
| LockpickingMenu | 0x141979a10 | 9 | 48: 0x141979a60, 8, 64: 0x141979aa8, 2 |
| LoginMenu::loginMenu | 0x1418ef3c0 | 9 | 48: 0x1418ef410, 2 |
| MagicItemData | 0x14197a7b8 | 7 |  |
| MagicItemDataCollector | 0x1418f6308 | 2 |  |
| MagicMenu | 0x14197a7f8 | 9 |  |
| MainMenu | 0x14197b570 | 9 | 48: 0x14197b5c0, 2, 56: 0x14197b5d8, 2, 64: 0x14197b5f0, 2 |
| MapMenu | 0x141987248 | 9 | 48: 0x141987298, 2, 56: 0x1419872b0, 3 |
| MarketplaceMenu | 0x1418f0370 | 9 | 48: 0x1418f03c0, 2 |
| MenuControls | 0x14197c1e8 | 2 | 8: 0x14197c200, 2 |
| MenuEventHandler | 0x1418f02e0 | 8 |  |
| MenuOpenHandler | 0x14197c350 | 8 |  |
| MenuTopicManager | 0x1418fea40 | 2 | 8: 0x1418fea58, 2 |
| MessageBoxMenu | 0x14197c788 | 9 |  |
| MistMenu | 0x14197dda0 | 9 | 48: 0x14197ddf0, 20, 72: 0x14197de98, 8 |
| ModManagerMenu | 0x1418f4630 | 9 | 48: 0x1418f4680, 8, 64: 0x1418f46c8, 2 |
| RaceSexMenu | 0x14197edb0 | 9 | 48: 0x14197ee00, 8 |
| SafeZoneMenu | 0x14197f198 | 9 |  |
| ScaleformFile::MemoryFile | 0x141a9b4b0 | 19 |  |
| SleepWaitMenu | 0x14197f4e8 | 9 |  |
| StandardItemData | 0x14196f3c8 | 7 |  |
| StatsMenu | 0x141980128 | 9 | 48: 0x141980178, 8 |
| StreamingInstallMenu | 0x141980998 | 1 |  |
| TitleSequenceMenu | 0x141980e48 | 9 |  |
| TrainingMenu | 0x141981158 | 9 | 48: 0x1419811a8, 2 |
| TutorialMenu | 0x141981508 | 9 |  |
| TweenMenu | 0x1419818b8 | 9 |  |
| UIBlurManager | 0x1419844a0 | 2 |  |
| UISaveLoadManager | 0x141985120 | 2 | 8: 0x141985138, 2 |
| UI_Button3 | 0x141b59cc8 | 14 |  |
| UI_Dialog | 0x141b5ab68 | 15 |  |
| UI_DialogDownloadCC | 0x141b5aec8 | 15 |  |
| UI_DialogMessage | 0x141b5a1e8 | 15 |  |
| UI_DialogYesNo | 0x141b59938 | 15 |  |
| UI_MarkdownText | 0x141b5adc8 | 14 |  |
| UI_ScrollingList | 0x141b5b570 | 29 |  |
| UI_Text | 0x141b59f80 | 15 |  |
| UI_Text2 | 0x141b5abe8 | 14 |  |
| UI_Text3 | 0x141b599b8 | 15 |  |
| UI_bannerEntry | 0x141b5bcc8 | 18 |  |
| UI_bar | 0x141b5aaf0 | 14 |  |
| UI_bottomBar | 0x141b59790 | 14 |  |
| UI_button2 | 0x141b5ac60 | 14 |  |
| UI_detailsPage | 0x141b58240 | 21 |  |
| UI_detailsPage::OnSale | 0x141b583a0 | 14 |  |
| UI_element | 0x141b59808 | 14 |  |
| UI_element2 | 0x141b5ad50 | 14 |  |
| UI_homePage | 0x141b5a5a8 | 21 |  |
| UI_image | 0x141b5a000 | 14 |  |
| UI_image2 | 0x141b5acd8 | 14 |  |
| UI_image3 | 0x141b59880 | 14 |  |
| UI_listEntry | 0x141b5bb88 | 18 |  |
| UI_listEntry::OnSale | 0x141b5bb10 | 14 |  |
| UI_page | 0x141b59d88 | 21 |  |
| UI_tag | 0x141b5b998 | 14 |  |
| UI_topBar | 0x141b5b818 | 14 |  |

## Animation: the names the executable uses with the behavior graph

Read from `SkyrimSE.exe` 1.7.104 with REA. The graph itself (0_master.hkx and the behaviors) is
read by `skyrim/hkx/graph.zap`; what the executable adds is the set of node names, graph variables
and events it writes and listens to. They are one static table of BSFixedStrings
(`FixedStrings`, built by 0x140224be0, called from 27 places; one BSFixedString per 8 bytes), so
a port that keeps the graph's own names needs exactly these.

### The table (offset: name)

Node names: 0x00 "NPC Root [Root]", 0x08 "NPC", 0x10 "NPC Head [Head]", 0x18 "NPC Pelvis [Pelv]",
0x20 "NPC Spine [Spn0]", 0x28 "NPC Spine1 [Spn1]", 0x30 "NPC Spine2 [Spn2]", 0x38 "NPC L Foot
[Lft ]", 0x40 "NPC R Foot [Rft ]", 0x48 "NPC L Calf [LClf]", 0x50 "NPC R Calf [RClf]", 0x58
"SpecialIdle_Cast", 0x60 "SpecialIdle_AreaEffect", 0x68 "AttachSound", 0x70 "Sound Marker", 0x78
"Skinned Decal Node", 0x80 "Decal Node", 0x88 "ModelSwapNode", 0x90 "Open", 0x98 "Close", 0xa0
"DVPG", 0xa8 "Prn", 0xb0 "Weapon", 0xb8 "WeaponSword", 0xc0 "WeaponDagger", 0xc8 "WeaponAxe",
0xd0 "WeaponMace", 0xd8 "Shield", 0xe0 "WeaponBack", 0xe8 "WeaponBow", 0xf0 "Quiver", 0xf8
"EditorMarker", 0x100..0x110 "EditorMarker:0..2", 0x118 "ArrowQuiver", 0x120 "MarkerSource",
0x128 "MarkerTarget", 0x130 "AttachLight", 0x138 "skin", 0x140 "FaceGenEars", 0x148 "Unequip",
0x150 "LaserSight", 0x158 "AimSight", 0x160 "Decal", 0x168 "Permanent Decal", 0x170 "grabLeft",
0x178 "grabRight", 0x180 "Arrow:0", 0x188 "ArrowBone", 0x190 "BSFaceGenNiNodeSkinned", 0x198
"EntryPoint", 0x1a0 "NPC L UpperArm [LUar]", 0x1a8 "NPC L Forearm [LLar]", 0x1b0 "NPC R UpperArm
[RUar]", 0x1b8 "NPC LookNode [Look]", 0x1c0 "NPC Tail1", 0x1c8 "NPC TailHub", 0x1d0 "NPC Pelvis",
0x1d8 "Talking", 0x1e0 "Camera1st [Cam1]", 0x1e8 "Camera3rd [Cam3]", 0x1f0
"HeadMeshForExport_FaceGenAndMorphs:0", 0x1f8 "PinnedLimb", 0x200 "Backpack", 0x208
"ProjectileNode", 0x210 "BlastRadiusNode", 0x218 "TorchFire", 0x220 "##LightOn", 0x228 "NPC COM
[COM ]", 0x230 "SkinAttachment", 0x238 "NPC Neck [Neck]", 0x240 "##NifRound", 0x248 "Scb", 0x250
"UpperBody", 0x258 "##LightOff", 0x260 "NPC Head MagicNode [Hmag]", 0x268 "NPC L MagicNode
[LMag]", 0x270 "NPC R MagicNode [RMag]", 0x278 "MagicLeft", 0x280 "MagicRight", 0x288
"MagicOther", 0x290 "Camera Control", 0x298 "NPC Root [Root]", 0x2a0 "SaddleBone", 0x2a8
"PerchFireNode", 0x2b0 "GraphDeleting".

Graph variables (the game sets them; the behaviors read them): 0x2b8 IsBlocking, 0x2c0
IsShouting, 0x2c8 IsPlayer, 0x2d0 IsNPC, 0x2d8 iIsPlayer, 0x2e0 fScale, 0x2e8 FemaleOffset, 0x2f0
IsFirstPerson, 0x2f8 i1stPerson, 0x300 fIsFirstPerson, 0x308 bHumanoidFootIKEnable, 0x310
iSyncIdleLocomotion, 0x318 iSyncTurnState, 0x320 IsAttackReady, 0x328 bVoiceReady, 0x330
bMLh_Ready, 0x338 bMRh_Ready, 0x340 bEquipOk, 0x350 IsSprinting, 0x358 iSyncSprintState, 0x360
weapAdj, 0x368 weaponSpeedMult, 0x370 leftWeaponSpeedMult, 0x378 BowZoom, 0x380 bBowZoomed, 0x388
iLeftHandType, 0x390 iRightHandType, 0x398 iLeftHandEquipped, 0x3a0 iRightHandEquipped, 0x3a8
bLeftHand, 0x3b0 bRightHand, 0x3b8 fIdleTimer, 0x3c0 Injured, 0x3c8 Land, 0x3d0 bCrashLand, 0x3d8
LandTypeIndex, 0x3e0 ActorResponse, 0x3e8 PlayerCharacterResponse, 0x3f0 TailPitchCurrent, 0x3f8
TailPitchMax, 0x400 TailYawCurrent, 0x408 TailYawMax, 0x410 LookAtHeadingMaxAngle, 0x4a0
fCastStrength, 0x4a8 staggerMagnitude, 0x4b0 staggerDirection, 0x4b8 IsBusy, 0x4c0 Imod, 0x4c8
Rimod, 0x4d0 DistToGoal, 0x500 VelocityZ, 0x508 Speed, 0x510 TurnDelta, 0x518 Direction, 0x520
SpeedSampled, 0x528 HorseSpeedSampled, 0x530 LookAtOutOfRange, 0x538 AimHeadingMax, 0x540
AimPitchMax, 0x548 AimHeadingCurrent, 0x550 AimPitchCurrent, 0x558 iSyncForwardState, 0x560
iSyncStrafeState, 0x568 bAnimationDriven, 0x570 bAllowRotation, 0x578 bIsSynced, 0x580
bSpeedSynced, 0x588 bDisableInterp, 0x590 iGetUpType, 0x5a0 fFlameProjectileLength, 0x5b0
bAimActive, 0x5b8 TurnDynamic, 0x5c0 bForceIdleStop, 0x5c8 ConstraintOffset.

Events and annotations (the graph sends them, the game listens, or the game sends them): 0x348
HitFrame, 0x418 English, 0x420 Russian, 0x428 Polish (the lip-sync language variants), 0x430
MLh_SpellFire_Event, 0x438 MRh_SpellFire_Event, 0x440 Voice_SpellFire_Event, 0x448 arrowRelease,
0x450 EndAnim, 0x458 StopEffect, 0x460 TweenEntryDirection, 0x468 TweenPosition, 0x470
TweenRotation, 0x478 HasTweenSpeed, 0x480 TweenSpeed, 0x488 bTweenUpdate, 0x490 TargetLocation,
0x498 MovementDirection, 0x4d8 preHitFrame, 0x4e0 weaponSwing, 0x4e8 weaponLeftSwing, 0x4f0
AttackWinStart, 0x4f8 AttackWinEnd, 0x598 ObjectActivated, 0x5a8 PairedKillTarget, 0x5d0 Left,
0x5d8 PickUp, 0x5e0 PathTweenerStart, 0x5e8 PathTweenerEnd.

The strings' addresses (REA `search_strings`): IsBlocking 0x141803dc8 ... bAimActive 0x141804408,
Speed 0x14180427c, TurnDelta 0x141804288, Direction 0x141804298, SpeedSampled 0x1418042a8,
staggerMagnitude 0x1418041c8, staggerDirection 0x1418041e0, iState 0x141a06360 (the
BShkbAnimationGraph's own, not in this table), bWantCastLeft/Right 0x14191c1e8/f8, iWantBlock
0x14191c3e8, bHeadTracking 0x14191c3f8, bInJumpState 0x14191c5e8 (the Actor's own set).

### What this settles for the port

- `game/graph.zap` feeds `Speed`, `TurnDelta`, `Direction` and `SpeedSampled` (the Walker) and
  `iSyncIdleLocomotion`, `iSyncTurnState`, `iSyncForwardState`, `iSyncStrafeState`,
  `iSyncSprintState` (the sync points the port still sets by hand are these integer variables:
  the graph's blenders sync by state index, the game only sets the integers).
- The stagger goes into the graph as `staggerMagnitude` and `staggerDirection` (the formula in
  `combat.md`) before the `staggerStart` event.
- The spells' timing events are `MLh_SpellFire_Event`, `MRh_SpellFire_Event`,
  `Voice_SpellFire_Event`; the attacks' `preHitFrame`, `HitFrame`, `weaponSwing`,
  `weaponLeftSwing`, `AttackWinStart`, `AttackWinEnd`, `arrowRelease`.

### The graph's data channels

The per-frame variables are not written by one function: 0x1406b0650 registers on an actor's graph
a list of `BSTAnimationGraphDataChannel<Actor, float, X>` objects, each named by a `FixedStrings`
entry (the table's getter is 0x1401544f0, its static at 0x14219df30), polled every frame
(vtable slot 1) and written into the graph (slot 2, the graph's virtual +0x80 SetVariable):

- `ActorSpeedChannel` (`Speed`, vtable 0x14191c240, 0x1407c6a10): the movement controller's speed
  (0x1406af0d0) over the actor's scale (0x1402e6f30, 1 under 1.2e-7); crossing 5.0 upward queues
  the default object 0x61 (Action Move Start), downward 0x62 (Action Move Stop).
- `ActorTurnDeltaChannel` (`TurnDelta`, 0x14191c2e0, 0x1407c6be0): the rotation speed times
  -57.29578 (degrees, the sign flipped); |TurnDelta| rising past 1 degree queues 0x64 Action Turn
  Left when positive, 0x63 Action Turn Right when not; falling under it 0x65 Action Turn Stop.
- `ActorDirectionChannel` (`Direction`, 0x14191c2c0, 0x1407c6d60): the movement controller's wanted
  direction from the facing (0x1406af1b0) wrapped to 0..2 pi, times 1 / 2 pi; crossing 0.25 or 0.75
  queues 0x66 Action Move Forward or 0x67 Move Backward, crossing 0 or 0.5 0x69 Move Right or 0x68
  Move Left.
- Others registered there: `TargetSpeed`, `Pitch`, `Roll`, `PitchDelta`, the weapon speeds.

The queued ids index the default object table (0x14219d1a0, built by 0x14031b830; the names
"Action Move Start".. "Action Move Right" in that order) and 0x1406f31a0 runs each action, which
reaches the graph as an event through the IDLE records. Ported in `game/graph.zap`'s `stepWalker`.

### Not read

The `BShkbAnimationGraph` virtuals (vtable 0x141a07d78, 14 slots) and
`hkbBehaviorGraph`'s (0x1419c09f0, 28 slots), and the 0x14190f898-vtable class holding
`sBasePath` (the animation file manager's root).

## Combat: what the executable computes that the records do not say

Read from `SkyrimSE.exe` 1.7.104 with REA. The behavior tree's weights and nodes are already in
`game/combat/chances.zap` and `projects/skyrim/README.md` (addresses 0x1408f1xxx..0x1408f3xxx); here what was still by
hand: the stagger, the confidence modifier, and the method that finds a setting's readers.

### Finding a setting's readers

A `SettingT` object is 24 bytes: vtable, value, name pointer (`settings.md`). The code reads the
value at `object + 8`, so REA's `xrefs` on that address lists the readers (an `xrefs` on the
object itself only gives its static initializer). Checked on fCombatAttackChanceMin: `xrefs
0x1420a1738` gives 0x1408f2742, inside the Attack node 0x1408f2720 chances.zap names.

### The stagger magnitude (0x1407f0690)

`staggerOf(attacker, target, weapon, given)`: `attacker`/`target` are actors (their
`ActorValueOwner` is at `actor + 0xb8`, slot 1 reads an actor value: 9 Block, 0x24 Mass, 0x57
WardPower), `weapon` the attacking `TESObjectWEAP` (0 for an unarmed or spell hit), `given` a
magnitude passed in (0 to compute one). The settings are the game settings (`gmst-floats-m-z.md`
has their defaults).

1. The base:
   - when the attacker is an actor that is blocking (0x1406cba10): 0x14041f230, the block
     stagger:
     `((Block * fStaggerAttackMult + fStaggerAttackBase) / (targetMass * fStaggerMassMult + fStaggerMassBase)) * state * weaponMult * shieldFactor`,
     with Block the attacker's Block skill and targetMass the target's Mass actor value; `state`
     is 1, or fStaggerRecoilingMult when the target's flags `+0xcc & 0xc00` (recoiling), times
     fStaggerRunningMult when the target runs (0x1406742a0), times fStaggerBlockingMult when the
     target blocks (0x1406aef60); `weaponMult` is fStaggerShieldMult when the attacker holds a
     shield (0x1406ca230), else fStagger2WeapMult for a two-handed weapon type (weapon `+0x19d`
     in 5..7, or 9), else fStagger1WeapMult, else 1 with nothing equipped; `shieldFactor` is the
     current attack's `BGSAttackData` `+0x34` (0x1406ca270 gives the attack data; its `Data` at
     `+0x18` has `staggerOffset` at `+0x1c`: the race's ATKD stagger of the attack, 0.5 for the
     Nord's bashStart). Floor fStaggerMin.
   - else 0x14041f5e0, the hit stagger: `targetMass` as above, times fStaggerPlayerMassMult when
     the target is the player (`DAT_1431df300`); `base = 1 / (targetMass * fStaggerMassMult +
     fStaggerMassBase)` (1 when that is under 0.0001), times `given` when given, else times the
     weapon's `+0x188` (the WEAP DNAM's stagger value, 1 without a weapon) times the attack's
     ATKD stagger (0x1406ca270's `+0x34`, as above: the Nord's 0 for attackStart, 1 for
     attackPowerStartForward, 0.5 for the fists' power attack); plus the attacker's WardPower
     (actor value 0x57) when the weapon type `+0x19d` is 7 or 9 (a staff or a bow... the two
     values with `(type - 7) & 0xfd == 0`); minus `max(0, (targetMass - fStaggerMassOffsetBase) *
     fStaggerMassOffsetMult)`.
2. When the base is positive, no magnitude was given, the target is a blocking actor
   (0x1406aef60) with a block timer `+0xe8 >= 0`: the target's shield (0x1406ca230) gives
   `shieldRating = shield->+0x200 * 0.01` (the ARMO's armor rating field), else with no shield
   and the target's `+0xcc & 0xe0 > 0x5f` (weapon drawn) the equipped weapon's block rating
   through 0x14028c140 (0x140720660 reads the right hand); then
   `blockTerm = fStaggerBlockAttackShieldMult * shieldRating + fStaggerBlockAttackShieldBase +
   fStaggerBlockMult * Block + fStaggerBlockBase + max(0, (Mass - fStaggerMassOffsetBase) *
   fStaggerMassOffsetMult)` (0x14041f560, with the target's Block skill and Mass) and
   `result = max(fStaggerMin, base - blockTerm)`.

With the defaults (fStaggerMassBase 0, fStaggerMassMult 1, offset base 3 and mult 0.15, block
base 0.5 and mult 0.005, shield base 1 and mult -0.005): an unblocked power attack on a mass-1 NPC
staggers by the weapon's stagger value, a plain attack not at all (the Nord's ATKD stagger is 0),
less 0 for a mass under 3; a block takes off at least 1.5. Ported: `game/combat/damage.zap`'s
`hitStagger`, `bashStagger` and `blockedStagger`, the race's ATKD read by `records.zap`.

### The confidence modifier

0x140855990 is the constructor of the per-actor combat state object (0x2f dwords; `+0x00` 100.0,
`+0x04` 0x10000, `+0x98` the owner): it draws once `[0x1c] = random(fCombatConfidenceModifierMin,
fCombatConfidenceModifierMax)` (-0.5..0.5) and `[0xe] = random(fCombatDialogueTauntMinElapsedTime,
fCombatDialogueTauntMaxElapsedTime)` (3..10 s, the next taunt), `[0xd] = [0x2d] = DAT_14324430c`
(the game's clock), `[0x2e] = 0.1`. 0x1401d6e40(min, max) is the random-in-range used across the
combat code. The modifier is added to the actor's confidence when the flight decision is made;
the decision itself (the node reading `+0x1c`) was not followed.

### CombatTargetSelector (vtable 0x141955910)

Seven slots: 0x140862b70 (destructor), 0x140eebf20, 0x140861f40 (the class name), 0x140861db0
and 0x140861e80 (save and load), 0x140861da0, 0x1415a97c8. CombatTargetSelectorStandard
(constructor 0x140861fc0) picks in 0x140862040: when its target is no longer valid, or
`clock - lastCheck > wait`, it runs 0x1408622e0 and sets `wait` to fCombatSelectTargetUpdateTime
(1.0) when the pick is unchanged, fCombatSelectTargetSwitchUpdateTime (3.0) when it changed.
0x1408622e0 walks the combat group's targets (valid by 0x1408629a0) and keeps the highest score,
from -FLT_MAX; with one target the score is 0, else the sum of (static floats 0x1420b9d90..dc0):

- the combat memory of the pair (0x1406a22d0) when its time `+0x38` is within 2.0 s: 1000 when its
  flag `+0x15` is set, else 1000 when the target is the current one and `+0x18` is within 2.0 s;
  plus 100 when its flag `+0x14` is set;
- 100 when it is the current target;
- 100 when both are melee or both not (0x140868df0: no weapon, or a WEAP of animation type < 7);
- `(1 - min(distance, 2048) / 2048) x 1000`, the distance 2048 in another worldspace (0 for the
  current target);
- 0x143254ba8 (BSS, written by no code: 0) when the target's attacker count exceeds one;
- 2000 less when it is not detected (0x140563180) within fCombatRangedDistance 1024 or across
  worldspaces, 2500 less when unreachable across worldspaces;
- 500 less when its virtual 0x4c8 says so, 500 less when 0x140691aa0 (fleeing: its combat
  controller's state, or a flee package of type 0x16 or 0x0a).

Ported in `game/combat/select.zap`, the two flags read as "the target hurt the fighter" and "the
fighter hurt the target", detection as fSneakMaxDistance.

### The block share (0x14041f4d0) and the hit (0x1407f09d0)

`blockShare(rating, block, shieldPerks, armed, unarmed, power)`: the skill's factor is
`lerp(fArmorRatingBase, fArmorRatingMax, Block * 0.01)`; with a shield (neither flag set)
`(factor + shieldPerks) * rating * fShieldScalingFactor * 0.01 + fShieldBaseFactor`, `rating` the
shield's armor rating (ARMO `+0x200` x 0.01); with a weapon `factor * damage * fBlockWeaponScaling
* 0.01 + fBlockWeaponBase`, `damage` the attacking weapon's (its `+0xc0` slot 0x20); times
fBlockPowerAttackMult against a power attack. The hit (0x1407f09d0) then runs the perk entry point
0x27 over it, caps it at `fPlayerMaxResistance * 0.01` and multiplies the damage by `1 - share`;
fBlockMax is read by no code. The same function takes the armor off before: `rating *
fArmorScalingFactor * 0.01` plus the actor's slot 0x738 (the pieces' base factor), the perk entry
0x25, capped at `fMaxArmorRating * 0.01`, the damage times `1 - that`. The plugin's GMSTs overwrite
these static settings' values at load (fShieldBaseFactor 0.45, fMaxArmorRating 80...). Ported in
`game/combat/damage.zap`.

### The barter factor (0x140420be0)

Called by the barter menu's show (0x140900580) with the player's Speechcraft (actor value 0x11):
`buy = max(lerp(fBarterMax, fBarterMin, Speech * 0.01), fBarterBuyMin)`, `sell = min(1 / buy,
fBarterSellMax)`; the menu then applies the perk entry points 8 and 0x3c and clamps buy at least
fMinBuyMult and sell at most fMaxSellMult before `SetBarterMultipliers(buy, sell)`. Ported in
`game/sim/economy.zap`.

### Flight (0x140856ce0)

The combat state (0x140855990's object) keeps the actor's Confidence actor value (index 1: 0
Cowardly .. 4 Foolhardy) at `+0x6d`, the modifier drawn at its start (fCombatConfidenceModifierMin
.. Max) at `+0x70`, its own damage a second at `+0x78` and threat at `+0x74` (0x140856ac0), and at
`+0` the threat ratio (0x140856b90, 100 by default): its combat group's threat (0x14081f830, the
members' `+0x74`) over the group's targets' threat (`+0xd0`, summed by 0x14081f4d0). 0x140856ce0
decides: true (flee) when the actor is in bleedout (its virtual 0x2f0, or life state bits), else
when `threshold(level + modifier) > ratio` (the modifier skipped at levels 0 and 4), where
0x1401dea40 reads the table at 0x1420781e8 (fConfidenceCowardly, Cautious, Average, Brave,
Foolhardy) between whole levels, the level clamped to 0..4. "Boost Confidence" (0x140856a80) raises
the level by one when it is under 4 and its threshold under 100. A threat (0x1406c9130) is
`dps / (1 - min(0.99, fArmorScalingFactor x DamageResist x 0.01 + the actor's base armor factor))
x Health`; the damage a second (0x1406cc570) the equipped items' 0x14086b020: a weapon's damage
(0x14041e9b0) x its speed (`+0x170`) x fCombatDPSMeleeSpeedMult (fCombatDPSBowSpeedMult for a bow
or crossbow), the unarmed "weapon" without one. fAIFlee* and the fConfidence* settings' own names
are read by no code: the table is reached through 0x1420781e8. Ported in `game/combat/flee.zap`.

## Eating, drinking and active effects in SkyrimSE.exe

Read in the decompilation (C:/tools/skyrim-decomp), addresses are the exe's. Ported in
`game/sim/consume.zap`; tests in `consumetests.zap`.

### Using an item

- `ActorEquipManager::EquipObject` 0x1406dc310 -> 0x1406de920 -> 0x1406b2570: a switch on the form
  type byte at +0x1a. Case 0x2e (AlchemyItem): refuse a quest item ("You can not eat quest items"),
  send the equip event, then `vfunc 0x308` (`AlchemyItem::IsPoison`): a poison opens the poison
  application (string ITMPoisonUse, 0x140749190); anything else calls `Actor::DrinkPotion` (Actor
  vtable slot 0x10F, offset 0x878) and, when it returns true, removes one of the item (slot 0x518).
- `Actor::DrinkPotion` 0x1406d5890 (the player's override 0x14075c250 calls it, then updates every
  gathered effect once more with 0 s): gets the actor's magic caster for casting source 3 (instant),
  casts the item on the actor (vfunc 0x2b0), and registers a created potion (0x14063f650).
- `AlchemyItem::IsFood` 0x1401468b0: food flag (0x2) set and not poison. IsPoison 0x140146940:
  flag 0x20000. IsMedicine 0x140146910: flag 0x10000. ENIT: cost override, flags, addiction,
  addiction chance, consumption sound (SNDR) at +16.

### ActiveEffect (0x90 bytes; CommonLibSSE-NG's layout)

- `ActiveEffect::Update` 0x1405bcde0: the first call runs `Start` (vtable 0xa0); then elapsed +=
  dt, but when duration > 0 and elapsed + dt > duration the dt is cut to what is left and elapsed
  = duration; then `Update` (vtable 0x20); the effect ends when the MGEF has the NoDuration flag
  (0x200) or duration <= elapsed, which runs `Finish` (0xa8).
- `ActiveEffect::GetMagnitude` 0x1405bb0a0 -> `GetTaperedMagnitude` 0x1404220e0 (magnitude, seconds
  left, taper duration, taper weight, taper curve): with fewer seconds left than the taper
  duration, magnitude x (left / duration)^curve x weight. MGEF DATA at 28, 52, 56. The taper is
  zero when the MGEF has NoMagnitude or NoDuration (0x600).
- `ActiveEffect::SetEffectiveness` 0x1405bada0: scales magnitude and duration by a power factor
  (1 for potions).

### ValueModifierEffect (archetype 0; Peak is 0x22 = 34)

- Constructor 0x1405e6dd0: the actor value is the MGEF's primary AV (+0xc4; out of 0..0xa4 becomes
  health); an MGEF with NoMagnitude (0x400) has magnitude 1.0.
- `Func1` 0x1405e7050 (OnAdd): the magnitude is negated when the MGEF is detrimental (flag 0x4)
  differs from the actor value's "inverted" bit (AV info +0x60 bit 9, none of those the model
  plays): harm lowers.
- `ShouldModifyOnStart` 0x1405e7170: true for a Recover MGEF (flag 0x2); otherwise when the effect's
  duration is 0 and the effect is not constant-like (0x1405e70e0: a concentration spell, a disease,
  an ability, or the enchanting flag).
- `ModifyOnStart` 0x1405e71d0: magnitude = GetMagnitude(); for the skills and attributes (AV 6..23,
  25..38, not health 24) a lowering (<= 0) is cut to what the value has; stores it as the effect's
  magnitude, then `ModifyActorValue` 0x1405e7630.
- `ShouldModifyOnUpdate` 0x1405e72f0: false for Recover; else true when the duration is not 0 or the
  effect is constant-like. `ModifyOnUpdate` 0x1405e7340 changes by GetMagnitude() x dt.
- `ShouldModifyOnFinish` 0x1405e7410: the Recover flag. `ModifyOnFinish` 0x1405e7430: for a positive
  value, first `FUN_1405e7ab0` (the cut of a lowering) and, for health when the current health is
  within 1 of the value, 1 more, given back as damage (type 2); then `ModifyActorValue` of the
  negated value.
- `ModifyActorValue` 0x1405e7630: Recover -> `FUN_1406c5220(actor, 1, av, value)` (the temporary
  modifier); otherwise a negative health change goes the hurt path (0x1406797c0), everything else
  `FUN_1406c5220(actor, 2, av, value)` (the damage modifier: kept <= 0, so a restore never goes
  above the maximum).
- Peak 0x1405d9ec0..0x1405da550: among the active effects of the same MGEF and actor value only the
  strongest is applied; the others are suspended (flag 0x400) and take over in turn.

### Not found

- The place that plays the item's consumption sound. `ActiveEffect::ApplySoundEffects` 0x1405bd510
  plays the MGEF's own sound slot 5 (a loop), not the ENIT sound.

## The dialogue: MenuTopicManager and the dialogue menu

Read from `SkyrimSE.exe` 1.7.104 with REA (`procedure_pseudo_code` of the functions named here).
The menu side (callbacks, messages, the topic list's filling) is in `menus.md`; here the manager
that owns the conversation. `game/dialogue/` and `game/talk.zap` are the port's reading of the
plugin's records; this is how the executable walks them.

### MenuTopicManager (singleton `DAT_1431df408`, vtable 0x1418fea40)

| offset | what |
|---|---|
| +0x18 | the current topic node (a linked list node: `[0]` the topic entry, `[1]` next) |
| +0x20 | the topic list's head |
| +0x30 | the current response (`DialogueResponse`-like, or 0) |
| +0x38 | the current `DialogueItem` (0x58 bytes, made by 0x1405ed830 from the topic's quest `+0x28`, topic `+0x50`, info `+0x30` and the speaker) |
| +0x40 | the critical section every menu call takes |
| +0x68 | the speaker's handle (0x14017ebe0 resolves it; a form of type 0x3e ACHR is an actor speaker, else the speaker is a talking activator) |
| +0x70 | the last response's info |
| +0xb0 | the speaker already faced the player |
| +0xb2 | the last said info was a "say once" (`info flags & 1`) |
| +0xb3 | the list is empty / the conversation must close |
| +0xb5, +0xb6 | one-shot flags: a line ended, the speaker is not talking |
| +0xb7 | skip the first topic (a greeting is at the head) |
| +0xb8 | a response is playing |
| +0xb9 | the voice is ready |
| +0xba | the menu is open and may skip |
| +0xc0, +0xc8, +0xd0 | the infos said this conversation: `BSTArray<TESTopicInfo*>` (data, capacity, count) |

A topic entry (`node[0]`): `+0x00` the topic's text, `+0x08` its length (0xffff: null terminated),
`+0x28` the quest, `+0x30` the info, `+0x49` a bool shown to the movie, `+0x4a` hidden, `+0x50` the
`TESTopic`. The topic's `+0x32` is its subtype (0x14209ce58's table, stride 10, tells which subtypes
are skipped when walking to the first topic: value 1 = skip).

### The functions

| address | what |
|---|---|
| 0x1405ee620(manager, skipAuto) | first topic: `+0x18 = +0x20` (its next when `+0xb7`); with skipAuto, skips the topics whose subtype's table entry is 1; true if a topic remains |
| 0x1405ee6a0(manager) | next topic (advances `+0x18`), true while one remains |
| 0x1405ee800(manager) | the current topic entry (`*+0x18`) |
| 0x1405ee6d0(manager, index) | select the topic at `index` (counting from the first, past the greeting when `+0xb7`): sets `+0x18`, and for an actor speaker runs the topic's `TESTopic` through 0x1403ef230(topic, speaker, player) with 0x140300c60 / 0x140300c30 around it (the topic's info chosen for this speaker, conditions evaluated); true when the entry holds a topic |
| 0x1405efb90(manager, fromMenu, ...) | say the selected topic: resolves the speaker; if the current item's info has flag `+0x20 & 4` on the topic's `+0x38` (the "random" / "no cross" flag family), tells the speaker (slot 0x270) to face the player, else only when 0x1405ee620-style `+0xb0` is clear; takes the entry's info (`+0x30`), marks it said (`+0x3c |= 0x8000` when the info's `+0x30 & 1`), runs 0x1403f2bb0 (the info's result scripts, with the speaker's handle), records `+0xb2 = info flags & 1` (say once); 0x1405f0fa0; appends the info to the said array; then, unless `fromMenu`, starts the response: `DAT_143211afa = 1`, and if the speaker is an actor that cannot speak (0x1406754b0) or a talking activator without a voice (0x140cc9730 / 0x140cc96e0) the speaker's slot 0x278 ends it, else 0x1405efe90 |
| 0x1405efe90(manager) | the response loop: under the lock, when a new item is pending (`DAT_143211afa`), drops the topic node already used (0x1405f2390 / 0x1405f2420) and builds the `DialogueItem` for the current topic (0x1405ed830); with no item, the end (0x1405f0820); with an item not yet playing: if the item has a response (`+0x40`), the speaker's slot 0x260 (play the response's voice/line) and `+0x70 = info`; else if the info is not "say once" and the topic is not hidden, finish; else re-selects the first topic, picks its info for the speaker (0x1403ef230) and says it (0x1405efb90) again; the end path runs 0x1405f04b0, 0x14098e4e0(a response exists) and 0x14098e5a0 (the menu's text hide and list show); afterwards `+0xb8 = 0`, `+0xb5 = +0xb6 = 0`, `+0xba = 1` |
| 0x1405f0820(manager) | skip / end of a line: only when `+0xba`; if the current item's response has no voice pending (`+0x30`'s `+0x3c & 0x40` clear) and no next response (`+0x40`): when nothing plays, starts the first response (0x1405efdf0(manager, 0)) or, after a "say once", marks the list to close (`+0xb3`); when a response plays and the voice is not ready yet, marks it ready and runs the end path; else (a voice playing) the speaker's slot 0x278 stops it |
| 0x1405f0ec0(manager) | the index of the topic whose `TESTopic` matches the last said info's topic (walks the said array from the end), for the list's selected row |
| 0x1405f2520 / 0x1405ee850 | the manager's two virtual functions (vtable 0x1418fea40) |

The dialogue menu's `TopicClicked` (0x14092ab70) only acts while a response is not playing
(`menu+0x30 == 1`) and the argument is a number: 0x1405ee6d0(index) then 0x1405efb90(manager, 0, 0).
`SkipText` (0x14092ab30) is 0x1405f0820 under the lock.

### What this settles for the port

- The topic list the movie shows is the manager's list minus the hidden entries, each with its
  text, the `+0x49` bool and its index; the selected row is the topic of the last said info.
- A "say once" info closes the list after its line; the said infos are kept per conversation in
  the array at `+0xc0`.
- The speaker turns to face the player only for infos whose topic carries the `+0x38 +0x20 & 4`
  flag or when it has not faced the player yet in this conversation (`+0xb0`).
- The greeting is the list's head and is skipped (`+0xb7`) when the topics are shown.

Not read: 0x1403ef230 (how an info is chosen among a topic's, with the conditions and the
"random" and "say once" flags; the port's `choose.zap` does this from the records), 0x1405ed830
(the `DialogueItem`'s responses from the info's `TESTopicInfo::ResponseData`), the voice file
naming (the port's `voice.zap` has it), and the speaker's slots 0x260 / 0x270 / 0x278 (the actor's
speak, face-player and stop-speaking virtuals).

## Havok: the collision filter the executable builds

Read from `SkyrimSE.exe` 1.7.104 with REA. The world's solver settings and the deactivation
classes are already in `game/havokworld.zap` (hkpWorld's constructor); here the `bhkCollisionFilter`
(vtable 0x141a825f0), built by 0x14107c3e0 and filled by 0x14107cbd0 (724 lines of bit sets,
parsed by script from the pseudocode).

### The layout (`bhkCollisionFilter`, singleton `DAT_1421a3e00`)

| offset | what |
|---|---|
| +0x4c | the next collision group (starts at 10) |
| +0x50 | `bipedBitfields[32]`, one uint32 per biped part, bit j = the part collides with part j |
| +0xd0 | 64 uint32, nearly empty: [9] = 4, [11] = 2, [13] = 3 (not identified) |
| +0x1d0 | `layerBitfields[64]`, one uint64 per layer, bit j = the layer collides with layer j; all set first, then cleared pair by pair |
| +0x3d0.. | the layer names (47 BSFixedStrings from the table at 0x1420d1f80) and the biped part names (29, from 0x1420d2100) |

### The layers (COL_LAYER), in the table's order

0 UNIDENTIFIED, 1 STATIC, 2 ANIMSTATIC, 3 TRANSPARENT, 4 CLUTTER, 5 WEAPON, 6 PROJECTILE, 7 SPELL,
8 BIPED, 9 TREES, 10 PROPS, 11 WATER, 12 TRIGGER, 13 TERRAIN, 14 TRAP, 15 NONCOLLIDABLE,
16 CLOUDTRAP, 17 GROUND, 18 PORTAL, 19 DEBRIS SMALL, 20 DEBRIS LARGE, 21 ACOUSTIC SPACE,
22 ACTORZONE, 23 PROJECTILEZONE, 24 GASTRAP, 25 SHELLCASING, 26 TRANSPARENT SMALL,
27 INVISIBLE WALL, 28 TRANSPARENT SMALL ANIM, 29 WARD, 30 CHARCONTROLLER, 31 STAIRHELPER,
32 DEADBIP, 33 BIPED NO CC, 34 AVOIDBOX, 35 COLLISIONBOX, 36 CAMERASPHERE, 37 DOORDETECTION,
38 CONEPROJECTILE, 39 CAMERAPICK, 40 ITEMPICK, 41 LINEOFSIGHT, 42 PATHPICK, 43 CUSTOMPICK1,
44 CUSTOMPICK2, 45 SPELLEXPLOSION, 46 DROPPINGPICK.

A body's layer is the low 7 bits of its `bhkRigidBody` collision filter info (the NIF's
`bhkCollisionObject` layer), the collision group the high 16 bits (`+0x4c` hands them out).

### The layer matrix: who does not collide with whom

Every pair collides unless listed (the matrix is symmetric; each line names the layers the layer
does not touch).

| layer | does not collide with |
|---|---|
| UNIDENTIFIED | CHARCONTROLLER |
| STATIC, ANIMSTATIC, CLUTTER, TREES, PROPS, TERRAIN, TRAP, GROUND, CUSTOMPICK1, CUSTOMPICK2, SPELLEXPLOSION | PORTAL, ACOUSTIC SPACE |
| TRANSPARENT, SPELL, TRIGGER, TRANSPARENT SMALL, TRANSPARENT SMALL ANIM, AVOIDBOX, CAMERAPICK, PATHPICK | PORTAL, DEBRIS SMALL, ACOUSTIC SPACE |
| WEAPON | BIPED, PORTAL, ACOUSTIC SPACE |
| PROJECTILE | BIPED, PORTAL, DEBRIS SMALL, ACOUSTIC SPACE |
| BIPED | WEAPON, PROJECTILE, PORTAL, DEBRIS SMALL, DEBRIS LARGE, ACOUSTIC SPACE, CHARCONTROLLER, DEADBIP |
| WATER, NONCOLLIDABLE, CLOUDTRAP | PORTAL, DEBRIS SMALL, DEBRIS LARGE, ACOUSTIC SPACE |
| PORTAL | every layer but ACTORZONE, PROJECTILEZONE, GASTRAP, SHELLCASING, INVISIBLE WALL, WARD, STAIRHELPER, BIPED NO CC, COLLISIONBOX, CAMERASPHERE, DOORDETECTION, CONEPROJECTILE, ITEMPICK, DROPPINGPICK and UNIDENTIFIED (two more bits, 16 CLOUDTRAP and 18 PORTAL itself, are cleared through a temporary the parser did not follow) |
| DEBRIS SMALL | TRANSPARENT, PROJECTILE, SPELL, BIPED, WATER, TRIGGER, NONCOLLIDABLE, CLOUDTRAP, PORTAL, TRANSPARENT SMALL, TRANSPARENT SMALL ANIM, CHARCONTROLLER, AVOIDBOX, CAMERASPHERE, CAMERAPICK, ITEMPICK, LINEOFSIGHT, PATHPICK, DROPPINGPICK |
| DEBRIS LARGE | BIPED, WATER, NONCOLLIDABLE, CLOUDTRAP, PORTAL, LINEOFSIGHT |
| ACOUSTIC SPACE | as PORTAL's list without DEBRIS SMALL, DEBRIS LARGE and CHARCONTROLLER (bits 16 and 21 cleared through a temporary) |
| CHARCONTROLLER | UNIDENTIFIED, BIPED, PORTAL, DEBRIS SMALL, DEADBIP |
| DEADBIP | BIPED, PORTAL, ACOUSTIC SPACE, CHARCONTROLLER |
| CAMERASPHERE, ITEMPICK, DROPPINGPICK | DEBRIS SMALL |
| LINEOFSIGHT | PORTAL, DEBRIS SMALL, DEBRIS LARGE, ACOUSTIC SPACE |
| ACTORZONE, PROJECTILEZONE, GASTRAP, SHELLCASING, INVISIBLE WALL, WARD, STAIRHELPER, BIPED NO CC, COLLISIONBOX, DOORDETECTION, CONEPROJECTILE | collide with everything (their bits are never cleared; the zones are phantoms) |

For the inn: the clutter (CLUTTER, PROPS), the statics and the character controller all collide
with each other; the player's capsule (CHARCONTROLLER) ignores the BIPED ragdoll bodies and the
dead (DEADBIP), which is why a ragdoll never pushes the walker; WEAPON and PROJECTILE pass through
BIPED (hits are detected by the game's own sweeps, not by Havok contacts).

### The biped parts (the ragdoll's self-collision)

The parts in the table's order: 0 OTHER, 1 HEAD, 2 BODY, 3 SPINE1, 4 SPINE2, 5 LUPPERARM,
6 LFOREARM, 7 LHAND, 8 LTHIGH, 9 LCALF, 10 LFOOT, 11 RUPPERARM, 12 RFOREARM, 13 RHAND,
14 RTHIGH, 15 RCALF, 16 RFOOT, 17 TAIL, 18 SHIELD, 19 QUIVER, 20 WEAPON, 21 PONYTAIL, 22 WING,
23 PACK, 24 CHAIN, 25 ADDONHEAD, 26 ADDONCHEST, 27 ADDONARM, 28 ADDONLEG. Here the bits are set
(only these pairs collide; the default is no self-collision):

| part | collides with |
|---|---|
| HEAD | LFOREARM, LHAND, RFOREARM, RHAND, TAIL, WING |
| BODY, SPINE1 | LFOREARM, LHAND, RFOREARM, RHAND, WING, CHAIN |
| SPINE2 | LFOREARM, LHAND, RFOREARM, RHAND, TAIL, WING, CHAIN |
| LUPPERARM | RFOREARM, RHAND, WING (RUPPERARM: LFOREARM, LHAND, WING) |
| LFOREARM | HEAD, BODY, SPINE1, SPINE2, LTHIGH, RUPPERARM, RFOREARM, RHAND, RTHIGH, TAIL, WING (RFOREARM mirrored) |
| LHAND | HEAD, BODY, SPINE1, SPINE2, LTHIGH, LCALF, LFOOT, RUPPERARM, RFOREARM, RHAND, RTHIGH, RCALF, RFOOT, WING (RHAND mirrored, plus SHIELD) |
| LTHIGH | LFOREARM, LHAND, RFOREARM, RHAND, RTHIGH, RCALF, RFOOT, SHIELD, WING, CHAIN (RTHIGH mirrored) |
| LCALF | LHAND, RHAND, RTHIGH, RCALF, RFOOT, SHIELD, WING, CHAIN (RCALF mirrored) |
| LFOOT | LHAND, RHAND, RTHIGH, RCALF, SHIELD, WING, CHAIN (RFOOT mirrored) |
| TAIL | HEAD, SPINE2, LFOREARM, RFOREARM, WING |
| SHIELD | LTHIGH, LCALF, LFOOT, RHAND, RTHIGH, RCALF, RFOOT, WING |
| WEAPON, PONYTAIL | WING |
| WING | every part but OTHER, QUIVER, PACK, CHAIN and the addons |
| CHAIN | BODY, SPINE1, SPINE2, LTHIGH, LCALF, LFOOT, RTHIGH, RCALF, RFOOT |

So a ragdoll's hands and forearms collide with the torso and the opposite leg; the two thighs
collide with each other but a thigh never with its own calf; the head only with the hands,
forearms and tail. `skyrim/hkx/ragdoll.zap` should filter its 18 bodies' pairs by this table
(the bodies' biped part is the NIF's / HKX's collision filter info bits 8..15).

### Not read

The constraint solver is read: `havok-solver.md` has the solver's tau and damping, the loop, the
rows of the ball and socket, the stiff spring, the limited hinge and the ragdoll (cone, twist and
plane limits, angular friction), their constants and the executable's addresses. Not read there:
the motors, the constraint chains, the contact schemas and the order a world's constraints are
turned into rows. `engine/physics` (`rows.zap`, `constraints.zap`) builds and solves those rows;
the cone limit's axis sign was misread in `havok-solver.md` (fixed there: mode 0 takes the cross
negated).

## Havok: the constraint solver (hk_2010.2.0-r1, SkyrimSE.exe 1.7.104)

How the jacobians of the ragdolls' and the hanging objects' joints are built and solved. Read in
two layers: the Havok 6.6.0 PC SDK's debug libraries (`hkpConstraintSolver.lib`, `hkpDynamics.lib`,
decompiled with Ghidra; the debug build keeps the function names and the structure), and the same
functions found in the executable by their constants, call shapes and offsets. What is stated
below holds for the executable; 6.6 is named only where 2010.2 differs. Everything is in the
solver's own units (Havok metres, seconds, radians); Skyrim's scale is the caller's.

### Where the code is (1.7.104, base 0x140000000)

| what | address | 6.6 name |
|---|---|---|
| the world's constructor, `setTauAndDamping` inlined in it | 0x140b531c0 | `hkpWorld::hkpWorld(cinfo)`, `hkpSolverInfo::setTauAndDamping` |
| the solver loop (gravity, steps, integration) | 0x140c12e20 | `hkSolveConstraints` |
| the same split per step (the multithreaded jobs) | 0x140c172f0 | `hkSolveConstraintsByTheSteps` |
| one pass over the schemas | 0x140c1ab60 | `hkSolveStepJacobians` (6.6's `hkSolver::solve1d*` are reference copies of its cases) |
| atoms to schemas, a switch on the atom type (jump table 0x140c22828) | 0x140c1f070 | `hkSolverBuildJacobianFromAtomsNotContact` |
| the ball and socket atom | 0x140c22d10 | `buildJacobianFromBallSocketAtom` |
| a 1d linear row with a given rhs (the stiff spring) | 0x140c235f0 | `hk1dLinearBilateralConstraintBuildJacobianWithCustomRhs` |
| a 1d angular bilateral row (the 2d ang atom) | 0x140c23a40 | `hk1dAngularBilateralConstraintBuildJacobian` |
| the angular friction rows | 0x140c23d10 | `hk1dAngularFrictionBuildJacobian` |
| the contact jacobians (not read here) | 0x140c243c0 | |
| the angle approximation | 0x140aabb90 | `hkMath::atan2fApproximation` |
| the hkUFloat8 table, 256 floats | 0x1419ba8c0 | `hkUFloat8_intToReal` |
| schema type to solver-temp count (bytes) | 0x1420c8aa8 | `hkpJacobianSchema::getNumSolverElemTemps` |

The atom types in 2010.2 (the jump table's order): 0 invalid, 1 bridge (calls a function pointer),
2 set local transforms, 3 set local translations, 4 set local rotations, 5 ball socket, 6 stiff
spring, 7 lin, 8 lin soft, 9 lin limit, 10 lin friction, 11 lin motor, 12 2d ang, 13 ang, 14 ang
limit, 15 twist limit, 16 cone limit, 17 ang friction, 18 ang motor, 19 ragdoll motor, 20 pulley,
21 overwrite pivot, 22 contact, **23 setup stabilization (new in 2010)**, 24 and up other new atoms
and the modifiers. The first 22 are 6.6's.

### The solver's numbers

`hkpWorldCinfo` carries tau (+0x88), damping (+0x8c), iterations (+0x90), micro steps (+0x94) and
the max constraint violation (+0x98). The defaults, which Skyrim adopts, are tau 0.6, damping 1.0,
4 iterations, 1 micro step. The `setupSolverInfo` presets are 2, 4 or 8 iterations with (tau,
damping) = (0.3, 0.9) soft, (0.6, 1.0) medium, (0.9, 1.1) hard.

`setTauAndDamping(tau, damping)` stores, in `hkpSolverInfo` (inside the world at +0x2c0):

- `m_tau = tau`, `m_damping = damping`, `m_frictionTau = 0.5 tau`;
- `m_dampDivTau = damping / tau` (D below), `m_tauDivDamp = tau / damping` (f below),
  `m_dampDivFrictionTau = damping / frictionTau`, `m_frictionTauDivDamp = frictionTau / damping`;
- `m_integrateVelocityFactor` = f in all four lanes, `m_invIntegrateVelocityFactor` = D in all four.

With the defaults: frictionTau 0.3, D = 1.6667, f = 0.6.

Per step the world sets (hkpSimulation, before the solve): `m_deltaTime = frameDt / numSteps`,
`m_invDeltaTime = numSteps / frameDt`, `m_invNumSteps`, `m_invNumMicroSteps`,
`globalAccelerationPerSubStep = gravity * m_deltaTime`, `...PerStep = gravity * frameDt`. At 60 Hz
and 4 steps the sub-step is 1/240 s.

The query every builder gets (`hkpConstraintQueryIn::set`; 2010 offsets): +0x00 sub-step dt, +0x04
micro-step dt (sub-step dt over micro steps), +0x08 sub-step 1/dt, +0x0c frame dt, +0x10 frame
1/dt, +0x14 1/numSteps, +0x18 1/(numSteps micro steps), **+0x20 rhsFactor = f * subStepInvDt**,
**+0x24 virtMassFactor = damping**, +0x28 frictionRhsFactor = frictionTauDivDamp * subStepInvDt,
+0x30 accumulator A, +0x38 accumulator B, +0x40 and +0x48 the two world transforms, +0x50 tau,
+0x54 damping, +0x60 maxConstraintViolationSqrd, +0x70 constraint instance, +0x78 runtime (the
atoms' `hkpSolverResults` array, 8 bytes a result: impulse, internal data), +0x80 the
violated-constraints buffer. At the defaults and 1/60 s, rhsFactor = 0.6 * 240 = 144 and
virtMassFactor = 1.

FLT_EPSILON, 1.1920929e-7 (0x34000000), is added to every effective mass before the division, and
is the threshold for "a vector has a length".

### The accumulators

The solver works on `hkpVelocityAccumulator`, 0x80 bytes a body (2010 layout): +0x00 type (0 rigid
body, 1 keyframed, 2 rigid body without gravity), +0x01 context, +0x04 deactivation class, +0x08
gravity factor, +0x10 linear velocity v, +0x20 angular velocity w in the body's **core frame** (its
principal axes), +0x30 inverse inertia diagonal (xyz) and inverse mass (w).

- While the jacobians are built: the centre of mass in the world is at **+0x70**, and coreFromWorld
  is a 3x3 whose columns are stored at +0x40, +0x50, +0x60 (core = M world; a lane of the result
  is the dot of the input with the matching lanes of the three columns). 6.6 kept the centre at
  +0x40 and the columns at +0x50..+0x70.
- While the solver runs: +0x40 holds the linear sum S_lin and +0x50 the angular sum S_ang (zeroed
  at the start). The stabilized ball socket also reads +0x60 as the body's orientation quaternion
  (core to world) and +0x70 as its position.

Every angular jacobian in a schema is in the core frame of its body: the builder rotates a world
axis by coreFromWorld, the solver applies `w += invInertia (lane by lane) * jacobian * impulse`.

### The loop (`hkSolveConstraints`)

1. For every accumulator: S_lin = S_ang = 0. A rigid body (type 0) gets
   `v += gravityFactor * globalAccelerationPerSubStep` once.
2. For step = 0 .. numSteps-1:
   1. `numMicroSteps` passes of `hkSolveStepJacobians` over all schemas, in the order they were
      emitted (Gauss-Seidel: each row sees the effect of the rows before it, in the same pass).
      Inside a constraint the order is the atoms' order; the order of the constraints is the
      solver setup's (not read).
   2. For every accumulator, the integration below.

The integration, per accumulator (u = the real velocity, defined as v - S):

- A velocity with a NaN lane or a lane of 1e7 or more is replaced by zero (v and w both).
- Types 0 and 2 only, with the body's deactivation class row of `hkpSolverInfo::m_deactivationInfo`
  (the table in `game/havokworld.zap`): per lane m = |v| * linearThresholdInv + |w| *
  angularThresholdInv. If all three lanes are below 1: if all are below
  `relativeSleepVelocityThreshold`, v and w become zero, else both are multiplied by
  `slowObjectVelocityMultiplier`.
- d_lin = v - S_lin and d_ang = w - S_ang; then S_lin += f d_lin and S_ang += f d_ang.
- Not the last step: v = S_lin + d_lin + gravityFactor * gravityPerSubStep and w = S_ang + d_ang,
  with the sums as just updated. In u terms: u grows by the gravity only and S gathers f u. (The
  gravity is added numSteps times in all: once before the loop, once after each step but the last.)
- The last step: v = d_lin, w = d_ang (the body keeps u), and the sums are scaled,
  S *= (1 / numSteps) * D. Since f D = 1, S is then the mean of u over the steps.

`hkRigidMotionUtilApplyAccumulators` stores v and the world form of w as the body's velocities and
steps its position with the sum S (clamped to the motion's speed caps), not with v. So a
constraint's position correction moves the body through u and S, while the velocity the body keeps
for the next frame is u alone.

### The schemas and how each is solved

A 1d row (types 5 and 6, 48 bytes, 12 floats): lin axis [0..2], rhs [3], angA [4..6] (A's core
frame), invJacDiag [7], angB [8..10] (B's core frame), maxImpulse [11] (type 6 only). The type byte
is stamped over the low byte of float [0]. Each row also owns one `hkpSolverElemTemp` (the impulse
accumulated this frame, `a`). vA, wA, vB, wB are the accumulators' v and w.

**Bilateral (5), and with an impulse limit (6)**:

    delta = invJacDiag * (rhs - (lin . (vA - vB) + angA . wA + angB . wB))
    type 6 only: delta = clamp(delta, -M - a, M - a)
    vA += invMassA * delta * lin;      vB -= invMassB * delta * lin
    wA += invInertiaA * angA * delta;  wB += invInertiaB * angB * delta
    a += delta

`invJacDiag` is built as `virtMassFactor / (invMassA + invMassB + sum_l invInertiaA_l angA_l^2 +
sum_l invInertiaB_l angB_l^2 + epsilon)`: with damping 1 the exact inverse effective mass, with
damping below 1 a softer row.

**Angular row (0xc, 32 bytes)**: angA [0..2], invDiag [3], angB [4..6], rhs [7]:
`delta = invDiag * (rhs - (angA . wA + angB . wB))`, applied to the angular velocities only; no
clamp.

**Angular limits (0xd, 48 bytes)**: angA [0..2], invDiag [3], angB [4..6], rhs [7], lower [8],
upper [9], tauFactor [10]. SA and SB are the angular sums, D and damping from the solver info:

    p    = tauFactor * rhs
           - (tauFactor * D * (angA . SA + angB . SB)
              + damping * (angA . (wA - SA) + angB . (wB - SB)))
    dMin = (p - lower) * invDiag
    dMax = (p - upper) * invDiag                       (a = the row's accumulated impulse)
    if dMin > -a:      apply dMin     (the lower limit side; a stays positive)
    elif dMax < -a:    apply dMax     (the upper limit side; a stays negative)
    else:              nothing

The delta is applied to w as `invInertia * ang * delta`, and `a += delta`. There is no clamp: the
test alone keeps the accumulated impulse of one sign. This is the one family that uses the sums
and the damping apart: what the earlier steps already moved (D S) is weighed by tauFactor, the
velocity part by damping.

**Angular friction (0xe, 48 bytes)**: angA, invDiag, angB, rhs [7], maxImpulse [8]:
`delta = invDiag * (rhs - (angA . wA + angB . wB))`; if |delta| > maxImpulse, delta is scaled to
magnitude maxImpulse and the scale (the used factor) goes into the row's second temp. So the clamp
is on each iteration's delta, not on the accumulated torque.

**Stabilized ball socket (0x10, 64 bytes; 2010 only)**: see the atom below.

A skipped atom (disabled, or a cone limit whose axes are parallel) emits a 16-byte schema of type
3 that only advances the solver-results pointer. The temps a schema takes (table at 0x1420c8aa8):
1 for types 5, 6, 0xc, 0xd; 2 for 0xe; 3 for 0x10.

### The atoms

#### The frames (types 2 and 3)

The set-local-transforms atom (ragdoll, limited hinge, hinge) holds one hkTransform a body, the
pivot in the translation. The builders use, for each body, its world transform composed with that
local transform: the constraint frame's world axes and the world pivot. The set-local-translations
atom (ball and socket, stiff spring) sets only the pivots. Below, A.col[i] is the i-th axis of A's
constraint frame in the world, pA and pB the world pivots, rA = pA - comA, rB = pB - comB.

#### Ball and socket, method OLD (`m_solvingMethod` = 1)

Three type 5 rows (type 6 when `m_maxImpulse` is not HK_REAL_MAX, 3.4028e38), one for each world
axis e_k:

- lin = e_k; angA = M_A (rA x e_k); angB = M_B (e_k x rB), M the coreFromWorld;
- invJacDiag as above;
- `rhs_k = rhsFactor * (pB - pA)_k - table[m_velocityStabilizationFactor] * (vRotB - vRotA)_k`,
  where vRotX = (the world angular velocity of X) x rX is the pivot's velocity due to the rotation
  alone, and `table` is the hkUFloat8 table at 0x1419ba8c0 (0, 0.01, 0.02 .. 0.07, then 0.075,
  0.08, 0.085, 0.091 ..; entry 47 is 0.998, 48 is 1.067, 255 is 1000002; three decimals, read the
  256 floats from the executable). 6.6 builds the same rows with its `m_stabilizationFactor`.

Skyrim's skeleton.hkx ragdolls hold exactly this: all 34 ball sockets of the human skeleton and
of the draugr's have `m_solvingMethod` 1, the stabilization byte 48 (factor 1.067), `m_maxImpulse`
HK_REAL_MAX and inertia stabilization 0. So a ragdoll pivot is three bilateral rows with
rhs = 144 * error and the full inverse effective mass at the defaults. (Whether the engine rewrites
the method at run time was not checked.)

If the query's `maxConstraintViolationSqrd` (cinfo 0.05, squared) is under the pivots' squared
distance, the builder appends the constraint instance to the violated buffer (up to 0x80) for the
game's callbacks; the rows are unchanged.

#### Ball and socket, method STABILIZED (any other value; 2010 only)

One 64-byte schema of type 0x10 for the three degrees of freedom. The builder stores:
[0..3] maxImpulse squared (maxImpulse itself when it is 1.7e38 or more; only for the breach check,
the solver does not read it), [4..6] the unit vector of rA in A's core frame and [7] its length,
[8..10] and [11] the same for rB, [12] tau * subStepInvDt, [13] the stabilization cap (the setup
stabilization atom's, HK_REAL_MAX when there is none or it is disabled), [14] and [15]
`min(1, invMass_X / (maxInvInertia_X * |r_X| * m_inertiaStabilizationFactor))` for A and B (1 when
the product is under epsilon), maxInvInertia being the largest of the body's three inverse inertia
lanes.

A pass over it:

1. Predict each body at the end of the sub-step from its sums: p' = p + (v + (D-1) S_lin) dt;
   q' = normalize(q advanced by the half vector 0.5 (w + (D-1) S_ang) dt), dt the sub-step.
2. The lever arms then: r'_X = |r_X| * rotate(q'_X, unit_X) (the quaternion rotation 2(w (u x v) +
   u (u . v) + v (w^2 - 1/2))).
3. e = (tau / dt) * ((p'B + r'B) - (p'A + r'A)).
4. K = (invMassA + invMassB) I + sum over A and B of |r_X| f_X J_X^T diag(invInertia_X) J_X, with
   the row k of J_X the unit direction of r'_X crossed with e_k, in the core frame; f_X is [14] or
   [15]. K is inverted with the adjugate and the determinant (reciprocal estimate and one Newton
   step).
5. imp = K^-1 e, scaled to length [13] when longer.
6. Apply: vA += invMassA imp, vB -= invMassB imp; wA += f_A invInertiaA (J_A^T imp),
   wB -= f_B invInertiaB (J_B^T imp). The three temps take the impulse's components.

There is no `rhs - J v` here: the velocities are already in the prediction. The skeletons'
ragdolls do not use it (above); constraints built at run time may (the NIF constraints' path was
not read).

#### Setup stabilization (type 23; 2010 only)

`m_enabled` (+2), `m_maxAngle` (+4). Enabled, the stabilized ball socket's cap [13] is
`m_maxAngle * subStepInvDt / max(maxInvInertiaA * |rA|, maxInvInertiaB * |rB|, epsilon)`. The
skeletons hold it disabled with `m_maxAngle` 1.8e19.

#### Stiff spring (type 6)

dir = (pA - pB) / |pA - pB|; with a length not above epsilon, dir = (1,0,0) and the length is 0.
One type 5 row: lin = dir. Both bodies' lever arms are taken from the same point, pA (the row
builder is given one point): angA = M_A ((pA - comA) x dir), angB = M_B (dir x (pA - comB)).
`rhs = rhsFactor * (m_length - |pA - pB|)`, invDiag as in the bilateral rows. A pushes along dir
(away from B) when the pivots are closer than the rest length.

#### The 2d ang atom (type 12; the limited hinge's and the hinge's axle)

`m_freeRotationAxis` f; i1 = (f+1)%3, i2 = (f+2)%3 (the byte table at 0x141a10170). Two angular
rows (type 0xc) keeping A's axis f aligned with B's:

- row 1: axis = B.col[i2], rhs = -rhsFactor * (A.col[f] . B.col[i1]);
- row 2: axis = -B.col[i1], rhs = -rhsFactor * (A.col[f] . B.col[i2]);

with angA = M_A axis, angB = -M_B axis, invDiag = virtMassFactor / (sum invInertia ang^2 over both
bodies + epsilon).

#### The ang limit atom (type 14; the limited hinge's limit)

Disabled: a skip schema. Else one 0xd row: axis = A.col[limitAxis]; with i1 = (limitAxis+1)%3,
i2 = (limitAxis+2)%3, angle = atan2(A.col[i1] . B.col[i2], A.col[i1] . B.col[i1]) (the
approximation in "2010 against 6.6"), then shifted by multiples of 2 pi to within pi of the
previous angle, which is minus the atom's result `internalSolverData`. The row: angA = M_A axis,
angB = -M_B axis, `tauFactor = tau * m_angularLimitsTauFactor`, `invDiag = tauFactor / (sum
invInertia ang^2 + epsilon)`, `rhs = -subStepInvDt * angle`, `lower = -subStepInvDt * minAngle *
tauFactor`, `upper = -subStepInvDt * maxAngle * tauFactor`. Skyrim's hinges: limitAxis 0, tau
factor 1.0, the limits as the file has them (e.g. -1.92 .. 0, -0.596 .. 0.0628).

#### The twist limit (type 15)

With the twist axis t: s = A.col[t] + B.col[t], h = s / |s| (B.col[t] and c = 0 when |s| is
under 1e-16), c = 0.5 |s|. With the reference axis r, w = h x B.col[r]: angle = atan2(A.col[r] .
w, A.col[r] . (w x h)), not shifted. The row 0xd: axis h, `tauFactor = tau *
m_angularLimitsTauFactor * c^2` (the limit fades as the two twist axes part), the rest as the ang
limit. The human ragdoll's first joints: twist axis 0, ref axis 1, +-0.1745 rad, tau factor 0.8.

#### The cone limit (type 16; a ragdoll has two, the cone and the planes)

a = A.col[twistAxisInA], b = B.col[refAxisInB], x = a x b; with |x|^2 under epsilon, a skip
schema. Else raw = atan2(|x|, a . b), in [0, pi]. Mode 0 (ZERO_WHEN_VECTORS_ALIGNED): angle = raw,
axis = -x / |x|. Mode 1 (ZERO_WHEN_VECTORS_PERPENDICULAR): angle = pi/2 - raw, axis = x / |x|
(the case's sign factor is the float at 0x141a10184 - 4 mode: -1 for mode 0, +1 for mode 1; the angle's
factor and offset are 0x141a10180 + 4 mode and 0x141a10188 + 4 mode, (1, 0) and (-1, pi/2)). The
row 0xd with that axis, `tauFactor = tau * m_angularLimitsTauFactor`, lower and upper the atom's
min and max, rhs = -subStepInvDt * angle.

When `m_memOffsetToAngleOffset` is above 1 (the stabilized cone) the atom keeps a float o in the
constraint runtime at that offset, and the angle is changed before the row is built. With
prev = minus this atom's result `internalSolverData`, a = angle - o, s = max(0.5 frameDt, 0.05 o):

    o' = o - s;   angle' = a + s
    if prev != 0 and a - prev > s + 0.25 frameDt:   o' += a - prev;   angle' = prev + s
    o' = max(o', epsilon)         (stored back to the runtime)

and angle' replaces the angle. It is a ratchet: the offset decays by s every frame, and a jump of
the angle beyond the allowance is fed in slowly (capped at prev + s) while the excess is
remembered in o.

The human ragdoll's atoms: cone: twistAxisInA 0, refAxisInB 0, mode 0, max 0.785 rad (45 deg),
min -100 (never reached), tau factor 0.8, stabilized (offset 56); planes: twistAxisInA 0,
refAxisInB 1, mode 1, per joint (e.g. -0.88 .. 0.26), tau factor 0.8, not stabilized.

#### Angular friction (type 17; ragdoll and limited hinge)

Skipped (type 3, `m_numFrictionAxes` results) when disabled or `m_maxFrictionTorque` is 0. Else one
0xe row for each of `m_numFrictionAxes` axes from `m_firstFrictionAxis`, the axis being A.col[i]:
angA = M_A axis, angB = -M_B axis, `invDiag = 1 / (sum invInertia ang^2 + epsilon)` (no
virtMassFactor), `rhs = subStepInvDt * (the row's result internalSolverData from the last frame)`,
`maxImpulse = m_maxFrictionTorque * microStepDt`. Skyrim's ragdoll: 3 axes from 0; the limited
hinge: 1 axis (0); the torque is the joint's.

#### Not read

The ragdoll motor (19) and the angular motor (18) atoms and the position motor (Skyrim's dead
ragdolls have them switched off, see `projects/skyrim/README.md`, State). The lin family (7..11), the pulley (20), the chain
constraints (`bhkConstraintChain`: their own solvers, the ball and socket chain and the powered
chain, with their own tau, damping and cfm) and the contact schemas (0x140c243c0). The order in
which a world's constraints are turned into schemas. The runtime path that builds the NIF's
constraints (which solving method, which stabilization factor it sets).

### What the solve leaves for the next frame

Each row's `hkpSolverResults` gets `m_impulseApplied` = the accumulated `a`, and
`m_internalSolverData`, from the 6.6 export (the structure is the same in the executable, not
decoded there): bilateral rows `rhs * D * dt - numSteps dt (J . S)`; the limits
`rhs * dt - numSteps dt (J . S)`, so the next frame's previous angle (minus it) is about the angle;
friction `(rhs * dt - numSteps dt (J . S)) * the used factor`. A type 6 row whose |a| exceeds 0.99
of its maxImpulse is reported as breached.

### 2010.2 against 6.6

- Accumulator: +0x01 context; the build-time centre of mass moved from +0x40 to +0x70 and
  coreFromWorld from +0x50 to +0x40. The solve-time sums are at +0x40 and +0x50 in both.
- `hkpConstraintQueryIn` gains `m_maxConstraintViolationSqrd` and the violated buffer; rhsFactor at
  0x20 and virtMassFactor at 0x24 (6.6, 32-bit: 0x1c, 0x20); 64-bit pointers.
- `hkpSolverInfo` is the same up to +0x128, where `m_maxConstraintViolationSqrd` is added.
- `hkpBallSocketConstraintAtom` is 16 bytes: +2 solving method (0 stabilized, 1 old), +3 bodies to
  notify, +4 velocity stabilization (hkUFloat8), +8 max impulse, +12 inertia stabilization factor.
  The old method is 6.6's with the violation record added; the stabilized method (schema 0x10) and
  the setup stabilization atom (23) are new.
- The ball and socket, hinge, limited hinge and ragdoll data gain an `m_setupStabilization` atom
  (at atoms +48, +144, +144, +144).
- The atom numbering is 6.6's up to 22, the new atom is 23. The row types 5, 6, 0xc, 0xd, 0xe have
  6.6's layouts and formulas (compared case by case in `0x140c1ab60`); 0x10 is new.
- The angle approximation (0x140aabb90): z = min(|x|,|y|) / (max(|x|,|y|) + epsilon);
  p = z - 0.121079 z^2 - 0.0935228 z^3 (the constants 0.12107899785 and 0.09352281690); p = pi/2 - p
  when |y| > |x|; p = pi - p when x < 0; p = -p when y < 0. 6.6 calls a function outside the
  libraries read.

### The layout of Skyrim's ragdoll data (skeleton.hkx, for the port)

`hkpRagdollConstraintData::Atoms` (352 bytes, from +32 of the data): transforms 0, setup
stabilization 144 (type 23, enabled 0, maxAngle 1.8e19), ragdoll motors 160, angular friction 256
(12 bytes), twist 268 (20), cone 288 (20), planes 308 (20), ball socket 328 (16). The limited
hinge's (240 bytes): transforms 0, setup stabilization 144, ang motor 160, ang friction 184, ang
limit 196 (16), 2d ang 212 (4), ball socket 216. Each pass solves them in that order: friction,
then the limits, then the pivot rows.

## The menus: how the executable drives the Scaleform movies

Each menu is an `IMenu` (vtable layout in `classes-menus.md`): the game creates it by name, calls
`Accept` once with a `CallbackProcessor` that registers the GameDelegate callbacks the movie may
call (`FUN_140cfc860` builds the BSFixedString name, the processor's slot 1 binds name to handler),
and then feeds it `UIMessage`s through `ProcessMessage`. Everything below was read from the
pseudocode of those two functions of each menu (REA `procedure_pseudo_code`); the menu's vtable
slot 1 is `Accept`, slot 4 `ProcessMessage`.

### The shared pieces

| | address | what |
|---|---|---|
| `UI` singleton | `DAT_1421a05c0` | the menu map and message queue |
| `InterfaceStrings` singleton | `DAT_1421a05c8` | the menu names and the message-data type names as BSFixedStrings; the menus compare a message's menu name and data type against its fields (offsets below) |
| `UserEvents` singleton | `DAT_1432048d0` | the control names (table below), built by `FUN_140d04050` |
| `MenuTopicManager` singleton | `DAT_1431df408` | the dialogue state (see `dialogue.md`) |
| `Inventory3DManager` singleton | `DAT_1432309f8` | the rotating item model; `+0x150` is its zoom (0 at rest), `+0x154` 1.0 |
| `PlayerCharacter` singleton | `DAT_143230778` | |
| `MemoryManager` singleton | `DAT_143275ae0` | slot 0x60 frees |
| `FUN_14117a9d0(movie, name, FxResponseArgs)` | | `Invoke` on the menu's movie (`menu+0x10` is the `GFxMovieView`) with typed args; `FxResponseArgs<N>::vftable` holds N values |
| `FUN_140cf6160(value, ..., name, args, n)` | | `GFxValue::Invoke` on a value (the menu's root at `menu+0x30`) |
| `FUN_140cf8350(value, ..., member, GFxValue)` | | `GFxValue::SetMember` |
| `FUN_140cf5a40(value, ..., member, out)` | | `GFxValue::GetMember` |
| `FUN_1401b47f0(UI, &menuName, type[, data])` | | `UIMessageQueue::AddMessage`: 1 show, 3 hide, 0xb ... |
| `FUN_1409350a0(layer)` / `FUN_140936340(layer)` | | `ControlMap` push and pop of an input context by name: "DialogueMode", "TweenMode", "InventoryMode", "Favor", "Swimming", "HorseMode", "MovementDisabled" |
| `FUN_1409920a0("UIFavorite")` | | play a UI sound by editor id ("UIJournalOpen", "UIFavorite", the menu's own at `InterfaceStrings+0x1f8`/`+0x200`) |
| `FUN_140987240(id)` | | a HUD or tutorial notification by id (0xf8 at the barter menu's show, 0xfc at the journal's, 0x103 at a favorite toggled); not read further |
| `FUN_14098dd00(...)` / `FUN_14098da10` | | message box and HUD notification requests |
| `FUN_14116ede0` | | `IMenu::ProcessMessage` (the base: a menu returns it for messages it does not take) |
| `FUN_140905790(list, GFxValue)` | | push a value on an `FxResponseArgsList` |
| `FUN_1401d6e40(min, max)` | | a random float between two settings' values (used by the combat code too) |

`UIMessage` (`param_2`): `+0x00` the menu name, `+0x08` the type, `+0x10` the data (`IUIMessageData`,
whose `+0x18` is a BSFixedString name of the user event for type 7 and a payload at `+0x20`).
The types are CommonLibSSE's `UI_MESSAGE_TYPE`: 0 kUpdate, 1 kShow, 2 kReshow, 3 kHide, 4 kOpen,
5 kClose, 6 kScaleformEvent, 7 kUserEvent, 8 kInventoryUpdate (data `+0x10` is the actor's form id,
`+0x18` the item changed, 0 for all), 9 kUserProfileChange, 10 kMUStatusChange, 11 kResumeCaching,
12 kUpdateController (data `+0x10` the control's name, `+0x18` an out flag set by `FUN_14098e7b0`),
13 kChatterEvent.

A `ProcessMessage` returns 0 (kHandled), 1 (kIgnore), 2 (kPassOn). The item menus return 2 for
unknown types only while the 3D item is not zoomed.

A form's type is the byte at `form+0x1a`, CommonLibSSE's `FormType`; the values the menus test:
0x1a ARMO, 0x29 WEAP, 0x2e ALCH, 0x34 SLGM, 0x3e ACHR, 0x77 SHOU.

### UserEvents (`DAT_1432048d0`), the control names by offset

Built by `FUN_140d04050` (one BSFixedString per 8 bytes). The menus compare a user event's name
against these; a port keys its controls by the same names (controlmap.txt uses them).

| offset | name | offset | name | offset | name |
|---|---|---|---|---|---|
| 0x08 | Forward | 0x10 | (Back) | 0x18 | Strafe Left |
| 0x20 | Strafe Right | 0x28 | (Move) | 0x30 | (Look) |
| 0x38 | Activate | 0x40 | Left Attack/Block | 0x48 | Right Attack/Block |
| 0x50 | Dual Attack | 0x58 | ForceRelease | 0x60 | Pause |
| 0x68 | Ready Weapon | 0x70 | Toggle POV | 0x78 | (Jump) |
| 0x80 | Journal | 0x88 | Sprint | 0x90 | (Sneak) |
| 0x98 | Shout | 0xa0 | KinectShout | 0xa8 | (Grab) |
| 0xb0 | (Run) | 0xb8 | Toggle Always Run | 0xc0 | Auto-Move |
| 0xc8 | Quicksave | 0xd0 | Quickload | 0xd8 | NewSave |
| 0xe0 | Inventory | 0xe8 | Stats | 0xf0 | (Map) |
| 0xf8 | Screenshot | 0x100 | Multi-Screenshot | 0x108 | Console |
| 0x110 | CameraPath | 0x118 | Tween Menu | 0x120 | Take All |
| 0x128 | Accept | 0x130 | Cancel | 0x138 | (Up) |
| 0x140 | (Down) | 0x148 | (Left) | 0x150 | Right |
| 0x158 | PageUp | 0x160 | PageDown | 0x168 | (Pick) |
| 0x170 | PickNext | 0x178 | PickPrevious | 0x180 | Cursor |
| 0x188 | Kinect | 0x190 | SprintStart | 0x198 | SprintStop |
| 0x1a0 | sneakStart | 0x1a8 | sneakStop | 0x1b0 | blockStart |
| 0x1b8 | blockStop | 0x1c0 | blockBash | 0x1c8 | attackStart |
| 0x1d0 | attackPowerStart | 0x1d8 | reverseDirection | 0x1e0 | Unequip |
| 0x1e8 | Zoom In | 0x1f0 | Zoom Out | 0x1f8 | RotateItem |
| 0x200 | Left Stick | 0x208 | PrevPage | 0x210 | NextPage |
| 0x218 | PrevSubPage | 0x220 | NextSubPage | 0x228 | LeftEquip |
| 0x230 | RightEquip | 0x238 | ToggleFavorite | 0x240 | Favorites |
| 0x248 | Hotkey1 | 0x250 | Hotkey2 | 0x258 | Hotkey3 |
| 0x260 | Hotkey4 | 0x268 | Hotkey5 | 0x270 | Hotkey6 |
| 0x278 | Hotkey7 | 0x280 | Hotkey8 | 0x288 | Quick Inventory |
| 0x290 | Quick Magic | 0x298 | Quick Stats | 0x2a0 | Quick Map |
| 0x2a8 | ToggleCursor | 0x2b0 | (Wait) | 0x2b8 | Click |
| 0x2c0 | MapLookMode | 0x2c8 | Equip | 0x2d0 | DropItem |
| 0x2d8 | Rotate | 0x2e0 | NextFocus | 0x2e8 | PreviousFocus |
| 0x2f0 | SetActiveQuest | 0x2f8 | PlacePlayerMarker | 0x300 | XButton |
| 0x308 | YButton | 0x310 | ChargeItem | 0x318 | (null) |
| 0x320 | PlayerPosition | 0x328 | LocalMap | 0x330 | LocalMapMoveMode |
| 0x338 | Item Zoom | | | | |

The names in parentheses are strings Ghidra did not inline (`DAT_141b544a0` and the like); their
place in CommonLibSSE's `UserEvents` gives the name.

### InterfaceStrings (`DAT_1421a05c8`), the names by offset

Built by `FUN_141177a90` (one BSFixedString per 8 bytes). A menu compares a `UIMessage`'s menu
name (`+0x00`) and its data's type name against these fields.

| offset | name | offset | name | offset | name |
|---|---|---|---|---|---|
| 0x08 | FaderData | 0x10 | HUDData | 0x18 | HUDCamData |
| 0x20 | FloatingQuestMarkers | 0x28 | ConsoleData | 0x30 | QuantityData |
| 0x38 | MessageBoxData | 0x40 | BSUIScaleformData | 0x48 | BSUIMessageData |
| 0x50 | BSUIAnalogData | 0x58 | InventoryUpdateData | 0x60 | RefHandleUIData |
| 0x68 | TESFormUIData | 0x70 | LoadingMenuData | 0x78 | KinectStateChangeData |
| 0x80 | KinectUserEventData | 0x88 | InventoryMenu | 0x90 | Console |
| 0x98 | Dialogue Menu | 0xa0 | HUD Menu | 0xa8 | Main Menu |
| 0xb0 | MessageBoxMenu | 0xb8 | Cursor Menu | 0xc0 | Fader Menu |
| 0xc8 | MagicMenu | 0xd0 | Top Menu | 0xd8 | Overlay Menu |
| 0xe0 | Overlay Interaction Menu | 0xe8 | Loading Menu | 0xf0 | TweenMenu |
| 0xf8 | BarterMenu | 0x100 | GiftMenu | 0x108 | Debug Text Menu |
| 0x110 | MapMenu | 0x118 | Lockpicking Menu | 0x120 | Quantity Menu |
| 0x128 | StatsMenu | 0x130 | ContainerMenu | 0x138 | Sleep/Wait Menu |
| 0x140 | LevelUp Menu | 0x148 | Journal Menu | 0x150 | Book Menu |
| 0x158 | FavoritesMenu | 0x160 | RaceSex Menu | 0x168 | Crafting Menu |
| 0x170 | Training Menu | 0x178 | Mist Menu | 0x180 | Tutorial Menu |
| 0x188 | Credits Menu | 0x190 | Mod Manager Menu | 0x198 | Creation Club Menu |
| 0x1a0 | Login Menu | 0x1a8 | Marketplace Menu | 0x1b0 | TitleSequence Menu |
| 0x1b8 | Console Native UI Menu | 0x1c0 | Kinect Menu | 0x1c8 | LoadWaitSpinner |
| 0x1d0 | StreamingInstallMenu | 0x1d8 | TextWidget | 0x1e0 | ButtonBarWidget |
| 0x1e8 | GraphWidget | 0x1f0 | TextureWidget | 0x1f8 | UIMenuOK |
| 0x200 | UIMenuCancel | 0x208 | Show Text | 0x210 | Hide Text |
| 0x218 | Show List | 0x220 | Voice Ready | 0x228 | DMFOStr |
| 0x230 | Show Journal | 0x238 | Journal Setttings Saved | 0x240 | CloseMenu |
| 0x248 | Closing All Menus | 0x250 | RefreshMenu | 0x258 | CancelLoading |
| 0x260 | UserSettingsLoaded | 0x268 | ActivityStarted | 0x270 | Menu Texture Degrade Event |
| 0x278 | the quest marker img tag | | | | |

So the dialogue menu's kUpdate data types are "Show Text", "Hide Text", "Show List", "Voice Ready"
and "DMFOStr" (the dialogue-mode fade), the journal's "Show Journal", "Journal Setttings Saved"
and "RefreshMenu"; "CloseMenu" (0x240) is the user event every menu closes on; the message box's
sounds are UIMenuOK and UIMenuCancel. The .data copies of the menu names (0x1420ba790 BarterMenu
and the rest) are the static strings the menus' own classes register under.

### The menus

Per menu: the vtable, `Accept` and `ProcessMessage`, the callbacks the movie may call with the
handler each is bound to, and what `ProcessMessage` does per message type (the Invoke names are the
ActionScript functions of the menu's SWF the game calls).

#### DialogueMenu (vtable 0x141974998)

- Accept 0x14092a980: SkipText -> 0x14092ab30 (`MenuTopicManager::SkipText` 0x1405f0820 under the
  manager's lock), TopicClicked -> 0x14092ab70 (the argument is the topic's index: selects it with
  0x1405ee6d0 and says it with 0x1405efb90), FadeDone -> 0x14092ac00, CloseMenu -> 0x14092ac70,
  PlaySound -> 0x140991e00 (shared by every menu).
- ProcessMessage 0x14092a5a0: kUpdate with the data type at `InterfaceStrings+0x208`:
  Invoke "ShowDialogueText"(text); `+0x210`: "HideDialogueText"; `+0x218`: rebuild the topic list
  (0x14092b0d0, below); `+0x220`: "NotifyVoiceReady"; `+0x228`: the movie's slot 0x40 (set the
  menu's visibility by the payload), pushes "DialogueMode" when the payload is set, pops it when not.
  kShow with data: 0x14092b7f0 (Invoke "SetSpeakerName"(name) and a HUD request). kHide with a set
  payload: "StartHideMenu" and return 1 (keep the menu until FadeDone); kHide otherwise: pop
  "DialogueMode" and send two messages (0x14092bd10 with ids 0x89 and 0x8a) to the fader. Type 6
  returns 2 while the dialogue flag `DAT_1432563f9` is set.
- The topic list 0x14092b0d0: under the manager's lock, if the manager has topics (0x1405ee620),
  for each topic (0x1405ee800 current, 0x1405ee6a0 next) that is not hidden (`+0x4a`): the text
  (or "$Empty" when blank), a bool at `+0x49` and the index as a double are pushed onto one
  FxResponseArgsList; with fewer than 2 values the list is marked empty (`manager+0xb3`); else it
  compares the new names with the names shown last time (case insensitive) to tell the movie
  whether the list changed, keeps the names, and invokes "PopulateDialogueList"(list...,
  changed, param) and "ShowDialogueList"(changed, param, selected index or -1); the selected
  index comes from 0x1405f0ec0 (the last said info's topic).

#### InventoryMenu (vtable 0x141978208)

- Accept 0x140943850: PlaySound, UpdateItem3D -> 0x140943d00, RequestItemCardInfo -> 0x140943d80,
  CloseMenu -> 0x140943e70, ShowTweenMenu -> 0x140943ea0, CloseTweenMenu -> 0x140943ed0,
  ItemSelect -> 0x140943f20, ItemDrop -> 0x140943fb0, ShowSoulGemList -> 0x1409440d0,
  ItemCardListCallback -> 0x140944590, QuantitySliderOpen -> 0x140944910, SaveIndices ->
  0x1409449e0, StartMouseRotation -> 0x140905d10, StopMouseRotation -> 0x140905d20, ZoomItemModel
  -> 0x140944b60, CheckForMouseEquip -> 0x140944d50.
- ProcessMessage 0x140942b80: kUpdate (data type `+0x88`): "ItemRotating". kShow: starts the 3D
  item (0x14093d990 with mode 1), gets `_root.GetInventoryItemList` and makes the ItemList
  (`menu+0x48`, 0x58 bytes, its `entryList` member read by GetMember), the ItemCard (`menu+0x50`,
  0x140947110) and the bottom bar (`menu+0x58`, 0x140966cc0), then fills them: 0x140945050,
  0x1409452b0 (the item list), 0x1409451e0, 0x140945e20. kHide: tears them down. kUserEvent:
  "Item Zoom" or Accept while the 3D item is at rest -> "ToggleMenuFade"; LeftEquip ->
  "AttemptEquip"(1.0); RightEquip -> "AttemptEquip"(0.0); XButton -> "DropItem"; YButton ->
  toggles the favorite of the selected entry (0x140905370 selected entry, 0x140940f50 can be a
  favorite, else the message "You cannot favorite that item" with sound UIMenuCancel; 0x1402374c0 /
  0x140237a20 add and remove the favorite, "UIFavorite" sound, 0x140905930 refreshes the list);
  ChargeItem -> "AttemptChargeItem"; Quick Inventory (0x288) -> the movie's slot 0x168 (close).
  kInventoryUpdate for the player: with no item, refresh the list (0x1409452b0, 0x1409451e0) and
  update the player's 3D (0x140724680 / 0x1406f6720); with an item, record it in a sorted array
  at `menu+0x60` of items to refresh; an item of form type 0x1a (ARMO) marks `DAT_143257eec` when
  the player wears it (0x1401d2170). kUpdateController: the control's name mapped through
  0x140942450 (the hotkeys 1..8 give 1..8, else -1); Favorites (`+0x240`): close; the three column
  controls (`DAT_143257e70/78/80`) switch the sort column (`menu+0x7c` 1..6) and refresh.
- Shared by ContainerMenu, BarterMenu, GiftMenu, MagicMenu (same shape, own addresses below).

#### ContainerMenu (vtable 0x141971a90)

- Accept 0x140910e90: PlaySound, UpdateItem3D -> 0x1409112b0, RequestItemCardInfo -> 0x140911310,
  CloseMenu -> 0x140911680, ItemTransfer -> 0x1409116b0, EquipItem -> 0x140911810,
  QuantitySliderOpen -> 0x1409119d0, TakeAllItems -> 0x140911a70, ToggleFavorite -> 0x140911a90,
  DisabledItemSelect -> 0x140911aa0, StartMouseRotation, StopMouseRotation, ZoomItemModel ->
  0x140911ac0, CheckForMouseEquip -> 0x140911cb0.
- ProcessMessage 0x14090ff70: kShow as the inventory's, plus SetMember `bNPCMode` = (the container
  mode `DAT_1432560b8` is 2 or 3: a follower or a pickpocket) and, when `menu+0xb9`, Invoke
  "ShowItemsList"; the fillers are 0x1409126e0, 0x140912a80, 0x1409129b0. kHide in mode 2
  (follower, `DAT_143256180` the container's handle): every item still marked (`menu+0x78` array)
  is given back to the actor with 0x1405cab50 and the actor's inventory updated through its
  slot 0x2b0. kUserEvent: zoom/accept -> "ToggleMenuFade"; LeftEquip/RightEquip ->
  "AttemptEquip"(1.0/0.0); XButton -> "XButtonPress"; YButton -> if `isViewingContainer` is false
  (GFxValue call on the root), 0x1409139b0 (favorite). kInventoryUpdate as the inventory's for the
  player or the container (`DAT_143256180`), with 0x140914640 testing the item against the kept
  list. kUpdateController: the hotkeys select rows (1..9 as given, 11..20 minus 9 for the second
  column unless mode 3), Favorites closes, three column controls (`DAT_143256168/70/78`), Take All
  (`+0x120`) or `DAT_1432561c0` -> 0x140913d20 (take all, unless mode 2); the dev controls
  `DAT_143256190..b8` set the global `DAT_1420ba9b0` (a float: max, 5, 10, 25, 50, 100).

#### BarterMenu (vtable 0x14196f408)

- Accept 0x140901060: PlaySound, UpdateItem3D -> 0x140901360, RequestItemCardInfo -> 0x1409013c0,
  CloseMenu -> 0x1409014b0, ItemSelect -> 0x1409014e0, GetRawDealWarningString -> 0x140901840,
  StartMouseRotation, StopMouseRotation, ZoomItemModel -> 0x140901a30, QuantitySliderOpen ->
  0x140901c20.
- ProcessMessage 0x140900580: kShow builds the lists (`menu+0x30/38/40`) and computes the two
  barter multipliers: starting from 1.0 both, the player's perk entry point 0x11
  (kModBuyPrices, 0x140447180 / 0x140420be0) changes them, then the merchant (handle
  `DAT_143255bc4`) applies 0x14038cff0 twice with the actor values 8 and 0x3c (the barter
  factors of the Speech skill and the buy/sell multiplier), the buy multiplier is clamped to at
  least `DAT_1420aeae0` and at least 1.0, the sell multiplier to at most `DAT_1420aeaf8` and at
  most 1.0 (`settings.md` names those two by address); Invoke "SetBarterMultipliers"(buy, sell);
  fillers 0x140901d20, 0x140902270, 0x140901f10; notification 0xf8. kHide pops "InventoryMode".
  kUserEvent: zoom/accept -> "ToggleMenuFade" only. kInventoryUpdate for the player or the
  merchant. kUpdateController: hotkeys, Favorites closes, column controls `DAT_143255ba8/b0/b8`.

#### MagicMenu (vtable 0x14197a7f8)

- Accept 0x140952d10: PlaySound, UpdateItem3D -> 0x140953010, RequestItemCardInfo -> 0x140953070,
  CloseMenu -> 0x1409533b0, ShowTweenMenu -> 0x1409533e0, CloseTweenMenu -> 0x140953410,
  ItemSelect -> 0x140953450, SaveIndices -> 0x1409534e0, DisabledItemSelect -> 0x140953660,
  ShowShoutFail -> 0x1409536f0.
- ProcessMessage 0x140952080: kShow: 3D item in mode 2, the item's placement from one of two
  constant sets by the aspect ratio (above 4:3 the second), lists at `menu+0x30/38/40`, fillers
  0x1409539a0, 0x1409542f0, 0x140954220, 0x1409547b0. kUserEvent: YButton toggles the favorite of
  the selected spell (0x140951230 is favorite, 0x140951050 add, 0x140951150 remove, "UIFavorite",
  0x140956ef0 refresh, notification 0x103); XButton on a shout (form type 0x77 SHOU) with a
  word known but not unlocked: with no dragon souls (actor value 0x85 <= 0) the message "Use Dragon
  Souls to unlock shout", else a message box "Spend Soul?" with two buttons (`PTR_DAT_1420abc78`,
  "Cancel") and a `SpendSoulCallback`; Quick Magic -> close; LeftEquip/RightEquip ->
  "AttemptEquip"(1.0/0.0). kInventoryUpdate: refresh. kUpdateController: the hotkeys
  (`DAT_1432581a8..f0`, 0..9) -> 0x140954950(menu, hotkey, flag); Favorites closes.

#### FavoritesMenu (vtable 0x141975188)

- Accept 0x14092cb20: FadeDone -> 0x14092cc30, PlaySound, ItemSelect -> 0x14092ccd0.
- ProcessMessage 0x14092c8f0: kShow: 0x1409513d0 (the favorites manager `DAT_143223e50` refresh);
  if there are none (0x14092d920), hide at once (message 3 to `InterfaceStrings+0xb8`) and return
  1, else 0x14092dc10 when `DAT_143256400`. kUserEvent while not fading (`menu+0x71`): Left or
  Right Attack/Block (0x40, 0x48) equip the selection to that hand (0x14092df60 with 0x14038fa30 /
  0x14038fa40 giving the hand; both hands 0 when `menu+0x73`). kInventoryUpdate for the player with
  no item: if no favorites remain, "StartFadeOut".

#### MessageBoxMenu (vtable 0x14197c788)

- Accept 0x140962e80: buttonPress -> 0x140962f50, PlaySound.
- buttonPress 0x140962f50: the top of the message box stack (`DAT_143258408` array, `DAT_143258418`
  count) gives the box; its button index base `+0x4c` plus the argument is the result given to the
  box's callback (`+0x40`, slot 1); the box's sound at `InterfaceStrings+0x1f8` is played; the
  box is removed (0x140963410) and the next shown (0x140963530).
- ProcessMessage 0x140963050: kShow with boxes pending and the menu not open yet: show the next;
  kHide with boxes pending: show the next and return 1 (the menu stays).

#### TweenMenu (vtable 0x1419818b8)

- Accept 0x140988290: OpenHighlightedMenu -> 0x140988440, HighlightMenu -> 0x140988460,
  StartCloseMenu -> 0x140988480, CloseMenu -> 0x1409884a0, OpenAnimFinished -> 0x1409884d0.
- ProcessMessage 0x140987c00: kUpdate for its own name (`InterfaceStrings+0xf0`): 0x140988710,
  0x140988b40, and the player's 3D update. kShow when no other menu is pending
  (`DAT_1431a5720+0x20` == 0): the camera 0x1408f9910, "TweenMode", 0x140935550, a budget change
  (0x140669250 4, 0xa00000), the three skydome models of `PTR_s_Interface_INTPerkSkydome_nif`
  queued into `menu+0x30`, 0x140988710, the saved camera FOVs (0x14095f6f0 saves into
  `menu+0x48/4c`, 0x14095f710 sets `DAT_1420bba70/88`), 0x14117a120; else return 1. kHide:
  camera back (0x1408f9a00) and the FOVs restored. kUserEvent: `InterfaceStrings+0x270` (the
  loaded-models data) attaches the three models (0x140fc8e80); Tween Menu (0x118) -> the movie's
  slot 0x168 (close). kUpdateController: Quick Stats (0x298) -> 0x140988ba0(menu, 1); Quick Magic
  (0x290) -> message 1 to `+0xc8` (MagicMenu), "HideMenu", FOVs restored, camera state 6, the
  player's 3D off; Quick Inventory (0x288) -> message 1 to `+0x88` (InventoryMenu), camera state 7;
  Quick Map (0x2a0) -> 0x14098df90(`+0x110`, 1, player form id) and message 3 to `+0xf0` (itself),
  camera state 8; Favorites (0x240) -> close.

#### JournalMenu (vtable 0x141989d98)

- Accept 0x1409ac4d0: RequestPlayerInfo -> 0x1409ac8b0, RememberCurrentTabIndex -> 0x1409acc00,
  PlaySound, CloseMenu -> 0x1409ac6d0, ShouldShowMod -> 0x1409acc20 (only when the Creations
  service 0x141598ef0 / 0x141599440 says no), myLog -> 0x1409acd40.
- ProcessMessage 0x1409abe30: kUpdate with data types `+0x230` "ShowMenu", `+0x238`
  "SettingsSaved", `+0x250` "RefreshSystemButtons" (and 0x1409a6450 on the quest journal at
  `menu+0x98`), `DAT_143258b30` a `FadeThenLoadCallback` with the save slot in the payload
  (0x14098ddd0 fades then loads); other kUpdate data goes to the map/quest part 0x14098f170
  (`DAT_1431e0140`), returning 2 when it declines. kShow: 0x14098f470 (the map menu part with
  `+0x148`), the quest list hooked (0x1405b9680), Invoke "RestoreSavedSettings"(savedTab as double
  when the payload asks, else 0; bool: a setting pending `DAT_143258ec4` or the UI's `+0x170`),
  sound "UIJournalOpen", 0x1409ad230 (when Creations are off) or notification 0xfc, the FOVs saved
  and set (`DAT_1420bc980/98`). kHide: unless `menu+0xe0`, Invoke "StartCloseMenu"(true) and
  return 1. kUserEvent: swallowed (returns 0). kChatterEvent clears `DAT_1432303b2`.

#### SleepWaitMenu (vtable 0x14197f4e8)

- Accept 0x140975190: `DAT_141b5a298` (the accept callback) -> 0x1409752a0, Cancel -> 0x140975370,
  PlaySound.
- The accept 0x1409752a0: unless a hide is already queued for it (`InterfaceStrings+0x138`), the
  menu's sound, then the player sleeps (0x140741370, after a message box request 0x14098dd00 with
  `DAT_1420bb900`) or waits (0x1407414c0) for the slider's hours (the argument), marks itself
  running (`menu+0x51`) and zeroes its timer (`menu+0x30`).
- ProcessMessage 0x140974e00: kUpdate while running (`menu+0x51`) and the root is a display object:
  the timer accumulates the frame time `DAT_143275608`; each second it reads `getSliderValue` and
  the player's remaining hours (`player+0x8f4`, in game minutes: (m + 3599) / 3600); at 0 hours it
  stops, hides itself (message 3 to `+0x138`) and tells 0x140975900 whether it slept; while hours
  remain and are fewer than the slider's, `modifySliderValue(-1.0)` and 0x140975470. kShow: the
  payload's bool is sleeping (`menu+0x50`), Invoke "SetSleeping"(bool), 0x140665f80. kHide: if it
  ran, 0x140741580 (end sleep/wait) and the sound at `+0x200`; if it slept and the HUD is open
  (`+0xc0`) and no `+0x128` menu (the LevelUp menu) is open, a message box 0x14098dd00 with
  `DAT_1420bb900`; 0x1409354b0.

#### HUDMenu (vtable 0x141976708)

- Accept 0x140934cc0: PlaySound, RegisterHUDComponents -> 0x140934e20, GetButtonFromUserEvent ->
  0x140991e30, myLog -> 0x140934f80.
- ProcessMessage 0x140933180 (the pseudocode is 28k characters; only the Invoke names and the
  message types were read): kHide 0x14075adf0 / 0x140687cd0; kScaleformEvent handles "Swimming"
  and the crosshair; the HUD's own data types (the `HUDData` kinds, a switch on the data's kind):
  1 "ShowMessage", 3 "SetCrosshairTarget" (with the activate text built by 0x1402289c0 /
  0x140228290 / 0x140227ef0 and the owner check 0x140739610 / 0x140739980), 4 "SetLoadDoorInfo",
  5 "ShowSubtitle", 6 "HideSubtitle", 7 "ShowArrowCount", 9 "SetSubtitlesEnabled", 0x17
  "ShowElements", 0x1b push/pop the "Favor" control layer, 0x1c "ValidateCrosshair" with "Alert"
  or "Normal", 0x1d "SetLocationName", 0x1e "ShowTutorialHintText", 0x1f "SetCrosshairEnabled",
  0x20 the compass markers (0x140d02350, 0x140cf5500, 0x140cf7330), 0x21
  "RefreshActivateButtonArt" (the Activate control's art, 0x140992020), 0x22 the tutorial
  messages (`MessagesInstance`, `MessageArray`, `ShownMessageArray` members; the control layers
  "HUDModes", "HorseMode", "WarHorseMode", "MovementDisabled"), 0x23 the survival meters
  (`aTemperatureLevel`, `aColdPenaltyPercent`, `aHungerPenaltyPercent`,
  `aExhaustionPenaltyPercent`, "ShowSurvivalElements").

#### GiftMenu (vtable 0x141975538)

- Accept 0x14092f6b0: PlaySound, UpdateItem3D -> 0x14092f9b0, RequestItemCardInfo -> 0x14092fa10,
  CloseMenu -> 0x14092fb00, ItemSelect -> 0x14092fb30, DisabledItemSelect -> 0x14092fd70,
  StartMouseRotation, StopMouseRotation, ZoomItemModel -> 0x14092fd90, QuantitySliderOpen ->
  0x14092ff80. ProcessMessage 0x14092ed20 not read.

#### The others

Console (vtable 0x141970a80, Accept 0x140909ad0, ProcessMessage 0x1409092d0), MainMenu
(0x14197b570, 0x140958690, 0x140959f90), LoadingMenu (0x141978d40, 0x14094b5b0, 0x14094b680),
FaderMenu (0x141974c00, 0x14092bfb0, 0x14092be70), CursorMenu (0x141974588, no Accept,
0x14092a070), StatsMenu (0x141980128, 0x140978020, 0x140976a50), LevelUpMenu (0x1419788b0,
0x14094aa80, base ProcessMessage), TrainingMenu (0x141981158, 0x140985670, 0x140985740),
LockpickingMenu (0x141979a10, no Accept, 0x14094d350), TutorialMenu (0x141981508, 0x140987140,
0x140986d40), BookMenu (0x14196fd90, no Accept, 0x1409063d0): not read.

### The item lists (`ItemList`, `StandardItemData`, `ItemCard`)

An item menu's `ItemList` (0x58 bytes at `menu+0x48` in the inventory, `+0x30` in the barter and
magic menus) holds the movie, the `_root.GetInventoryItemList` value and its `entryList` array.
Each entry is a `StandardItemData` (vtable 0x14196f3c8) made by 0x140903e60: it asks the entry's
source for its GFxValue (slot 0x68 of the data source), then sets the members `text` (slot 1 of the
item data), `count` (slot 2), `equipState` (slot 3), `filterFlag` (slot 4), `favorite` (slot 5)
and `enabled` (slot 6). The magic menu's `MagicItemData` adds `soulLVL` (0x140940e50, for a soul
gem of form type 0x34 SLGM with a soul: the level name through 0x14028ef00). The `ItemCard`
(0x40 bytes, ctor 0x140947110: the movie's value through slot 0x68 and a 0x801-byte text buffer)
is filled by 0x1409472c0 (5167 bytes, not read in full), which sets `spellCost`, `potionType`,
`effects`, `weight`, `value`, `damage`, `armor` and `bestInClass` on the card's data; its field
names are the strings at 0x141978580..0x141978680.

## Perks and their entry points

SkyrimSE.exe 1.7.104.0. Names are CommonLibSSE-NG's where they have one (`BGSPerk`,
`BGSPerkEntry`, `BGSEntryPoint`, `BGSEntryPointPerkEntry`, `BGSSkillPerkTreeNode`). Ported in
`skyrim/esm/perk.zap` (the records), `game/sim/perks.zap` (what an actor holds and the entry
points), `game/sim/perktree.zap` (choosing in a constellation), `interface/statsmenu.zap`.

### The records

- `BGSPerk::Load` 0x140396cc0. PERK: EDID, FULL, DESC, the CTDAs before DATA (the conditions that
  say who may take it, +0x58), DATA (trait, minimum level, ranks, playable, hidden), NNAM the next
  perk of its chain (`BGSPerk+0x78`), then the entries. Each rank of a tree's perk is a record of
  its own, linked by NNAM (Armsman 00, 20, 40, 60, 80); an earlier rank stops applying through a
  `HasPerk(next) == 0` condition on its own entries, not by any replacement.
- An entry opens with PRKE (type 0 quest, 1 ability, 2 entry point; rank; priority) and closes with
  PRKF. Quest: DATA = quest form, stage. Ability: DATA = spell. Entry point: DATA = entry point,
  function, number of parameters (the owner counts); then for each parameter that has conditions a
  PRKC (its index) followed by its CTDAs; EPFT the type of the function's data (1 one value, 2 two
  values, 3 leveled list, 4 activate choice, 5 spell, 6 text) and EPFD the data.
- The entry points are the table at 0x1420994f0 (0x20 bytes each: name, parameter list, function
  type); the 92 are CommonLibSSE-NG's enum (`kModSkillUse` 0x16, `kModAttackDamage` 0x23...).
  The function kinds (the `DAT_14209a080` table, 0x18 each): 1 set 0x14038d2c0, 2 add 0x14038d330,
  3 multiply 0x14038d3a0, 4 add range 0x14038d410, 5 add actor value mult 0x14038d550, 6 absolute
  0x14038d8e0, 7 negative absolute 0x14038d950, 8 add leveled list 0x14038d9c0, 9 add activate
  choice 0x14038db70, 10 select spell 0x14038de50, 11 select text 0x14038dec0, 12 set to actor
  value mult 0x14038d630, 13 multiply actor value mult 0x14038d710, 14 multiply 1 + actor value
  mult 0x14038d7f0, 15 set text 0x14038e030. The numeric ones check the data's type (one value for
  1 to 3, two for 4, 5, 12 to 14); Skyrim.esm uses 1, 2, 3 and 14 for numbers (and 9, 10, 11, 15
  for the rest).

### Holding a perk

- `Actor::HasPerk` 0x14069f920 -> `ActorProcess::HasPerk` 0x1407280c0 gives the perk's rank (0 for
  none) from the actor's `BGSPerkRankArray` (`FindPerkInRanksVisitor`). Papyrus `Actor.AddPerk`
  0x140360010 (calls the actor's virtual +0x7d8 with rank 0), `RemovePerk` 0x140360130 (+0x7e0)
  and `HasPerk` 0x1403601d0 (-> 0x1403394e0). The player's own list is `PlayerCharacter+0x4d8`
  (0x14075bb70); the rank event (type 0x5f, `FUN_1406694c0`) is handled by 0x140397640: the
  entries whose rank + 1 is the new rank are applied (vtable +0x58), those whose rank + 1 is the old
  one removed (+0x50). Entry-point entries are inserted into the actor process's per-entry-point
  lists (0x5c lists of 0x18 bytes at `ActorProcess+8 -> +0x288`, 0x14069f950) sorted by
  0x140397600: priority (+9) higher first, then rank (+8) lower first. Quest entries
  (0x140395c00) set the stage; ability entries (0x140395f80) add the spell.
- The Rested spells are abilities whose magic effect (MGEF DATA +136, `EffectSetting` +0xd8) names a
  perk (RestedPerk 1.05, RestedWellPerk 1.1, RestedMarriagePerk); the port gives an actor the perks
  of the abilities it knows at rank 1. The place the exe adds that perk was not found (the
  active effect's start does not call the +0x7d8 virtual), so this is the effect of the data, not a
  port of the call.

### Asking the entry points

`BGSEntryPoint::HandleEntryPoint(entry, owner, args..., results...)` 0x14038cff0: the entry's
parameter count (table +0x8) counts the owner; then one pointer for each result of the function
type (`DAT_14209a1f0`: 1 for a number). The owner's list for the entry point is walked
(`Actor::ForEachPerkEntry` 0x14069f9c0) with `HandleEntryPointVisitor` 0x14038d170: an entry is
asked `EvaluateConditions` (0x1403960d0): it needs exactly its parameter count of forms; for each
parameter the entry's tab (the conditions of its PRKC) must hold for that form, a null form
meeting only an empty tab; then its function runs on the value with the owner as the actor whose
values the actor-value functions read (current value, `ActorValueOwner` +8).

Call sites ported (entry, owner, parameters, value):

| entry | site | owner | parameters | value |
|---|---|---|---|---|
| 0x16 skill use | 0x14078dcb0 | the player | - | the amount a use adds, after the use mult (also for the unscaled uses) |
| 0x1c power attack damage, 0 weapon damage, 0x23 attack damage | the hit's data 0x1407f0030..0x1407f17c0 | attacker | weapon, target | the hit's damage |
| 0x24 incoming damage | 0x1407f17c0 | target | attacker, weapon | the same |
| 0x12 sneak attack mult | 0x1407f17c0 | attacker | weapon, target | the multiplier, then the damage times it |
| 8 buy prices, 0x3c sell prices | the barter menu 0x140900580 | the player | merchant | the factors (buy at least 1, sell at most 1 after) |
| 0x38 pickpocket chance | 0x14041d860 | thief | victim, item | the chance after the detected penalty, before the limits |
| 0x26 spell cost | 0x140151780 area (`MagicItem::GetCost`) | caster | spell | the magicka cost |
| 0x1e duration, 0x1d magnitude | active effect start 0x1405baed0 | caster | spell, target | the effect's |
| 0x2a, 0x29 incoming duration and magnitude | same | target | spell | the same |

Not ported: the others (crit, armor and resistance 0x25, bashing 0x1a, detection 0x2f 0x30 0x39 0xf
whose pure formulas in `game/stealth` take no world, lockpicking, smithing, alchemy 0x42 at the
table, enchanting, leveled-list and spell entries, the quest-stage `Activate` choices).

### Choosing a perk in the stats menu

- The tree is the AVIF's nodes: PNAM the perk, FNAM, XNAM/YNAM grid place, HNAM/VNAM the place in
  the constellation, SNAM the skill, CNAM each child's index, INAM the node's index
  (`BGSSkillPerkTreeNode`, 0x140446920). Node 0 is the root (no perk).
- The confirmation callback `PerkSelectConfirmCallback` 0x140982480 (after "Are you sure you want
  this perk?") runs 0x1409790a0: it takes the node (menu+0x1c8 -> `0x1409812b0`), walks the chain of
  its perk by +0x78 counting what the player has (`Actor::HasPerk`), takes the first he has not,
  and when the conditions of that perk's record (+0x58, `FUN_1404a6e20`) hold for the player and he
  has not all of them: the player's virtual +0x7d8 (AddPerk, rank 1), the sound
  `UISkillsPerkSelect2D`, perk points -1 (0x14097e820: the byte at `PlayerCharacter+0xb11`), the
  card updated (0x14097a2e0), and `SetStatsMode(no points, points)` called on the movie.
  0x14097f8b0 is the same test without the effect (the key handler asks it before the box);
  0x14097e710 the points.
- The menu has no GameDelegate call for the choice: the 3D cursor and the box are the game's; the
  port's `chooseSkillPerk` is the confirmation. Not ported: the constellation scene, the cursor,
  `SetDescriptionCard` for a perk node.

## Render captures: what SkyrimSE.exe draws in the inn, read from RenderDoc

The game's own frames of compare.zap's six poses, captured with RenderDoc 1.46 (portable, in
`C:/tools/renderdoc`) and replayed without the game. The captures (`C:/tools/skyrim-rdc/*.rdc`) and
the scripts (`C:/tools/skyrim-rdc/harness`, `analysis`) stay outside the repository: they hold the
game's data.

### How they are taken (headless)

- `harness/hidden.py` starts a program on a hidden desktop of the session (`CreateDesktopW`): no
  window on the user's screen, no input.
- `qrenderdoc.exe --py harness/trigger.py` (on that desktop) launches SkyrimSE.exe injected
  (`ExecuteAndInject`), waits for the main menu, sends console commands, triggers one capture
  (`TargetControl.TriggerCapture`) and writes its path. qrenderdoc's first run asks about analytics:
  `Analytics_TotalOptOut: true` in `%APPDATA%/qrenderdoc/UI.config` keeps that dialog away.
- The console commands go in without keys (`harness/console.py`): the command string is written
  into the game and the console's execute (0x140909f90 in 1.7.104) is called on a thread of the game.
  `sStartingConsoleCommand` does not serve: this build reads it only at shutdown (0x140654610).
  Windows Defender flags that script (Exploit:Python/Leivion.C, a process injection pattern); the
  user excluded `C:/tools/skyrim-rdc`.
- The pose: `coc RiverwoodSleepingGiantInn`, then `bat zappose` (`harness/pose.py` writes it into the
  game's folder: fov, the three actors disabled, `tai`, setpos, setangle, `tm`).
- `analysis/*.py` (run the same way): `list.py` the actions, `history.py` a pixel's history,
  `cbuf.py` an event's constant buffers and targets, `shader.py` its bytecode, `texdata.py`
  textures, `fogfade.py` the SAO composite of every capture.

### What they show (start pose unless said)

- The floor's lighting draw (event 6095, BSLightingShader, the same instructions as ours): the sun's
  DirLightColor is 65 70 80 / 255 x 1.5 (the image space's sunlight scale); the point lights' colors
  are their color x fade x 0.781 (the fire) and x 0.868: the executable's flicker (0.76..0.91), not
  the measured 0.6 rest flicker.zap had; the directional ambient rows are ours (mean 0.175 0.187
  0.187, the -z/+z half difference on z).
- The SAO composite (ISSAOCompositeSAOFog, every pose): FogParam (0.025641, 0.00025641, 1, 1) = fog
  from 100 to 4000 units, power 1, max 1; FogNearColor = FogFarColor = 31 52 46 / 255 with w 0.8333,
  the fog fade the composed picture is multiplied by. Ported (occlusion.zap's fogFade). The source: BSShaderManager::State's
  invFrameBufferRange (CommonLibSSE, offset 0x9C), a static 1 / 1.2 at 0x1420d694c that only the
  SetFramebufferRange console command (handler 0x14037ac30) changes; Nukem9's SkyrimSETest writes
  it into FogNearColor.w.
- The HDR blend (ISHDR): Param (0.85, 1 / 1.1^2 = 0.826446, 0), Cinematic (1.05, 0, 1.2, 1.15), Tint
  (0.627 0.392 0.039, 0.05): ours; the 2 x 2 adapted luminances 0.162 0.150 / 0.191 0.197, both
  channels equal at rest; the bloom texture is all but black (mean 0.03 / 255). The blend's formula
  applied in Python to the game's input gives its output on 99.9% of the pixels within 8, and on
  ours gives our grade's output on 100%: the grade is exact, what differs is the scene before it.
- TAA's BlendParams (0.5, 0.8, 0.21, 0.21): ours (rest 0.8, speed 0.5, sharpen and overlay 0.21).

With the sun, the flicker and the fog fade as the game has them, our scene before the grade matches
the game's within 1 to 5% by band with the colors in balance (the saturation gap gone), 76.7% of
its pixels within 8; compare.zap's total moved 523.5 to 517.5 (table 96.4, backroom 96.9, start
82.1, bar 88.3): what is left is in the scene, pixel by pixel.

### The shadow mask (event 5197, RENDER_SHADOWMASKDPB)

The fire light's mask: the place from the depth (no normal offset), carried by the light's
view-projection (the paraboloid's axis the light's x, its projection `z' = (z - 0.1) / 0.9` on that
axis, the same in the map pass 117), its hemisphere's half of the atlas, the distance over the radius
(521.677) less a bias of 0.0125, compared 16 times at a Poisson disk (the shader's table) of radius
1/512 of the atlas, a tap that would leave its hemisphere keeping its v; a camera-distance fade
`1 - (d^2 / 9e6)^8` on the sum. Ported in `world/shaders/shadow.gpu.zap`: our shadowed share of the
start pose 21.7% against the game's 21.3% (the old 3 x 3 read with a 0.0005 bias: 23.7%), the two
masks agreeing on 97.8% of the pixels (97.0% before); compare.zap's total 517.5 to 513.9.

### The lit effects' light

Every lit effect draw (the bar's dust beams, event 8034; the start pose's 11420) takes its light from
the pixel constant buffer's row 8, the vanilla Effect.hlsl's PropertyColor: 105 114 118 / 255 on
every pose (alpha 0.9 for the beams), the unlit effects 1 1 1. Ours summed the cell's ambient and
each light by its fall-off at the pixel, which lit the bar's beam far brighter than the game's
(alpha 0.17 at a color of 0.13 there). Ported as a constant (`lighting.gpu.zap`'s effectLighting):
bar 88.3 to 96.2, total 513.9 to 522.8.

Where it comes from (found with the community's names, `C:/tools/skyrim-decomp/names.tsv`): the
effect's SetupGeometry (BSEffectShader 0x141557090) writes PropertyColor from
`BSEffectShaderProperty+0x88`, the external emittance color pointer (white when null), and alpha
from `+0x30`. The NIF's External Emittance flag (SLSF1 0x2000_0000) has the pointer aim at the
reference's emittance source (XEMI, ExtraEmittanceSource, extra 0x63): a LIGH's color, or a REGN's
`+0x40`, which TESObjectCELL 0x1402ba000 fills each frame with the region's weather's effect
lighting color (NAM0 color 9) at the hour: Sky::FillColorBlend 0x140416760 weighs two times of day
by the climate's TNAM (sunrise begin minus and sunset end plus fDaytimeColorExtension 0.5, half
widths, the middle one's own color), Sky::SetColor 0x140414cf0 sums the bytes times 1/255. The
inn's beams and the windows of its walls (FarmWindowInterior01, BSLightingShader: EmitColor =
`*emissiveColor x emissiveMult`, SetupGeometry 0x141549550) name REGN WeatherPineForest, whose
weathers include SkyrimClear; Update.esm sets SkyrimClear's day effect lighting to 105 114 118,
the captures' value exactly. Ported: `skyrim/esm/weather.zap`, `world/emittance.zap`, Skyrim.esm
opened with Update.esm and the DLC masters as overlays (`esm/file.zap`). With a lit effect
(Effect_Lighting) the shader instead takes DLightColor = sunlightScale x sun fade x the sun's
effectColor (NiDirectionalLight+0x14C, Sun::Update 0x14041bd90 copies Sky.skyColor[9]; in an
interior Sky::UpdateColors 0x140412df0 sets it to the cell's directional color).

### The captures' flicker state (exact11)

The fire and the lamps flicker at random (the executable's draws, 0x140274be0), so a capture holds
one state of them, and ours at another made the lit floor 5 to 7% off the game's: the start pose
drew the fire at 0.846 of its fade, the game's capture at 0.781. `analysis/lightrows.py` reads the
pixel constant buffer slot 3 (the shader's cb2: light positions in rows 15..21 with the radius in
w, colors in rows 22..28) of every draw; a light is told by its radius (the positions are relative
to each draw's own origin), its dimmer is the row's red over the light's prepared color (LIGH color
times its fade). A light the game has not updated reads 1.0 (start: the lamps of radius 184 and
380; firepit: also the shadow light). compare's poses.json lists them as `dimmers`, one a cell
light in the scene's order (fire, shadow light, then the lamps of radius 251, 447, 400, 184, 380,
251), 0 for a light the capture does not show (the two of radius 251 cannot be told apart by
radius), and compare.zap passes them as main.zap `--dimmers`. Share within 8 by pose, total 522.9
to 534.2: start 82.9 to 89.0, bar 96.2 to 95.6, firepit 62.5 to 64.8, table 93.7 to 94.1,
backroom 97.0, pelt 90.6 to 93.7. This is the capture's own state, not a fitted factor; what is
left is real.

### The shadow map's far plane (table pose)

The shadow pass (table capture, events 117..: VS 12370/12376, PS 12605..12608; raster state: back faces
culled, no hardware bias) writes SV_POSITION.z = |paraboloid vector| x 1/radius (cb0[1].x), with no
clamp: a fragment past the radius has z > 1 and the hardware clips it, so the map holds 1.0 (the
clear) there. Ours clamped the depth at 1 in the vertex stage, so a large triangle with a vertex past
the radius (the wall behind the table's pelt) interpolated too-near depths and shadowed a pelt at the
radius's edge (the stretched distance, the axis scaled by 1 / 0.9, puts the pelt at 1.0016 of the
radius): the fire's shadow ended at the pelt's left third in the game and covered all of it in ours;
a bias of 0.05 instead of 0.0125 hid it, which showed the occluder was within 26 units. Slice 1
of the atlas (texture 209, array 8, 2048 x 2048) is the fire's, slice 0 the other shadow light's.
`paraboloid` no longer clamps: table 94.1 to 96.4, pelt 93.7 to 94.6, start 89.0 to 89.2, firepit
64.8 to 65.0, total 534.2 to 537.8.

### The start pose's remaining difference, measured stage by stage

`analysis2/savexr.py` (job file: capture, event, texture, out.exr) saves any texture of a capture as
EXR; `analysis2/evdump.py` lists an event's textures, targets and constant buffers and saves its pixel
shader. With them the start pose's chain was compared stage by stage (our stage read by a temporary
shader hack, none kept):

- The mask (event 5197, texture 92) and our fire share disagree on 1.3% of the pixels, edges only.
- The lit color before the composite (event 11258, texture 55) matches ours within 1 to 4% (the
  bottom rows) with no fog and no occlusion; the occlusion (texture 134, red) is 0.996 on the floor
  in both. The fire's share regresses to 1.00 and the lamps' to 0.98.
- The lit shader does not fog its output: the DXBC ends in `min(c, c - FogNearColor.w x fogged(c) +
  clamp)` and `o = c - over x cb12[42].z` with cb12[42].z = 0, so the vertex stage's fog (radial
  distance, FogParam) only feeds the clamps. The fog is the SAO composite's alone: `lerp(ao x lit,
  fog color, share) x 0.8333` with share = (z - 100) / 3900 on the planar view depth z (the dp2 in
  its depth formula is the standard 2 n f / (...)); the game's HDR is reproduced from its own lit
  color, occlusion and depth to 0.003 mean error. Ours fogs in the lit stage (radial, from the
  cell's 0) and not in the composite; porting the game's form (lit stage unfogged, composite fogging
  at 100..4000) leaves the HDR error as it is (0.0157) and moves the total 537.8 to 537.4, so it was
  not kept.
- The ISHDR blend's output (event 13098, texture 116) equals our grade on the game's HDR and the
  game's 2 x 2 luminances (every pixel within 8, mean error 0.001): the grade is exact.
- The TAA pass (event 13129) is not a bias: binned by the graded luma it looked 3 to 5% darker on
  the bright floor, which is regression to the mean (the bin picks the pixels whose current value
  is above their history's); over the picture the output is 1.008 of the input, and the final pass
  (event 13202: its depth-of-field factor is 0 on every pixel, the 320 x 240 blur is unused) writes
  the TAA output unchanged. The remaining floor difference is between the capture's frame and the
  reference PNG: `assets/reference/*.png` are other frames than the `.rdc` files (the PNG's floor
  luma is 0.2548, the capture's 0.2695, ours 0.2681; PNG against capture: 93.5% within 8), so the
  flicker state of the PNG is not the one `dimmers` reads from the capture.
- TAA is ported exactly (`world/shaders/taa.gpu.zap`, see below).
- The door at the pit's right: see "The open door".
- The captures' samplers are anisotropic 16; the RHI's are 8 (16 changes 2% of the pixels, the share
  not at all).

### The TAA pass, ported from the DXBC (event 13129)

The pixel shader (`analysis2/ev13129.ps.dxbc`, disassembled with `analysis/dis.py`) is
Community Shaders' ISTemporalAA.hlsl, SDR path, instruction for instruction. Its inputs: t0 the
graded picture (RGBA8), t1 the history (RGBA8: luma, confidence, motion), t2 the motion vectors
(zero here: the camera stands still), t3 the depth, t4 a mask (its y is 0 here: no reject), t5 the
alpha coverage (a black 16 x 16: none); outputs 0 the color and 1 the new history. The constant
buffer (cb2): TexelSizeParams (1/W, 1/H), NeighborWeights (the bilinear weights that un-jitter the
frame: 0.34 center, 0.22 up, 0.27 left, 0.17 up-left for a jitter of 0.4375, 0.389 px),
TexelOffset (1/W, -1/H), BlendParams (0.5, 0.8, 0.21, 0.21), ThresholdParams.w 0.1.

- The history is luma, not color: the pixel and its eight neighbours give a bracket (the nearest
  luma under the history's and the nearest at or over it; -0.001 and 1.001 stand for none, and the
  other end for a missing one), kept as red, blue and luma (green is what the luma 0.5 g + 0.25 r
  + 0.25 b leaves); the color is the bracket's, interpolated where the history's luma lies.
- The weight on that resolve: lerp(0.8, 0.5, motion), capped by 1 - 20 |motion change|, then raised
  toward 0.99 by the confidence = saturate(0.25 saturate(neighbours 0.2 or more away in luma - 4)
  + 0.95 history confidence) times 1 - 100 |motion change|. A confidence under 0.9025 clamps the
  history luma into the bracket and lets a missing end stand for the other; above it the bracket
  keeps its sentinels (the game's wide bracket).
- The frame's own color is un-jittered (a bilinear read at the pixel shifted by the jitter), the
  resolve sharpened away from it by BlendParams z and laid back over it by w.
- The new history: luma + weight (history luma - luma) (the luma itself when that is under 0.01),
  the confidence, the motion (|velocity| over 128 pixels, saturated); 8 bits each.
- Checked in numpy on the capture's own inputs (`C:/tools/skyrim-rdc/analysis3/taa_np.py`): 99.8%
  of the color's pixels and 99.3% of the luma's within 1/255 of the game's output, the confidence
  99.99%. Ported in Zap: `taaFeedbackPixel` writes the history and `taaPixel` the color (the RHI
  has one target a pass); the history targets are RGBA8 as the game's. The jitter is ours (a
  centered Halton, the picture un-jittered by the shift beginFrame applied); the game's NeighborWeights
  are its own jitter's bilinear weights. Not ported: the mask and alpha coverage branches (dead
  here) and dynamic resolution.
- Measured: compare.zap's total 537.8 to 537.7 (start 89.2 to 89.3, bar 95.6 to 95.4, firepit 65.0
  to 65.2, table 96.4, backroom 97.0 to 96.9, pelt 94.6 to 94.5): none, as the picture is static
  and its history has converged; the port is kept for being the game's.

### The open door

The door at the pit's right is FarmhouseAnimDoor02 `000E3A79` (RiverwoodInnDelphineRoomDoor, at
-1023.9 415.5, persistent, owner Delphine's faction; the other FarmhouseAnimDoor02, `000E3A7B` at
-767.7 -417.6, is left of the start pose's view). Neither has ONAM or an XLOC; Update.esm and the
DLC masters do not touch them; the only records that name `000E3A79` are MQ106's property
(InnRoomDoor) and MQ106IntroScene's condition, none running at a new game. The game's open state
of a door is set at its 3D load by TESObjectREFR::InitNonNPCAnimation 0x1402ef180 (SetOpenState
0x1401d9eb0 with the reference's ExtraAction bit 8, which ONAM sets, flipped by two form-id sets
of the Game singleton: none at a new game).

What opens it is the AI: the pathing system cuts every loaded door into the navmesh, a path through
a closed door carries it as a point, and the actor reaching the point sends itself
MovementMessageActivateDoor, whose handler (0x1406a81d0) activates the door; nothing plays Close, so
an actor that opens a door leaves it open (`projects/skyrim/README.md`, Doors). The harness (`harness/trigger.py`)
loads the cell with `coc`, lets the game run 30 seconds, then `bat zappose` disables Delphine
(`13485`), Orgnar (`13486`) and Embry (`3550C`) and waits 15 seconds more before the capture.
Delphine's reference is placed in the hall (-494.8 155.0) while her package at every hour is
DelphineStartInRoom (the room at about -1004 640, whose only entrance is this door): she walks there
through the door in those 30 seconds. The port does the same: the residents start at their
references, walk over the navmesh and open the door at the crossing (walktests.zap), and the door is
drawn in its pose: its NIF's Open sequence turns the node Door02 about z from 0 to about 90 degrees
in one second (`world/movables.zap`, doortests.zap), the leaf a movable part of the prepared cell
rather than baked into its buffer. A headless run of 3000 frames (`main.zap --free --at -900,100,0
--eye 120 --look 335,-5 --bare`) shows it open with Delphine in her room.

### The references are the captures' final frames

The PNGs in `assets/reference` were taken at another moment than the `.rdc` captures that pinned
the dimmers (the start PNG's floor luma 0.2548, its capture 0.2695), so compare.zap now measures
against each capture's own presented frame: `analysis/finals.py` saves the last action's output as
`<pose>-final.png` (1280 by 960, beside the PNGs, never committed) and poses.json names it in the
pose's `capture` field; a pose without the file falls back to its PNG, masks apply to both. The
firepit capture stood on the pit's step, not at the pose: the camera is read from the draws
(`analysis3/objpos.py`: each draw's model matrix translation is the object minus the eye; the mode
of the translation differences over models both captures draw, against the start capture, gives the
eye; bar, table, backroom and pelt come out exactly at their poses), here (-500, -335, 184), so
poses.json's `captureAt` holds the feet (-500, -335, 63.35) and compare.zap draws ours there.
Share within 8, PNG baseline to capture final: start 89.3 to 88.4, bar 95.4 to 94.6, firepit 65.2
to 68.0, table 96.4 to 95.7, backroom 96.9 to 98.9, pelt 94.5 to 93.6; total 537.7 to 539.2.
There is one capture of each pose, so no game-against-game ceiling is measured; the ceiling is the
share that the capture's own TAA jitter and the flicker state (already pinned) leave, not
measurable without a second capture of the same pose.

### The captures' TAA jitter and dimmers, pinned per pose (poses.json)

The TAA event's cb1[1] holds the frame's jitter in uv; in pixels it is the centered Halton (2, 3)
point of index 1..8, exactly ours (picture.zap's beginFrame): start 8, bar 1, firepit 3, table 7,
backroom 7, pelt 2 (the index is (capture number + 2) mod 8, 8 for 0). poses.json's `jitter` gives
it and compare.zap passes `--jitter-phase` so the last of its 30 frames lands on that index
(`analysis4/taacb.py`). Total 539.2 to 540.2 (start 88.4 to 88.2, firepit 68.0 to 68.9, table 95.7
to 95.8, backroom 98.9 to 99.1, the rest unchanged): the history converges, the jitter only moves
edges.

poses.json had lost its `dimmers` (the file is git-ignored), so the 539.2 above was unpinned.
`analysis4/perdraw.py` lists every draw's lights; a light's dimmer is the red of its exact-radius
rows (a draw divides the radius by the object's scale, so scaled rows are skipped) over our
prepared color (fire 2.0353, the lamps 1.1647), the most common value across draws (the bar's
draws before event 4371 hold an earlier flicker state, 0.8985 / 0.7979, than the later ones).
The two radius-251 lamps are told by their offset inside one draw (+240 in x for lamp 2). Order
fire, shadow light, 251, 447, 400, 184, 380, 251:
start 0.7809 0 0 0.8872 0.8684 1 1 0; bar 0.8958 0 0 0.7861 0 0 0 0; firepit 0.8138 1 0 0 0.8821 1 1 0;
table 0.7781 0.8777 0 0 0.8437 0 0.8107 0; backroom 0 0 0.8571 0 0 0 0 0.8312;
pelt 0.8231 0.7743 0 0 0.7652 0 0.8037 0. Total 540.2 to 544.0: start 89.6, bar 93.0 (from 94.6),
firepit 70.0, table 96.2, backroom 99.2, pelt 96.0.

What remains: the bar's capture has Orgnar standing at the counter (ours has none there), and the
flicker's position offsets (at most 8 units for a lamp, 2 for the fire) and the SAO's per-frame
angle are not pinned.

## Skills, levels and the stats menu

SkyrimSE.exe 1.7.104.0. Names are CommonLibSSE-NG's where they have one. `PlayerCharacter+0x9c0`
points to `PlayerSkills`, whose `Data` is: xp (+0x0), levelThreshold (+0x4), then for each of the
18 skills (actor values 6 to 23) a `SkillData` at 0x8 + 0xc k: the skill's level when the
character last rose (+0x8), its xp in the level (+0xc), its threshold (+0x10); the legendary count
of each at 0xe0 + 4 k. Settings below are `SettingT` addresses; the value is at +8.

### Experience of a skill

- `Actor::UseSkill(av, points, advanceObject, action)` is the virtual at +0x7b8 (slot 0xf7);
  `PlayerCharacter`'s (0x1407499e0) does nothing for points <= 0 and calls `AddSkillExperience`.
  The base `Actor`'s (0x1406990e0) is empty: NPCs gain nothing.
- `PlayerSkills::AddSkillExperience(av, points, object, action, scaled, quiet)` 0x14078dcb0: for a
  skill below 100 (the constant at 0x141b5bf14), `AVIF+0x108` is the AVSK (`useMult`, `useOffset`,
  `improveMult`, `improveOffset`, read by 0x1404454e0). `scaled` (UseSkill) makes the amount
  `points x useMult + useOffset`; the perk entry point 0x16 (Mod Skill Usage) then changes it
  (0x14038cff0; this is where the Rested bonus applies, through the perks of its ability). The
  amount is added to the skill's xp; while xp >= threshold: xp -= threshold, the skill's base
  value +1 (`ActorValueOwner::ModBaseActorValue`, slot 5), the new threshold is
  `pow(level, fSkillUseCurve 0x1420a8ca0) x improveMult + improveOffset` (0 from 100), the
  character's xp gains `floor((n+1) n / 2) - floor(n (n-1) / 2)` times `fXPPerSkillRank`
  (0x1420a8ce8), that is the new level n, and the SkillIncrease event is sent (0x14073af50).
  Unless quiet, the notice `sSkillIncreased` ("%s Increased to %i") is shown (0x1409364b0).
- `IncrementSkill` 0x140749a20 -> `PlayerSkills` 0x14078e0a0 (a skill book, a trainer): count 0 is 1;
  each level adds `threshold - xp` unscaled and quiet but for the last; the share of the level
  already earned (xp / threshold) is kept of the new one. The Papyrus natives are 0x14035d110
  (AdvancePCSkill) and 0x14035d1c0 (IncrementPCSkill). 0x14078e200 is the legendary reset (xp and
  threshold 0, the count +1).
- The thresholds at the start: 0x14078ea70 measures them from the skills' levels.

### Where the player's skills are used

All call the virtual at +0x7b8. Ported (game/combat/practice.zap, game/sim/skills.zap):

| site | skill | amount |
|---|---|---|
| 0x1406cd2f0 (the hit handler), attacker is the player, total damage > 0 | the hit's skill (HitData+0x88) | the weapon's base damage (`TESAttackDamageForm` slot 4), 0 without a weapon |
| same, bash flag (HitData flag 0x4000) | Block | `0x14041f410`: damage x (`fShieldBashSkillUseMult` 0x1420a7cf8 / `fWeaponBashSkillUseMult` 0x1420a7d28) + (`fShieldBashSkillUseBase` 0x1420a7ce0 5 / `fWeaponBashSkillUseBase` 0x1420a7d10 1) |
| same, the player is hit and the hit is blocked (flag 1) | Block | (physical - total damage) x `fWeaponBlockSkillUseMult` (0x1420a7e00) + `fWeaponBlockSkillUseBase` (0x1420a7de8) |
| same, not blocked | Heavy (11) or Light (12) Armor | the physical damage; each worn armor (rating > 0, not clothing) adds 2 to its skill for the body piece, else 1; a roll `rand % 6` under the light weight is light, under light plus heavy is heavy, else none |
| the magic effects' update and cast: 0x1405bd8f0, 0x1405bf8d0 (concentration, each update), 0x1405c39e0 (once, when the spell is let go), 0x1405c41b0 (cloaks), 0x1405c5890 | the effect's school | `SpellItem::GetSkillUsageData` 0x140155540: the costliest effect's cost (at most the spell's cost when not auto-calculated) x `EffectSetting+0x100` (skill usage); a concentration spell x dt |
| player update 0x140756950 | Sneak (15) | `0x140421800`: `fSkillUsageSneakPerSecond` (0x1420aa9f8) x dt while 0 != 100 - highest detection < `iSkillUsageSneakFullDetection` (100) |
| the stealth meter 0x14093a7e0 reaching 0 (`$HIDDEN`), 0x140756ab0 | Sneak | `fSkillUsageSneakHidden` (0x1420aaa10, 2.5) |
| pickpocket success 0x140759b90 | Pickpocket (13) | `0x140421ca0`: pow(value taken, `fPickpocketSkillUsesCurve` 0x1420aabc0) |
| barter, each stack bought or sold (`BarterMenu` 0x1409014e0) | Speech (17) | `GetSpeechcraftBarterExperience` 0x140228940: the item's (tempered) value rounded to 0.1 |

Not ported (call sites): Lockpicking (14) 0x14094f0c0 and 0x14094f6d0 (the amount by the lock's
level, `LockpickingMenu::GetSkillUsage` 0x1404215f0: `fSkillUsageLockPick*`), Smithing (10) the
crafting and tempering menus 0x14091fab0, 0x140920860, 0x140921de0, 0x1409225f0, 0x1409228d0
(`GetConstructedObjectSkillAdvanceAmount` 0x140421be0, tempering 0x140421960), Enchanting (23)
0x140944590, training (`TrainingMenu::SetSkillXpPercent` 0x140986030, `iSkillPointsTagSkillMult`),
the Papyrus `Game.AdvanceSkill` 0x140a23d20, and the other UseSkill callers 0x1406ca640 and
0x1406d8890 (not read).

### The character's level

- `PlayerSkills::CanLevelUp` 0x14078e250: xp >= threshold (`levelThreshold`).
- `UpdateLevel` handler 0x14035d240 (the console/script command): while the character can: step
  0x14078e270 (the sound `UILevelUp`, the level +1 in the player's base, the LevelIncrease event
  0x14073afe0) then `AdvanceLevel(0)`.
- `PlayerSkills::AdvanceLevel(addThreshold)` 0x14078e320: xp -= threshold (the old one; true adds
  nothing); the new threshold is `level x fXPLevelUpMult (0x1420a8cd0) + fXPLevelUpBase
  (0x1420a8cb8)` with the level already raised (Skyrim.esm: 25 and 75; the exe's 30 and 170); each
  skill's `level` is read again from the actor value owner (slot 2); the perk-granting arrays at
  `DAT_14219e570+0x90` are walked; health is raised by `fPCHealthLevelBonus` (0x1420a8f58,
  Skyrim.esm: 0); the damage modifier of health, magicka and stamina (0x18 to 0x1a) is taken off
  (0x1406c5440 reads it, 0x1406c47f0 undoes it): all three restored.
- The level-up menu (`LevelUpMenu`, levelupmenu.swf) registers `addHealth`, `addMagicka`,
  `addStamina` and `PlaySound` (0x14094aa80). The choice 0x14094ad60: `ModBaseActorValue(av,
  iAVDhmsLevelUp 0x14209ca98)` (10), for stamina also `ModActorValue(0, carryweight 0x20,
  fLevelUpCarryWeightMod 0x1420a8d00)` (Skyrim.esm 5), then `AdvanceLevel(0)`, the menu closed.
  The port raises the level in the same step as the choice (the exe's `UpdateLevel` step does it
  before the menu's `AdvanceLevel` reads the new level; the call that runs it for the menu was not
  found).
- It is offered when the character can rise and `0x1409924d0` (a global at form 0x148's value 1)
  does not block: the tween menu's open (0x140988710, `StartOpenMenuAnim(levelUp, date, level,
  progress)`) and waking from sleep (0x1407415a0). The HUD reminds "Level up available." every
  `iLevelUpReminder` (0x140936de0).
- Perk points are `PlayerCharacter+0xb11` (a byte); the stats menu spends one per perk
  (0x14097e820, which adds its argument when the menu is not in the Beast mode). The level is
  risen in the stats menu's message handler (0x140976a50): when the character can rise (0x14078e250) it
  calls UpdateLevel (0x14078e270), opens the level-up menu (0x14094ac40) and adds one perk point
  (0x14097e820 with 1); the port does the same.

### The stats menu

- `StatsMenu` (statsmenu.swf; vtable 0x141980128, constructor callbacks 0x140978020) is told:
  `UpdateSkillList` 0x140979790: `StatsMenu.SkillStatsA` (SetVariableArray) holds 5 values for
  each of the 18 skills (the order is the menu's array at `StatsMenu+0x50`, default Heavy Armor):
  the actor value's current value rounded down, its name (0x140442fd0), `xp / threshold x 100`
  (0x14078dc10), the colour (0x140992510: current less base less damage modifier below -0.001 red
  `#FF0000`, above 0.001 green `#189515`, else `#FFFFFF`) and the legendary count; then
  `UpdateSkillList(english)`.
- `SetPlayerInfo` 0x14097da30 (13 arguments): the player's name, level, `xp / threshold x 100`,
  the race's name, then for magicka, health and stamina the current value (rounded down, not below
  0), the maximum (current less the damage modifier) and the colour.
- `SetStatsMode(perkPoints == 0, perkPoints)` 0x14097a0d0; `ShowLegendaryButtonHint` when a
  skill is 100 (0x14097a2e0); `SetDescriptionCard` (8 values: the selected skill's description,
  value, the next rank's perk...) 0x14097a2e0; the camera `MoveCamera`/`SetFadedIn`; the sounds
  `UISkillsStop`, `UISkillsGlow`, `UISkillsPerkSelect2D`, `UISkillsTransitionUp`.
- The movie registers these with `GameDelegate.addCallBack` (`SetDescriptionCard`, `SetPlayerInfo`,
  `UpdateSkillList`, `HideRing`, `SetPerkCount`, `ShowLegendaryButtonHint`); the port calls them
  through `delegate`. The movie's own loading raises 8 script errors in the port's AVM1 (five
  `gotoAndStop` on a clip it does not find, three `SetText` calls before `InitExtensions` defines
  it, as in the game's order); the later calls raise none.
- The perk tree (`BGSSkillPerkTreeNode`, the 3D constellations `INTPerkStars01.nif`,
  `INTPerkLine01.nif`), choosing a perk (0x140978580: "Are you sure you want this perk?", then
  0x1409790a0) and the entry points are in `perks.md`; the constellations' 3D scene is not ported.

## Stealth: sneaking, detection and pickpocketing

What SkyrimSE.exe 1.7.104.0 does, read from its decompilation (the functions at the addresses
below; `names.tsv` has the community names, the settings are in `gmst-*.md`). The port is
`game/stealth/` (the formulas; `hearing.zap` the events), `game/sim/stealth.zap` (the state), `game/combat/` (witnesses, sneak
attacks), `interface/` (the eye, the pickpocket menu); `stealthtests.zap` checks it.

### Sneaking

- The Sneak command (`SneakHandler::ProcessButton` 0x1407b3a80) toggles: it sends the graph the
  sneak start or stop event (`Actor::SetSneaking` 0x1406aee40 sets the graph variable `iIsInSneak`).
  `Actor::IsSneaking` 0x1403ccaa0 reads the actor state's 0x200 bit (and not 0x400).
- The sneaking player moves by the graph's sneak locomotion (`Sneak_Locomotion_Behavior`): the
  clips `sneakwalk_forward` (47.2 units a second in the behavior project's motion files) and
  `sneakrun_forward` (132.9) blended by `SpeedSampled`, the walk's and the run's at 82.5 and 350.9.
  The eye of a sneaking actor is 0.57 of its standing height (0x140685b30).

### The detection value (Actor::CalculateDetection 0x1406a33b0)

Per watcher and watched; the game keeps one `DetectionState` (0x1407c6510: level at +0x10, view
cone +0x14, line of sight +0x15) per pair and reads it again when it is older than
`fDetectionUpdateTimeMin` (1 s) and rejects it past `fDetectionUpdateTimeMax` (2 s): the table at
0x1420b8ab8 (min, max by kind; the player's kind 3 is 1 and 2), the refresh `0x1407c3eb0`, the job
`DoDetectionJob` 0x1407c5220 which stores the result with `0x1407c6600`. A watcher has detected the
watched while its level is above 0 (`Actor.IsDetectedBy` 0x140a00ef0, `RequestDetectionLevel`
0x1406a2520); a level never worked out is -1000.

1. Reach (0x14041cd30): `fSneakMaxDistance`, times `fSneakExteriorDistanceMult` outside, times
   `fSneakFlyingDistanceMult` when either flies; a watcher fighting another has
   `fDetectionCombatNonTargetDistanceMult` of it. Past it: -1000. Off the watcher's facing by more
   than `fDetectionLOSDistanceAngle` (60 degrees) the reach shrinks linearly to
   `fDetectionLOSDistanceMultInterior`/`Exterior` straight behind (0x1406a33b0).
2. Line of sight (`RequestLOS` 0x1406a2830, `CalculateLOSLocation` 0x1406a30c0): only inside half
   `fDetectionViewCone` (190 degrees) of the facing (the heading to the watched is 0x1406a32c0), a
   ray from the watcher's eye (its eye height, 0x140687450) to the watched's chest (half its
   height), head (0.85) or legs (0.15), each 0.57 of that sneaking; one reaching is a sight. The
   port takes the rays from the cell's physics (`game/seen.zap`).
3. The sum (0x14041cd90) = noise + light + skill + `fSneakBaseValue`:
   - noise = (`(int)fSneakActionMult` x the sound level of the watched's last action (Actor +0x11c,
     set by `0x14069fe50` from `0x14041d3f0`: Loud 100, Normal 50, Silent 0, Very Loud 200, for
     `fActorAlertSoundTimer` s) + (`fSneakRunningMult` when running) x (`fSneakEquippedWeightMult` x
     the weight it wears and holds (0x14023bd30) + `fSneakEquippedWeightBase`) x its Movement Noise
     Mult x moving) x `fSneakSoundsMult` x attenuation x (1 + `fSneakSleepBonus` if the watcher
     sleeps); `fSneakSoundLosMult` of it without a line of sight.
     Moving is speed >= 5 (0x1406aefa0); running is speed past the walk and the run blended by
     `fJogInterpolationBetweenWalkAndRun` (0x1406742a0).
   - attenuation = (1 - distance / reach)^`fSneakDistanceAttenuationExponent`, 0 past the reach.
   - light = (in the sight and not invisible) x attenuation x (1 + `fSneakLightRunMult` running +
     `fSneakLightMoveMult` moving) x (light level x `fSneakLightMult` (`...ExteriorMult` outside)
     + `fDetectionSneakLightMod`) x (100 - Blindness)/100 (0 asleep) x `fDetectionLargeActorSizeMult` x
     the race size's `fSneakDetectionSize*`.
   - light level = the watched's light level truncated (x `fDetectionNightEyeBonus` with the
     watcher's Night Eye), less the ambient (outside `iLightLevelExteriorMod`, inside the cell's
     ambient x 100 at most `iLightLevelInteriorMod`), kept between 0 and `iLightLevelMax`.
   - skill = (attenuation x (1 + `fSneakAlertMod` fighting + `fSneakSleepMod` asleep +
     `fSneakCombatMod` fighting another + the ambush package's `fSneakAmbushTargetMod`/`NonTarget`)
     x ((`fSneakPerceptionSkillMax` - `...Min`) x the watcher's Sneak / 100 + `...Min`) - the
     watched's Sneak while it sneaks) x `fSneakSkillMult`. The player's Sneak enters as
     `fPlayerDetectionSneakMult` x skill + `fPlayerDetectionSneakBase` (0x14041cd90 start).
   - The value is its truncation, 1 for one between 0 and 1; 0 counts as -1.
4. The light on an actor (`0x140726250`, stored in the process, 0x3a8, by `0x1406ff490`): the sum of
   the lights near it (`0x141576ca0`: dimmer x the color's mean x (1 - (distance / radius)^2)) plus the
   cell's ambient mean plus the directional mean times the shader manager's scale, times 100;
   recomputed every `fLightRecalcTimerPlayer` (0.5 s, `fLightRecalcTimer` 2 for the others).
5. A sound that is not the watched's own (a detection event, 0x14041d230): the same terms with the
   event's sound level in place of the action and the light level `iDetectEventLightLevelInterior`/
   `Exterior`; the event's reach is `fDetectEventSneakDistanceVeryLoud` for very loud sounds.

### Detection events (the second half of CalculateDetection 0x1406a33b0)

- The store: `SetActorsDetectionEvent` 0x1406f2560 writes, in the process (AIProcess +0x3d8) of the
  actor that made the noise, its sound level's value, the place, the game time and the causing
  reference; one for each actor, the next replacing it. `0x1406f26e0` drops it past
  `fDetectionEventExpireTime` (5 s); `0x1406f2540` reads it.
- The makers (the callers of 0x1406f2560): a spell effect applied (0x1405cdf50: the caster's place,
  `0x14041d3f0` of the effect's casting sound level, MGEF DATA at 140; the caster's perk entry
  0x37 may silence it; it also sets the caster's action level, 0x14069fe50), a summon (0x1405e3a50,
  Loud), an explosion (0x140261310, the EXPL's level, at the explosion), a projectile's impact
  (0x14031def0, the impact data's level), a papyrus `ObjectReference.CreateDetectionEvent`
  (0x140a451f0, the level as given). A blow makes none: a swing or a draw only sets the action
  level (0x1406cbee0: the weapon's, or the NPC's, sound level, for `fActorAlertSoundTimer`), which
  the first half's noise term reads. `0x14041d3f0` maps the record's level: 0 Loud (iSoundLevelLoud
  100), 1 Normal (50), 2 Silent (0), 3 Very Loud (200).
- The read, after a sight that left the level at -1000, -1 or 0: skipped when the watcher's faction
  reaction to the watched (0x14069ca50) is ally or friend (2, 3), and when neither it nor the
  watched holds a combat controller (Actor +0x158) and, for the player, `IsHostileToActor`
  (0x14068c9d0, the attack-on-sight rule 0x14068c170) is false. The event is then compared with
  `fDetectEventDistancePlayer` (1536; the NPCs' 512 for another watched), times
  `fDetectEventDistanceVeryLoudMult` (2) from `iSoundLevelVeryLoud`; a ray (0x1406a2e20) to its
  place, the cone test, and the sum of 0x14041d230: (`fSneakActionMult` x level x
  `fSneakSoundsMult` x (1 - distance / reach)^`fSneakDistanceAttenuationExponent`, x
  `fSneakSoundLosMult` without a line of sight; reach `fSneakMaxDistance`, `fDetectEventSneakDistance
  VeryLoud` for a very loud sound, times the exterior mult) + the light of the place
  (`iDetectEventLightLevelInterior`/`Exterior` x the light mult, x attenuation, in the cone, 0
  asleep) + `fSneakBaseValue`. Above 0 the reading is level 0 with the event's place
  (`DetectionState::Set` 0x1407c6600 keeps it at +0x3c). Else the watched's projectiles (the
  projectile manager's list, owner the watched) within `fDetectProjectileDistancePlayer` (1024;
  NPC 512) of the watcher's head are tried the same way as a Normal (50) sound.
- The cone test compares the angle to the sound in radians with half of `fDetectionViewCone` in
  degrees (the first half converts), so a sound whose point the eye reaches is always in the cone.
- A level of 0 is a noise heard and no one seen. `Actor::SendAssaultAlarm` 0x140682ed0 takes as
  witnesses the actors whose level against the criminal is above 0 (`RequestDetectionLevel`
  0x1406a2520); whatever else a heard place does (the AI packages) is not read here.
- Whether an actor attacks another on sight (0x14068c170) from the aggression value and the faction
  reaction (0 neutral, 1 enemy, 2 ally, 3 friend): unaggressive attacks no one; aggressive an enemy;
  very aggressive a neutral or an enemy (an ally or friend never); frenzied anyone.

### The eye (the stealth meter)

`PlayerCharacter` 0x140756950 runs each frame: the highest level any active actor holds against the
player (`ProcessLists` 0x140786350); above 0 the value is 100, else 0 (in combat the combat group's
stealth points, 0x140852450, are used); the HUD message (0x140935340) carries it and whether the
player sneaks (and is not in the 0x400 state). `StealthMeter::ProcessMessage` 0x14093a700 plays the
`StealthMeterInstance` timeline's `FadeIn`/`FadeOut` and sets the HUD mode `StealthMode`;
`Update` 0x14093a7e0 moves the shown value 30 percent of the way to it each frame and sets
`SneakAnimInstance`'s frame to its 1.01 times; arriving at 0 or 100 it writes `$HIDDEN` or
`$DETECTED` into `SneakTextInstance` and plays `SneakTextHolder` from `Start`.

### Sneak attacks

A sneak attack is a hit of a sneaking attacker on a target that has not detected it; the damage is
multiplied by the weapon type's `fCombatSneak*Mult`.

### Pickpocketing

- The activation text (0x1403c1000) reads "Pickpocket" for a living actor that is not a teammate,
  of a race with `kAllowPickpocket` (RACE DATA flags 0x800000), while the player sneaks. Detection
  does not decide it.
- `ContainerMenu` mode 2 (`DAT_1432560b8`): the victim's items less what it wears; the selected
  item's card gets `pickpocketChance` (0x140911310: one item of one that weighs something, the
  whole stack of one that weighs nothing; clamped 0..100); the menu sets `bNPCMode`.
- The chance (0x14041d860) = `fPickPocketTargetSkillMult` x the victim's Pickpocket +
  `...TargetSkillBase` + `fPickPocketActorSkillMult` x the player's Pickpocket + `...ActorSkillBase`
  + `fPickPocketAmountMult` x the gold value of the items + `...AmountBase` +
  `fPickPocketWeightMult` x their weight + `...WeightBase`, less `fPickPocketDetected` when the
  victim has detected the player, between `fPickPocketMinChance` and `fPickPocketMaxChance`,
  rounded half up.
- Taking (`PlayerCharacter::AttemptPickpocket` 0x140759b90) rolls 0..99 against the chance: at or
  above it the attempt fails: the victim's state is set to level 100 (0x1406a2580), a pickpocket
  crime is added (0x1406827e0; the bounty is the faction's CRVA pickpocket gold), the message "You've
  been caught pickpocketing." shows and the menu closes. Else the items move, stolen from the victim,
  the player's Pickpocket skill gaining experience by their value (`0x140421ca0`).
- Items cannot be put into the victim ("You cannot place items in a container while pickpocketing.").

### Not modelled

Perk entry points (0x39, 0x30, 0x2f, 0xf, 0x38 the pickpocket chance, 0x20, 0x45, 0x54); the skill
experience (Sneak: `fSkillUsageSneakHidden`, `fSkillUsageSneakPerSecond`; Pickpocket:
`fPickpocketSkillUsesCurve`); of the detection events the explosions', impacts' and summons'
makers and the projectiles in the air (the fights have none), the combat stealth points of the meter, the ambush
package's flag, the race size (all medium), a weapon's own sound level (all Loud, fists Normal),
`fSneakDetectionSizeLarge` actors, mounts, the flying states, and the shader manager's directional
scale (1).
