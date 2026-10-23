# The player's own settings of the game: Skyrim.ini and SkyrimPrefs.ini in Documents/My Games/
# Skyrim Special Edition, "key=value" lines under "[Section]" headers, each named as the executable
# names it ("bDialogueSubtitles:Interface"); one neither file sets takes the executable's default.

import fs

# The executable's defaults of the settings read here, from SkyrimSE.exe's static settings (the
# value just before the pointer to the name). The few the executable fills in at run time (its
# static value is 0) take the game's: iDifficulty 2 (Adept), fAutosaveEveryXMins 15, bGamePadRumble
# 1, bShowFloatingQuestMarkers 1, fLightLODStartFade (fLightLODDefaultStartFade's 1000).
# long: a table of settings, one a line
iniDefaults {str: str} = {
	"bdialoguesubtitles:interface": "0",   # the dialogue's lines shown as subtitles
	"bgeneralsubtitles:interface": "0",   # the other speech shown as subtitles
	"itexmipmapskip:display": "0",   # top mip levels of the textures left out (the game's texture quality: 0 ultra, 1 high...)
	"bshowcrosshair:interface": "1",
	"bshowcompass:interface": "1",
	"fhudopacity:interface": "1.0",
	"fdialoguerotationsecs:dialogue": "1.0",   # seconds the speaker takes to turn to the player
	"fdialoguesoftstopangle3p:controls": "25.0",   # degrees aside the speaker stays in a 3rd person view
	"binvertyvalues:controls": "0",
	"fmouseheadingsensitivity:controls": "0.0125",
	"fmouseheadingsensitivitymin:controls": "0.01",
	"fmouseheadingsensitivitymax:controls": "0.05",
	"bgamepadrumble:controls": "1",
	"idifficulty:gameplay": "2",
	"fautosaveeveryxmins:savegame": "15.0",
	"bshowfloatingquestmarkers:gameplay": "1",
	"bsaveonrest:savegame": "1",
	"bsaveonwait:savegame": "1",
	"bsaveontravel:savegame": "1",
	"fgamma:display": "1.0",
	"fgammamin:display": "0.6",
	"fgammamax:display": "1.4",
	"fdynamicdoffarblur:display": "0.7",
	"fshadowdistance:display": "8000.0",
	"flightlodstartfade:display": "1000.0",
	"fspecularlodmaxstartfade:display": "2000.0",
	"ftreesmidlodswitchdist:display": "3600.0",
	"fgrassstartfadedistance:grass": "7000.0",
	"fsplitdistancemult:terrainmanager": "1.5",   # a distant block splits while the eye is within this times its half diagonal
	"fblockmaximumdistance:terrainmanager": "250000.0",   # the distant blocks' last distance
	"flodlanddropamount:lod": "230.0",   # how far the distant land sinks under the loaded cells
	"ugridstoload:general": "5",   # the loaded cells' side
	"flodfadeoutmultobjects:lod": "5.0",
	"flodfadeoutmultitems:lod": "3.0",
	"flodfadeoutmultactors:lod": "6.0",
	"faudiomastervolume:audiomenu": "1.0",
	"feffectsvolume:audiomenu": "1.0",
	"ffootvolume:audiomenu": "1.0",
	"fvoicevolume:audiomenu": "1.0",
	"fmusicvolume:audiomenu": "1.0"
}

iniFiles = ["Skyrim.ini", "SkyrimPrefs.ini"]

pub type IniSettings:
	values {str: str}   # by "key:section", lower case

# the user's folder's Documents/My Games, where the game's ini files are
fn myGames() str?:
	home = fs.userDir()
	if home == "": return none
	"{home}/Documents/My Games"

# the folder of the game's ini files, none without a user's folder
pub fn iniDir() str?:
	"{try myGames()}/Skyrim Special Edition"

# The folder of this game's own files (the settings it saves, the controls the player remapped),
# beside the real game's and never inside it.
pub fn ownDir() str?:
	"{try myGames()}/Skyrim Zap"

# one setting of an ini file, as written
pub type IniEntry:
	section str
	key str
	value str

# the entries of an ini file's text, in order, names as written
pub fn parseEntries(text str) IniEntry[]:
	section = ""
	out = []
	for raw in text.lines():
		line = raw.trimmed()
		if line.startsWith("[") and line.endsWith("]"):
			section = line[1..line.len - 1].copy()
		elif line.indexOf("=") is at:
			if not line.startsWith(";"):
				out.push(IniEntry(section = section.copy(), key = line[..at].trimmed().copy(),
					value = line[at + 1..].trimmed().copy()))
	out

# the entries as an ini file's text, a section's together in order of first appearance
pub fn showEntries(entries IniEntry[]) str:
	sections str[] = []
	for e in entries:
		if e.section not in sections: sections.push(e.section.copy())
	lines = []
	for section in sections:
		lines.push("[{section}]")
		for e in entries:
			if e.section == section: lines.push("{e.key}={e.value}")
		lines.push("")
	lines.join("\n")

# the settings the ini files' text sets, by "key:section"
pub fn parseIni(text str, mut into {str: str}):
	for e in parseEntries(text):
		into["{e.key.lower()}:{e.section.lower()}"] = e.value.copy()

# The player's ini files read (none of their settings without them), then this game's own saved
# settings, which win.
pub fn readIniSettings() IniSettings:
	values {str: str} = {}
	if iniDir() is dir:
		for name in iniFiles:
			if fs.readFile("{dir}/{name}") is text: parseIni(text, values)
	if ownDir() is own:
		if fs.readFile("{own}/SkyrimPrefs.ini") is text: parseIni(text, values)
	IniSettings(values)

# Settings ("bShowCompass:Interface", text) written into the SkyrimPrefs.ini of a folder, over
# what the file held.
pub fn writePrefs(dir str, changes (str, str)[]) () ? str:
	path = "{dir}/SkyrimPrefs.ini"
	entries = parseEntries(fs.readFile(path) ?? "")
	for (name, text) in changes:
		colon = name.indexOf(":") ?? fail("the setting {name} has no section")
		key = name[..colon]
		section = name[colon + 1..]
		found = false
		for mut entry in entries:
			if entry.key.lower() == key.lower() and
				entry.section.lower() == section.lower():
				entry.value = text.copy()
				found = true
		if not found:
			entries.push(IniEntry(section = section.copy(), key = key.copy(), value = text.copy()))
	fs.createDir(dir) ?? return "cannot make {dir}"
	fs.writeFile(path, showEntries(entries)) ?? return "cannot write {path}"

# the executable's default of a setting
pub fn iniDefault(name str) str:
	(iniDefaults.get(name.lower()) ?? fail("no ini setting {name}")).copy()

# a setting's text by its name ("bDialogueSubtitles:Interface"): the files', else the executable's
pub fn iniText(s IniSettings, name str) str:
	key = name.lower()
	(s.values.get(key) ?? (iniDefaults.get(key) ?? fail("no ini setting {name}"))).copy()

pub fn iniNumber(s IniSettings, name str) f64:
	f64.parse(s.iniText(name)) ?? 0.0

pub fn isSettingOn(s IniSettings, name str) bool:
	s.iniNumber(name) != 0.0
