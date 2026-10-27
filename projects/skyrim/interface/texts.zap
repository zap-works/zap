# What the menus say that the game takes from its plugin rather than from the movies: the string
# game settings (sAllItems, sWeapons, sTake...), the records' names (FULL) and the magic effects'
# descriptions (MGEF DNAM, in the .STRINGS table or the .DLSTRINGS one, its "<mag>" and "<dur>"
# the effect's magnitude and duration), read from Skyrim.esm and its strings tables.

import skyrim
import skyrim.esm
import game.sim

# the game settings naming the days of the week from Sundas and the months from Morning Star
weekdaySettings = ["sDaySunday", "sDayMonday", "sDayTuesday", "sDayWednesday", "sDayThursday",
	"sDayFriday", "sDaySaturday"]
monthSettings = ["sMonthJanuary", "sMonthFebruary", "sMonthMarch", "sMonthApril", "sMonthMay",
	"sMonthJune", "sMonthJuly", "sMonthAugust", "sMonthSeptember", "sMonthOctober",
	"sMonthNovember", "sMonthDecember"]

pub type GameTexts:
	plugin esm.Esm
	names skyrim.Strings   # .STRINGS: names and settings
	descriptions skyrim.Strings   # .DLSTRINGS: descriptions
	settings {str: f64}   # the game settings by lower-case editor id, a string's its id

# the texts of the install's Skyrim.esm, or why they cannot be read
pub fn openTexts(install skyrim.Install, settings {str: f64}) GameTexts ? str:
	plugin = try esm.openEsm(install.installPlugin("Skyrim.esm"))
	names = try install.readNames("Skyrim.esm")
	descriptions = try install.readDescriptions("Skyrim.esm")
	GameTexts(plugin, names, descriptions, settings = settings.copy())

# a string setting's text by its editor id ("sAllItems"), "" when the plugin has none
pub fn setting(t GameTexts, key str) str:
	id = t.settings.get(key.lower()) ?? return ""
	(t.names.texts.get(i64(id)) ?? "").copy()

# A message (MESG) as Message.Show gives it: its text (DESC, in the .DLSTRINGS), its buttons (each
# ITXT, in the .STRINGS) and whether it is a box (DNAM flag 0x1) or a notice at the HUD's corner.
pub fn messageOf(mut t GameTexts, formId i64) (str, str[], bool):
	r = t.plugin.recordOf(formId) ?? return ("", [], false)
	text = t.descriptions.localText(r, "DESC")
	buttons = []
	for f in r.fields:
		if f.tag == "ITXT": buttons.push((t.names.texts.get(i64(r.body.u32le(f.at))) ?? "").copy())
	flags = r.body.u32le(esm.dataOf(r.fields, "DNAM") ?? return (text, buttons, false))
	(text, buttons, (flags & 1) != 0)

# a record's name (FULL), "" without one
pub fn nameOf(mut t GameTexts, formId i64) str:
	r = t.plugin.recordOf(formId) ?? return ""
	t.names.localText(r, "FULL")

# a skill's name (its AVIF record's FULL), "" when the plugin has none
pub fn skillName(mut t GameTexts, skill str) str:
	for id in t.plugin.formsOfKind("AVIF"):
		r = t.plugin.recordOf(id) ?? continue
		if sim.skillOfEditorId(esm.textOf(r.body, r.fields, "EDID")) == skill:
			return t.names.localText(r, "FULL")
	""

# an effect as the item card says it: its magic effect's description with the magnitude and the
# duration put in
pub fn effectText(mut t GameTexts, e sim.Effect) str:
	r = t.plugin.recordOf(e.effect) ?? return ""
	text = t.descriptions.localText(r, "DNAM")
	if text.isEmpty: text = t.names.localText(r, "DNAM")
	text.replace("<mag>", "{i64(e.magnitude.round())}").replace("<dur>", "{e.duration}")

# an item's effects as the item card lists them, one sentence after the other
pub fn effectsText(mut t GameTexts, item sim.Item) str:
	item.effects().map(t.effectText(it)).filter(not .isEmpty).join(" ")

# the suffix of a day of the month: 1st, 2nd, 3rd, 4th... 11th, 12th, 13th, 21st
fn ordinalSuffix(t GameTexts, day i64):
	if day % 100 >= 11 and day % 100 <= 13: return t.setting("sDefaultOrdSuffix")
	match day % 10:
		1: t.setting("sFirstOrdSuffix")
		2: t.setting("sSecondOrdSuffix")
		3: t.setting("sThirdOrdSuffix")
		_: t.setting("sDefaultOrdSuffix")

# A date as the menus write it, "Sundas, 9:08 AM, 17th of Last Seed", with the era and year after
# it when `year` ("..., 4E 201").
pub fn dateText(t GameTexts, d sim.Date, year bool) str:
	hour = (d.hour + 11) % 12 + 1
	noon = t.setting("sTimePM" if d.hour >= 12 else "sTimeAM")
	day = "{d.day}{t.ordinalSuffix(d.day)}"
	text = "{t.setting(weekdaySettings[d.weekday])}, {hour}:{d.minute:02} {noon}, {day} of {t.setting(monthSettings[d.month])}"
	if year: return "{text}, 4E {d.year}"
	text

# What the crosshair's target says, as the game gives it to the HUD: what activating does over
# what it is (an item's count after it), the verb red when it is a theft, an item's weight and
# value; none for nothing.
pub fn targetText(mut t GameTexts, w sim.GameWorld, refId i64) HudTarget?:
	f = try w.forms.get(refId)
	mine = w.canTake(w.player, w.ownerOf(f))
	if w.items.get(f.base) is item:
		count = " ({f.count})" if f.count > 1 else ""
		verb = t.setting("sTake" if mine else "sSteal")
		return HudTarget(text = "{verb}\n{item.name}{count}", weight = f64(item.weight),
			value = item.value)
	name = t.nameOf(f.base)
	match f.baseKind:
		"CONT": HudTarget(text = "{t.setting("sSearch" if mine else "sStealFrom")}\n{name}")
		"DOOR":
			door = f.teleport ?? return HudTarget(text = "{t.setting("sOpen")}\n{name}")
			place = door.placeName.copy()
			HudTarget(text = "{t.setting("sOpen")}\n{place if not place.isEmpty else name}")
		"NPC_":
			verb = t.setting("sPickpocket" if w.canPickpocket(refId) else "sTalk")
			HudTarget(text = "{verb}\n{name}")
		_: HudTarget(text = "{t.setting("sActivate")}\n{name}")
