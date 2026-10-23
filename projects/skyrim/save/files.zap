# The saves on disk: the folder beside the game's own ("Skyrim Zap/Saves" next to "Skyrim Special
# Edition", so a real save is never touched), a file a save named as the game names its own
# ("Save3_<name in hex>_<location>_<time>.ess", "Quicksave0_...", "Autosave1_..."), and the list of
# them the load menu shows, the newest first.

import date
import fs
import skyrim

pub kindSave = "Save"
pub kindQuick = "Quicksave"
pub kindAuto = "Autosave"

pub type Listed:
	file str   # the file's path
	kind str   # kindSave, kindQuick or kindAuto
	header Header

# the folder the player's saves are in, none without a user's folder
pub fn savesDir() str?:
	game = try skyrim.iniDir()
	"{fs.dirOf(game)}/Skyrim Zap/Saves"

fn hexOf(text str):
	out = ""
	for b in text.bytes():
		out += "{b:02X}"
	out

fn letters(text str):
	out = []
	for c in text.bytes():
		if (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122): out.push(c)
	out.cStringAt(0, out.len)

# the file name of a save: the kind and the number, the name, the place and the time written
pub fn fileNameOf(kind str, h Header) str:
	number = 0 if kind == kindQuick else h.saveNumber
	"{kind}{number}_{hexOf(h.name)}_{letters(h.location)}_{h.filetime}.ess"

# the kind a save's file is of, by its name
fn kindOfFile(file str):
	name = fs.fileName(file)
	for kind in [kindQuick, kindAuto]:
		if name.startsWith(kind): return kind
	kindSave

# The saves of the folder, the newest first; a file that cannot be read as a save is left out.
pub fn listSaves(dir str) Listed[]:
	out = []
	for name in fs.list(dir) ?? []:
		if fs.extension(name) != ".ess": continue
		file = "{dir}/{name}"
		bytes = fs.readBytes(file) ?? continue
		match headerOf(bytes):
			h: out.push(Listed(file, kind = kindOfFile(file), header = h))
			error: pass
	out.sortedBy(-.header.saveNumber)

# the number the next save takes
pub fn nextNumber(saves Listed[]) i64:
	1 + (saves.map(.header.saveNumber).max() ?? 0)

# when a file written now is dated: a scratch file's modification time
pub fn nowFiletime(dir str) i64:
	probe = "{dir}/.stamp"
	fs.writeFile(probe, "") ?? return 0
	when = fs.modified(probe) ?? 0
	fs.deleteFile(probe) ?? return when
	when

pub fn deleteSave(e Listed) ? str:
	fs.deleteFile(e.file) ?? return "{e.file} cannot be deleted"
	return

# a file time (100 ns since 1601) as "2026-10-21 14:20" in UTC
pub fn filetimeText(filetime i64) str:
	minutes = filetime / 600_000_000
	days = minutes / 1440 - 134_774   # days since 1970-01-01
	civil = date.civilOfDay(days)
	"{civil.year}-{civil.month:02}-{civil.day:02} {minutes / 60 % 24:02}:{minutes % 60:02}"

# the row of the load menu for a save, which the page cuts at 20 letters: "Save 3", "Quicksave",
# "Autosave 1"
pub fn listText(e Listed) str:
	e.kind.copy() if e.kind == kindQuick else "{e.kind} {e.header.saveNumber}"
