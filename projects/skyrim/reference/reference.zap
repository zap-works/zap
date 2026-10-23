# The game's own pictures against ours (README.md, "The game's own pictures", says how the game's
# are taken): the captures of assets/reference/ and of assets/reference/menus/ (menus.json naming
# each menu's capture, the command that draws ours and the rectangles compared), measured by the
# mean difference of red, green and blue (0..255) and the share of pixels within 8 of the game's
# over the compared part of the frame: the regions given (the whole frame without any), less the
# masked rectangles. Written under reference/out/ are ours, the two side by side (-side.png) and
# where they differ (-diff.png).

import fs
import image
import json

pub referenceDir = "projects/skyrim/assets/reference"
# the poses the captures were taken from and the state each pinned (camera, light dimmers, TAA
# jitter): our own numbers, versioned, beside the pictures the git ignores
pub posesFile = "projects/skyrim/reference/poses.json"
pub outDir = "{referenceDir}/out"
tolerance = 8

# a menu's capture and how ours is drawn
pub type MenuShot:
	name str
	command str   # the program under projects/skyrim and its arguments, --shot added
	regions f64[]   # the rectangles compared, none for the whole frame
	masks f64[]

# what a comparison measured
pub type Measure:
	mean Vec3
	within f32   # percent

pub fn readDoc(path str) json.Doc:
	text = fs.readFile(path) ??
		fail("no {path}: README.md, the game's own pictures, says how they are taken")
	json.parse(text) ?? fail("{path}: {error}")

pub fn menusIn(path str) MenuShot[]:
	doc = readDoc(path)
	list = doc.get(doc.root, "menus") ?? fail("{path} has no menus")
	out = []
	for k in 0..doc.count(list):
		m = doc.at(list, k)
		out.push(MenuShot(name = doc.textOf(m, "name"), command = doc.textOf(m, "command"),
			regions = doc.numbers(m, "regions") ?? [], masks = doc.numbers(m, "mask") ?? []))
	out

pub fn run(line str):
	if Process.run(line) != 0: fail("failed: {line}")

# the rectangles' (four numbers each: x, y, width, height) pixels painted black; how many there are
pub fn mask(mut img image.Image, masks f64[]) i64:
	covered = 0
	for k in 0..masks.len / 4:
		at = k * 4
		w, h = i64(masks[at + 2]), i64(masks[at + 3])
		img.fillRect(i64(masks[at]), i64(masks[at + 1]), w, h, image.Rgba8(0, 0, 0, 255))
		covered += w * h
	covered

# the image with only the regions' pixels kept, the rest black; how many it kept
fn keepOnly(img image.Image, regions f64[]):
	out = image.Image(img.width, img.height, fill = image.Rgba8(0, 0, 0, 255))
	kept = 0
	for k in 0..regions.len / 4:
		x, y = i64(regions[k * 4]), i64(regions[k * 4 + 1])
		w, h = i64(regions[k * 4 + 2]), i64(regions[k * 4 + 3])
		out.paste(img.crop(x, y, w, h), x, y)
		kept += w * h
	(out, kept)

fn save(img image.Image, path str):
	img.savePng(path) ?? fail("cannot write {path}")

# The game's picture and ours compared over the regions (the whole frame without any) less the
# masks, the numbers printed under `name`, the side-by-side and difference pictures written at
# `out` with -side.png and -diff.png.
pub fn measure(
	name str,
	gamePath str,
	oursPath str,
	regions f64[],
	masks f64[],
	out str
) Measure:
	game = image.loadPng(gamePath)
	ours = image.loadPng(oursPath)
	total = game.width.max(ours.width) * game.height.max(ours.height)
	kept = total
	if not regions.isEmpty:
		game, kept = game.keepOnly(regions)
		ours, _ = ours.keepOnly(regions)
	kept -= game.mask(masks)
	ours.mask(masks)
	d = game.compare(ours, tolerance)
	share = f32(kept.max(1))
	mean = d.mean * (f32(total) / share)
	within = 100.0 * (1.0 - f32(d.pixels) / share)
	print("{name:<16} mean difference r {mean.x:>5.1} g {mean.y:>5.1} b {mean.z:>5.1}   within {tolerance}: {within:>5.1}%")
	image.loadPng(gamePath).sideBySide(image.loadPng(oursPath)).save("{out}-side.png")
	game.diff(ours, tolerance).save("{out}-diff.png")
	Measure(mean = Vec3(mean.x, mean.y, mean.z), within)

# the menu drawn by its command, then measured against the game's capture of it
pub fn compareMenu(m MenuShot) Measure:
	fs.createDir("{outDir}/menus") ?? fail("cannot make {outDir}/menus")
	ourPath = "{outDir}/menus/{m.name}.png"
	run("{zapPath()} run projects/skyrim/{m.command} --shot {ourPath}")
	measure(m.name, "{referenceDir}/menus/{m.name}.png", ourPath, m.regions, m.masks,
		"{outDir}/menus/{m.name}")
