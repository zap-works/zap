# The buttons a route holds instead of a player (`--route path`): lines "frame buttons", the
# buttons held from that frame on ("120 start", "300 right,b", "400 none"), as tools/oracle.lua
# plays them in Mesen 2.

# the buttons' names by their bit, from bit 4 (R) to bit 15 (B)
import fs

buttonNames = ["r", "l", "x", "a", "right", "left", "down", "up", "start", "select", "y", "b"]

type RouteStep:
	frame i64
	held u16

mut route RouteStep[] = []

fn loadRoute(path str):
	text = fs.readFile(path) ?? fail("cannot read the route {path}: {error}")
	out = []
	for row in text.lines():
		words = row.trimmed().split(" ").filter(not .isEmpty)
		if words.len < 2: continue
		frame = i64.parse(words[0]) ?? continue
		held = 0
		for name in words[1].split(","):
			if name == "none": continue
			k = buttonNames.indexOf(name) ?? fail("{path}: no button '{name}'")
			held |= u16(1) << u16(k + 4)
		out.push(RouteStep(frame, held))
	out.sortBy(.frame)
	out

mut routeNext = 0   # the route's steps are in order (loadRoute sorts them): the next one not taken

# the buttons held at the frame's end: the route's step for it, else those held before
fn routeButtons(frame i64, before u16):
	held = before
	while routeNext < route.len and route[routeNext].frame <= frame:
		if route[routeNext].frame == frame: held = route[routeNext].held
		routeNext += 1
	held

# `--polls path`: lines "n buttons" keyed by the frames that read the joypads (tools/bk2Route.zap
# writes them from a movie), the buttons held from the game's n-th such frame on; a frame that
# reads none (a lag frame) takes none, as tools/oracle.lua's SNESRECOMP_POLLS gives them in Mesen 2.
# The build plays such a movie by itself, so it runs beside Mesen rather than after it.
mut polls RouteStep[] = []
mut pollStep = 0
mut pollReads = 0
mut joypadsRead = false   # this frame read 4016-4017 or 4218-421F

fn noteJoypadRead():
	joypadsRead = true

fn routeFields(mut f StateFile):
	routeNext = f.int(routeNext)
	pollStep = f.int(pollStep)
	pollReads = f.int(pollReads)
	joypadsRead = f.isSet(joypadsRead)

# the buttons held at the frame's end: the step of the joypad-reading frames counted so far
fn pollButtons(before u16):
	if joypadsRead: pollReads += 1
	joypadsRead = false
	held = before
	while pollStep < polls.len and polls[pollStep].frame <= pollReads:
		held = polls[pollStep].held
		pollStep += 1
	held
