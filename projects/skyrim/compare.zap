# Compares our pictures of the Sleeping Giant Inn with the game's own: the pictures SkyrimSE.exe
# took (README.md, "The game's own pictures", says how) in projects/skyrim/assets/reference/.
# Printed for each are the mean difference of red, green and blue (0..255) and the share of pixels
# within 8 of the game's, over the compared part of the frame: the regions given (the whole frame
# without any), less the masked rectangles (the fire, the 3D scene behind a menu); written under
# reference/out/ are <name>.png (ours), <name>-side.png (the game's left, ours right) and
# <name>-diff.png (image.diff at 8).
#
#   zap run projects/skyrim/compare.zap          every pose of poses.json, main.zap drawing ours
#   zap run projects/skyrim/compare.zap table    one pose, by name
#   zap run projects/skyrim/compare.zap --menus [name]   the menus of menus/menus.json, each drawn
#       by the command its entry gives (main.zap or menuinfo.zap and their arguments)
#   zap run projects/skyrim/compare.zap --pair game.png ours.png [--region x,y,w,h]... [--mask x,y,w,h]...
#       two pictures

import fs
import image
import reference

type Pose:
	name str
	at f64[]   # the player's feet: x, y, z in the game's units
	yaw f64   # Skyrim's angle z in degrees: 0 north, 90 east
	pitch f64   # Skyrim's angle x in degrees: positive looks down
	fov f64   # Skyrim's convention (game.fovY)
	eye f64   # the camera's height over the feet
	masks f64[]   # rectangles left out, x, y, width, height in pixels, four numbers each
	dimmers f64[]   # the dimmer of each cell light in the capture (0 where not read), main.zap --dimmers
	captureAt f64[]   # the capture's own feet when it stood elsewhere than `at` (the firepit's on the step), read from its draws; empty: `at`
	jitter f64   # the capture's TAA jitter, the Halton index (1..8) of its frame, main.zap --jitter-phase; 0: free
	capture str   # the RenderDoc capture's final presented frame under reference/ (no extension); empty: the pose's own PNG

fn posesIn(path str):
	doc = reference.readDoc(path)
	list = doc.get(doc.root, "poses") ?? fail("{path} has no poses")
	out = []
	for k in 0..doc.count(list):
		p = doc.at(list, k)
		number = (key str): doc.number(p, key) ?? fail("{path}: pose {k} has no {key}")
		out.push(
			Pose(
				name = doc.textOf(p, "name"),
				at = [number("x"), number("y"), number("z")],
				yaw = number("yaw"),
				pitch = number("pitch"),
				fov = number("fov"),
				eye = number("eye"),
				masks = doc.numbers(p, "mask") ?? [],
				dimmers = doc.numbers(p, "dimmers") ?? [],
				captureAt = doc.numbers(p, "captureAt") ?? [],
				jitter = doc.number(p, "jitter") ?? 0.0,
				capture = doc.textOf(p, "capture")
			)
		)
	out

# The hour of the captures: their beams take SkyrimClear's day effect lighting, which holds from
# the sunrise's end to the sunset's start (10 to 16 in SkyrimClimate).
capturedHour = 12

# our picture from the pose, drawn by main.zap into `path`
fn drawOurs(p Pose, path str, feet f64[]):
	at = "{feet[0]},{feet[1]},{feet[2]}"
	camera = "--at {at} --eye {p.eye} --look {p.yaw},{-p.pitch} --fov {p.fov}"
	pinned = " --dimmers {p.dimmers.map("{it}").join(",")}" if not p.dimmers.isEmpty else ""
	phased = " --jitter-phase {(i64(p.jitter) + 6) % 8}" if p.jitter > 0.0 else ""
	reference.run("{zapPath()} run projects/skyrim/main.zap --frames 30 --step 16 --free --bare --hour {capturedHour} {camera}{pinned}{phased} --shot {path}")

fn comparePose(p Pose):
	ourPath = "{reference.outDir}/{p.name}.png"
	hasCapture = not p.capture.isEmpty and fs.exists("{reference.referenceDir}/{p.capture}.png")
	gameName = p.capture if hasCapture else p.name
	p.drawOurs(ourPath, p.captureAt if hasCapture and not p.captureAt.isEmpty else p.at)
	reference.measure(
		p.name,
		"{reference.referenceDir}/{gameName}.png",
		ourPath,
		[],
		p.masks,
		"{reference.outDir}/{p.name}"
	)

# the rectangles the option gives, each `--option x,y,w,h` four numbers
fn rectangles(option str):
	out = []
	for k in 0..args.len - 1:
		if args[k] == option: out.extend(args[k + 1].split(",").map(f64.parse(it) ?? 0.0))
	out

fs.createDir(reference.outDir) ?? fail("cannot make {reference.outDir}")
args.options(
	[
		ArgOption("--pair", true, "the game's picture"),
		ArgOption("--region", true, "a rectangle to compare"),
		ArgOption("--mask", true, "a rectangle to leave out")
	]
)
if args.option("--pair") is gamePath:
	ours = args.positional()
	if ours.isEmpty: fail("--pair game.png ours.png")
	stem = fs.stem(ours[0])
	reference.measure(stem, gamePath, ours[0], rectangles("--region"), rectangles("--mask"),
		"{reference.outDir}/{stem}")
	return
wanted = args.positional()
if args.hasFlag("--menus"):
	menus = reference.menusIn("{reference.referenceDir}/menus/menus.json")
	for m in menus:
		if wanted.isEmpty or m.name in wanted: m.compareMenu()
	return
poses = posesIn(reference.posesFile)
mut compared = 0
for p in poses:
	if not wanted.isEmpty and wanted.indexOf(p.name) == none: continue
	p.comparePose()
	compared += 1
if compared == 0: fail("no pose named {wanted} in {reference.posesFile}")
