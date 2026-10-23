# The game settings combat, the sounds and the dialogue read, by their editor ids (lower case):
# Skyrim.esm's GMSTs, else the value compiled into the executable for those the plugin leaves out,
# listed here with their source. Combat's come from UESP's Skyrim:Block, Skyrim:One-handed,
# Skyrim:Sneak and Skyrim:Health pages, and two (the NPCs' damage multiplier's ends, which UESP gives
# as +2% a skill point) are named here after the player's (fDamagePCSkillMin/Max) for want of the
# executable's names. The dialogue's is SkyrimSE.exe's own: its static settings hold the value just
# before the pointer to the name.

# long: a table of settings, one a line
pub exeSettings {str: f64} = {
	"fdamagepcskillmin": 1.0,   # the player's damage multiplier at skill 0 (UESP: 1 + skill / 200)
	"fdamageskillmin": 1.0,   # an NPC's at skill 0
	"fdamageskillmax": 3.0,   # an NPC's at skill 100 (UESP: +2% a point)
	"fcombathitconeangle": 35.0,   # degrees each side of the facing a melee swing reaches
	"fshieldbasefactor": 0.45,   # a shield's share blocked before its rating
	"fshieldscalingfactor": 0.2,   # its rating's part, per 100 points
	"fplayermaxresistance": 85.0,
	# the barter's (economy.zap), the exe's static settings; the plugin sets fBarterMin/Max
	"fbartermin": 1.4,
	"fbartermax": 2.4,
	"fbarterbuymin": 1.05,
	"fbartersellmax": 0.95,
	# the flight's (flee.zap), the exe's static settings
	"fcombatdpsmeleespeedmult": 1.0,
	"fcombatdpsbowspeedmult": 0.2,
	"fcombatconfidencemodifiermin": -0.5,
	"fcombatconfidencemodifiermax": 0.5,
	"fconfidencecowardly": 1000.0,
	"fconfidencecautious": 2.0,
	"fconfidenceaverage": 1.0,
	"fconfidencebrave": 0.5,
	"fconfidencefoolhardy": 0.0,   # the most a block (and a resistance) takes off, percent
	"fweaponbashmin": 0.1,
	"fweaponbashpcmin": 0.1,
	"fweaponbashpcmax": 0.5,
	"fshieldbashpcmin": 0.1,
	"fcombatsneakbowmult": 2.0,
	# the combat AI's (chances.zap, ai.zap): the executable's static settings, read as the dialogue's are
	"fcombatattackchancemin": 0.05,
	"fcombatattackchancemax": 1.0,
	"fcombatattackchanceblockingmultmin": 0.2,
	"fcombatattackchanceblockingmultmax": 0.67,
	"fcombatattackchancelastattackbonus": 1.5,
	"fcombatattackchancelastattackbonustime": 5.0,
	"fcombatblockchancemin": 0.0,
	"fcombatblockchancemax": 1.0,
	"fcombatblockchanceweaponmult": 0.25,
	"fcombatblocktimemin": 4.0,
	"fcombatblocktimemid": 8.0,
	"fcombatblocktimemax": 10000.0,
	"fcombatbashchancemin": 0.025,
	"fcombatbashchancemax": 0.2,
	"fcombatbashtargetblockingmult": 0.0,
	"fcombatoffensivebashchancemin": 0.0,
	"fcombatoffensivebashchancemax": 0.05,
	"fcombatcirclechancemin": 0.0,
	"fcombatcirclechancemax": 0.75,
	"fcombatcircleanglemin": 30.0,
	"fcombatcircleanglemax": 90.0,
	"fcombatcircleangleplayermult": 0.75,
	"fcombatfallbackchancemin": 0.0,
	"fcombatfallbackchancemax": 0.5,
	"fcombatfallbackdistancemin": 96.0,
	"fcombatfallbackdistancemax": 256.0,
	"fcombatfallbackwaittimemin": 0.75,
	"fcombatfallbackwaittimemax": 1.5,
	"fcombatgroupoffensivemultmin": 0.1,
	"fcombatselecttargetupdatetime": 1.0,
	"fcombatselecttargetswitchupdatetime": 3.0,
	"fcombatfleedistanceinterior": 2048.0,
	# the stagger's (strike.zap, from reference/exe/README.md, "Combat: what the executable
	# computes"; the exe's static settings)
	"fstaggerattackbase": 0.5,
	"fstaggerattackmult": 0.01,
	"fstaggerblockbase": 0.5,
	"fstaggerblockmult": 0.005,
	"fstaggerblockattackshieldbase": 1.0,
	"fstaggerblockattackshieldmult": -0.005,
	"fstaggermassbase": 0.0,
	"fstaggermassmult": 1.0,
	"fstaggermassoffsetbase": 3.0,
	"fstaggermassoffsetmult": 0.15,
	"fstaggerplayermassmult": 2.0,
	"fstaggershieldmult": 1.0,
	"fstagger1weapmult": 0.2,
	"fstagger2weapmult": 0.5,
	"fstaggerrecoilingmult": 1.5,
	"fstaggerrunningmult": 1.5,
	"fstaggerblockingmult": 1.0,
	"fstaggermin": 0.05,
	"fstaminaregendelaymax": 5.0,   # seconds without stamina regeneration after a power attack
	"isecondstosleepperupdate": 900.0,   # game seconds each frame of waiting or sleeping passes
	"fdialogspeechdelayseconds": 2.0,   # how long a line without a voice file is said
	"faimingreetingdistance": 150.0,   # an actor greets the player this near (the default No NPC Greetings names)
	# the damage the player takes and deals at each difficulty, Novice to Legendary (very easy to legendary)
	"fdiffmulthptopcve": 0.5,
	"fdiffmulthpbypcve": 2.0,
	"fdiffmulthptopce": 0.75,
	"fdiffmulthpbypce": 1.5,
	"fdiffmulthptopcn": 1.0,
	"fdiffmulthpbypcn": 1.0,
	"fdiffmulthptopch": 1.5,
	"fdiffmulthpbypch": 0.75,
	"fdiffmulthptopcvh": 2.0,
	"fdiffmulthpbypcvh": 0.5,
	"fdiffmulthptopcl": 2.5,
	"fdiffmulthpbypcl": 0.25,
	# stealth's (game/stealth): the executable's static settings, which the plugin overrides where it
	# sets them (reference/exe/README.md, its "Game settings" sections, holds their addresses)
	"fsneakbasevalue": -25.0,
	"fsneakmaxdistance": 1500.0,
	"fsneakexteriordistancemult": 2.0,
	"fsneakflyingdistancemult": 2.0,
	"fsneakdistanceattenuationexponent": 2.0,
	"fsneaksoundlosmult": 0.25,
	"fsneaksoundsmult": 1.6,
	"fsneakactionmult": 1.0,
	"fsneakequippedweightbase": 12.0,
	"fsneakequippedweightmult": 0.5,
	"fsneakrunningmult": 2.0,
	"fsneaklightmult": 1.4,
	"fsneaklightexteriormult": 1.0,
	"fsneaklightmovemult": 0.01,
	"fsneaklightrunmult": 0.2,
	"fdetectionsneaklightmod": 0.0,
	"fsneaksleepbonus": -0.5,
	"fsneaksleepmod": -0.2,
	"fsneakalertmod": 0.2,
	"fsneakcombatmod": -0.4,
	"fsneakambushtargetmod": 2.5,
	"fsneakambushnontargetmod": -0.25,
	"fsneakdetectionsizesmall": 0.5,
	"fsneakdetectionsizenormal": 1.0,
	"fsneakdetectionsizelarge": 1.5,
	"fsneakdetectionsizeverylarge": 2.0,
	"fdetectionlargeactorsizemult": 1.0,
	"fsneakperceptionskillmin": 10.0,
	"fsneakperceptionskillmax": 90.0,
	"fsneakskillmult": 0.5,
	"fplayerdetectionsneakbase": 0.0,
	"fplayerdetectionsneakmult": 1.0,
	"fdetectionviewcone": 190.0,
	"fdetectionlosdistanceangle": 60.0,
	"fdetectionlosdistancemultinterior": 0.75,
	"fdetectionlosdistancemultexterior": 0.5,
	"fdetectioncombatnontargetdistancemult": 0.75,
	"fdetectionnighteyebonus": 3.0,
	"fdetectionupdatetimemin": 1.0,
	"fdetectionupdatetimemax": 2.0,
	"ilightlevelinteriormod": 50.0,
	"ilightlevelexteriormod": 0.0,
	"ilightlevelmax": 100.0,
	"fpickpocketactorskillbase": 40.0,
	"fpickpocketactorskillmult": 0.0,
	"fpickpockettargetskillbase": 20.0,
	"fpickpockettargetskillmult": -0.25,
	"fpickpocketamountbase": 0.0,
	"fpickpocketamountmult": -0.05,
	"fpickpocketdetected": 25.0,
	"fpickpocketweightbase": 0.0,
	"fpickpocketweightmult": -5.0,
	"fpickpocketminchance": 5.0,
	"fpickpocketmaxchance": 95.0,
	"fdetecteventsneakdistanceveryloud": 3072.0,
	"isoundlevelveryloud": 200.0,
	"isoundlevelloud": 100.0,
	"isoundlevelnormal": 50.0,
	"isoundlevelsilent": 0.0,
	"fdetecteventdistanceplayer": 1536.0,
	"fdetecteventdistancenpc": 512.0,
	"fdetecteventdistanceveryloudmult": 2.0,
	"fdetectprojectiledistanceplayer": 1024.0,
	"fdetectprojectiledistancenpc": 512.0,
	"fdetectioneventexpiretime": 5.0,
	"idetecteventlightlevelinterior": 225.0,
	"idetecteventlightlevelexterior": 75.0,
	"fjoginterpolationbetweenwalkandrun": 0.5,
	"factoralertsoundtimer": 5.0,
	# the skills' and the levels' (skills.zap; reference/exe/README.md, "Skills, levels and the
	# stats menu" has each address)
	"fskillusecurve": 1.25,
	"fxplevelupbase": 170.0,
	"fxplevelupmult": 30.0,
	"fxpperskillrank": 1.0,
	"fpchealthlevelbonus": 5.0,
	"iavdhmslevelup": 10.0,
	"flevelupcarryweightmod": 10.0,
	"fshieldbashskillusebase": 5.0,
	"fshieldbashskillusemult": 0.0,
	"fweaponbashskillusebase": 1.0,
	"fweaponbashskillusemult": 0.0,
	"fweaponblockskillusebase": 0.0,
	"fweaponblockskillusemult": 1.0,
	"fskillusagesneakpersecond": 0.5,
	"fskillusagesneakhidden": 2.5,
	"iskillusagesneakfulldetection": 100.0,
	"fpickpocketskillusescurve": 1.0
}

# a setting's value: the plugin's, else the executable's; a name in neither is a bug
pub fn gmst(settings {str: f64}, name str) f32:
	f32(settings.get(name) ?? (exeSettings.get(name) ?? fail("no game setting {name}")))

# What a difficulty (iDifficulty: 0 Novice, 1 Apprentice, 2 Adept, 3 Expert, 4 Master, 5 Legendary)
# multiplies in a fight, by the game settings fDiffMultHPToPC* and fDiffMultHPByPC*.
pub type DifficultyMultipliers:
	toPlayer f32   # the damage the player takes
	byPlayer f32   # the damage the player deals

pub fn difficultyMultipliers(settings {str: f64}, difficulty i64) DifficultyMultipliers:
	suffix = ["ve", "e", "n", "h", "vh", "l"][difficulty.clamp(0, 5)]
	DifficultyMultipliers(toPlayer = settings.gmst("fdiffmulthptopc{suffix}"),
		byPlayer = settings.gmst("fdiffmulthpbypc{suffix}"))
