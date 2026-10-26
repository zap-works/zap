# The journal's settings pages (quest_journal.swf's gameplay, display and audio lists) as the game
# answers them: RequestGameplayOptions, RequestDisplayOptions and RequestAudioOptions give each
# entry of the page's list its ID, its value and its default, from the player's ini settings
# (skyrim/ini.zap); OptionChange applies a choice and SaveSettings writes the changed settings in
# SkyrimPrefs.ini's form into this game's own folder (never the real game's); the controls page
# is inputMap.zap's. A slider's value is
# 0..1 over the range its setting spans, a stepper's the index of its option, a check box's 0 or 1.

import engine.swf.avm1
import skyrim

pub type OptionKind:
	Slider
	Stepper
	Check

# An entry of a page: the key of its text in the list the movie builds, the setting it is and how
# the setting maps to the menu's value.
type OptionDef:
	page i64   # 0 gameplay, 1 display, 2 audio
	text str
	kind OptionKind
	setting str   # "bShowCrosshair:Interface"
	low f64 = 0.0   # a slider's setting at 0
	high f64 = 1.0   # and at 1
	steps f64[] = []   # a stepper's setting at each of its options

pageGameplay = 0
pageDisplay = 1
pageAudio = 2
# an entry's ID is its page's hundred and its place in the table
idPerPage = 100
minutesSteps = [5.0, 10.0, 15.0, 30.0, 45.0, 60.0, 0.0]   # Save on Pause: the options' minutes, 0 off
difficultySteps = [0.0, 1.0, 2.0, 3.0, 4.0, 5.0]   # Very Easy to Legendary

# long: the settings of three pages, one a line
options OptionDef[] = [
	OptionDef(0, "$Invert Y", .Check, "bInvertYValues:Controls"),
	OptionDef(0, "$Look Sensitivity", .Slider, "fMouseHeadingSensitivity:Controls", low = 0.01,
		high = 0.05),
	OptionDef(0, "$Vibration", .Check, "bGamePadRumble:Controls"),
	OptionDef(0, "$Difficulty", .Stepper, "iDifficulty:GamePlay", steps = difficultySteps),
	OptionDef(0, "$Show Floating Markers", .Check, "bShowFloatingQuestMarkers:GamePlay"),
	OptionDef(0, "$Save on Rest", .Check, "bSaveOnRest:SaveGame"),
	OptionDef(0, "$Save on Wait", .Check, "bSaveOnWait:SaveGame"),
	OptionDef(0, "$Save on Travel", .Check, "bSaveOnTravel:SaveGame"),
	OptionDef(0, "$Save on Pause", .Stepper, "fAutosaveEveryXMins:SaveGame", steps = minutesSteps),
	OptionDef(1, "$General Subtitles", .Check, "bGeneralSubtitles:Interface"),
	OptionDef(1, "$Dialogue Subtitles", .Check, "bDialogueSubtitles:Interface"),
	OptionDef(1, "$Crosshair", .Check, "bShowCrosshair:Interface"),
	OptionDef(1, "$Tree LOD Fade", .Slider, "fTreesMidLODSwitchDist:Display", high = 7200.0),
	OptionDef(1, "$Specularity Fade", .Slider, "fSpecularLODMaxStartFade:Display", high = 4000.0),
	OptionDef(1, "$Light Fade", .Slider, "fLightLODStartFade:Display", high = 3500.0),
	OptionDef(1, "$Shadow Fade", .Slider, "fShadowDistance:Display", high = 10000.0),
	OptionDef(1, "$Grass Fade", .Slider, "fGrassStartFadeDistance:Grass", high = 7000.0),
	OptionDef(1, "$Object Fade", .Slider, "fLODFadeOutMultObjects:LOD", high = 30.0),
	OptionDef(1, "$Item Fade", .Slider, "fLODFadeOutMultItems:LOD", high = 10.0),
	OptionDef(1, "$Actor Fade", .Slider, "fLODFadeOutMultActors:LOD", high = 15.0),
	OptionDef(1, "$HUD Opacity", .Slider, "fHUDOpacity:Interface"),
	OptionDef(1, "$Brightness", .Slider, "fGamma:Display", low = 0.6, high = 1.4),
	OptionDef(1, "$DDOF Intensity", .Slider, "fDynamicDOFFarBlur:Display"),
	OptionDef(2, "$Master", .Slider, "fAudioMasterVolume:AudioMenu"),
	OptionDef(2, "$Effects", .Slider, "fEffectsVolume:AudioMenu"),
	OptionDef(2, "$Footsteps", .Slider, "fFootVolume:AudioMenu"),
	OptionDef(2, "$Voice", .Slider, "fVoiceVolume:AudioMenu"),
	OptionDef(2, "$Music", .Slider, "fMusicVolume:AudioMenu")
]

# the sound categories (editor ids, lower case) the audio sliders set the volume of
# long: a table, one a line
pub volumeCategories {str: str} = {
	"audiocategorymaster": "fAudioMasterVolume:AudioMenu",
	"audiocategorysfx": "fEffectsVolume:AudioMenu",
	"audiocategoryfootsteps": "fFootVolume:AudioMenu",
	"audiocategoryvoice": "fVoiceVolume:AudioMenu",
	"audiocategorymus": "fMusicVolume:AudioMenu"
}

# The player's settings as they stand while the game runs: the ini files' (then this game's own),
# the choices made on the settings pages since, and where they are saved.
pub type Prefs:
	settings skyrim.IniSettings
	folder str   # this game's folder, empty without a user's folder
	changed str[] = []   # the settings chosen since the last save
	revision i64 = 0   # counts the choices, for whoever applies them
	controls InputMap   # the keys of the commands

# the settings read from the ini files and the keys from the install's controlmap.txt, to be saved
# in `folder`
pub fn openPrefs(install skyrim.Install, folder str) Prefs:
	Prefs(settings = skyrim.readIniSettings(), folder = folder.copy(),
		controls = install.openInputMap(folder))

pub fn prefsOf(settings skyrim.IniSettings, folder str, move controls InputMap) Prefs:
	Prefs(settings = settings.copy(), folder = folder.copy(), controls)

pub fn isOn(p Prefs, setting str) bool:
	p.settings.isSettingOn(setting)

pub fn number(p Prefs, setting str) f64:
	p.settings.iniNumber(setting)

# the player's difficulty (iDifficulty)
pub fn difficulty(p Prefs) i64:
	i64(p.number("iDifficulty:GamePlay")).clamp(0, 5)

# the volume slider of each sound category that has one (0..1), by the category's editor id
pub fn volumes(p Prefs) {str: f32}:
	out {str: f32} = {}
	for category, setting in volumeCategories:
		out[category.copy()] = f32(p.number(setting))
	out

# the menu's value of a setting's text
fn menuValue(d OptionDef, text str):
	x = f64.parse(text) ?? 0.0
	match d.kind:
		Check: 1.0 if x != 0.0 else 0.0
		Slider: ((x - d.low) / (d.high - d.low)).clamp(0.0, 1.0)
		Stepper:
			best = 0
			for k, s in d.steps:
				if (s - x).abs() < (d.steps[best] - x).abs(): best = k
			f64(best)

# the setting's text a menu value gives
fn settingText(d OptionDef, value f64):
	match d.kind:
		Check: "1" if value >= 0.5 else "0"
		Slider: "{d.low + value.clamp(0.0, 1.0) * (d.high - d.low):.4}"
		Stepper: "{d.steps[i64(value + 0.5).clamp(0, d.steps.len - 1)]:.0}"

# the entries of a page with their IDs
fn pageOptions(page i64):
	out = []
	for d in options:
		if d.page == page: out.push((page * idPerPage + out.len, d.copy()))
	out

# what the game writes into a page's entries, matched to the movie's by their text
fn pageRows(p Prefs, page i64):
	rows = []
	for (id, d) in pageOptions(page):
		rows.push(avm1.Row(members = [
			avm1.Member("text", .Str(d.text.copy())),
			avm1.Member("ID", .Num(f64(id))),
			avm1.Member("value", .Num(d.menuValue(p.settings.iniText(d.setting)))),
			avm1.Member("defaultVal", .Num(d.menuValue(skyrim.iniDefault(d.setting))))
		]))
	rows

# The answers to the three pages' requests, given the settings as they stand: each page's list
# (its first argument) gets its entries' IDs, values and defaults.
pub fn answerOptionPages(mut pl avm1.Player, p Prefs):
	for (call, page) in [("RequestGameplayOptions", pageGameplay),
		("RequestDisplayOptions", pageDisplay), ("RequestAudioOptions", pageAudio)]:
		pl.m.replies[call.copy()] = [.Merge(0, "text", p.pageRows(page))]

fn floatArg(c avm1.ExternalCall, k i64):
	if k >= c.args.len: return 0.0
	match c.args[k]:
		Num(x): x
		_: 0.0

# Applies what the settings pages ask of the game: OptionChange(ID, value) sets the setting, and
# SaveSettings writes the chosen ones; whether the call was one of these.
pub fn answerOptionCall(mut p Prefs, mut pl avm1.Player, c avm1.ExternalCall) bool:
	if c.name == "SaveSettings":
		p.saveChanged()
		return true
	if c.name != "OptionChange": return false
	id = i64(c.floatArg(1))
	for (at, d) in pageOptions(id / idPerPage):
		if at != id: continue
		p.settings.values[d.setting.lower()] = d.settingText(c.floatArg(2))
		if d.setting not in p.changed: p.changed.push(d.setting.copy())
		p.revision += 1
	pl.answerOptionPages(p)
	true

# The chosen settings written into this game's SkyrimPrefs.ini; none without a folder.
pub fn saveChanged(mut p Prefs):
	if p.changed.isEmpty or p.folder.isEmpty: return
	changes = p.changed.map((.copy(), p.settings.iniText(it)))
	match skyrim.writePrefs(p.folder, changes):
		error: eprint("settings not saved: {error}")
		_: p.changed.clear()
