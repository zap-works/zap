# Skyrim: an interior of Skyrim Special Edition played on Zap's engine from the player's own
# install (its Skyrim.esm and BSA archives: the cell, its references, their models and textures,
# the player's body and clips), nothing of the game in the repository. `zap run
# projects/skyrim/prepare.zap` reads the install once and writes the cell, the player and the
# cell's physics ready to use into projects/skyrim/assets/prepared/; the game reads only that, and
# opens at once inside the Sleeping Giant Inn, the player standing inside its door seen from
# behind, as the game's third person shows him (it prepares first, once, when the prepared files
# are missing or of an older format).
#
#   zap run projects/skyrim/main.zap        WASD walks the player the way the camera looks, Shift
#                                       runs, the mouse turns the camera (after a click; Esc lets
#                                       it go) or a right drag does, Esc leaves
#   needs: projects/skyrim/assets/prepared (made by prepare.zap from the install, or from
#          projects/skyrim/assets/game, which extract.zap fills from it, when the install is missing)
#   zap run projects/skyrim/main.zap --frames 120 --step 16 --shot skyrim.png
#   zap run projects/skyrim/main.zap --frames 44 --step 16 --replay "10:down w" --shot skyrim-walk.png
#   zap run projects/skyrim/main.zap --frames 150 --step 16 --replay "10:down w;50:down shift;90:down d;100:up d;110:drag 400 0" --shot skyrim-run.png
#   zap run projects/skyrim/main.zap --frames 200 --step 16 --replay "10:down a" --shot skyrim-wall.png
#       (the keys and the mouse replayed from a script instead of read, game/input.zap: walk a
#       few steps; run, turn right and look around; walk left into the corner by the door)
#   zap run projects/skyrim/main.zap --frames 260 --step 16 --replay "5:drag -168 0;10:down w;10:down shift;200:up w;200:up shift;210:drag -260 0" --shot skyrim-bar.png
#       (run to the bar and look at Orgnar behind it, who turns his head to the player)
#   zap run projects/skyrim/main.zap --hour 19 --free --at 51,-200,0 --eye 100 --look 0,-10 --frames 30 --step 16 --shot skyrim-evening.png
#       (at 19 of the first day: Embry in his chair, Camilla at the table behind)
#   zap run projects/skyrim/main.zap --free --frames 60 --step 16 --shot skyrim-free.png
#       (the free camera: WASD moves it, the mouse looks, Shift is faster, E and Q rise and sink)
#   zap run projects/skyrim/main.zap --free --at -100,-300,120 --look 300,-10
#       (the free camera standing at x, y, z in the game's units, Z up; looking toward a heading
#       in degrees, 0 north and 90 east, tilted up by a pitch in degrees)
#   zap run projects/skyrim/main.zap --install D:/Skyrim/Data --cell WhiterunBanneredMare
#       (prepare from another install, open another interior by its editor id)
#   zap run projects/skyrim/main.zap --free --at 8,-170,0 --eye 120 --fov 65 --bare
#       (the eye that high over --at's z, as the game's first person camera over the player's
#       feet; the view FOV wide in the game's convention, see fovY; only the cell, no label and
#       no actor, as the reference captures show it)
#   zap run projects/skyrim/main.zap --dimmers 0.78,0,0,0.89   (the dimmer each cell light takes in place
#       of its flicker's, in the cell's order, 0 leaving one free: the state of a capture, compare.zap)
#   zap run projects/skyrim/main.zap --jitter-phase 2   (the TAA jitter's sequence 2 frames ahead, so the last of
#       --frames 30 lands on a capture's index: compare.zap)
#   zap run projects/skyrim/main.zap --frames 600 --frametimes   (the frames' cost summed up at the end)
#   zap run projects/skyrim/main.zap --ids ... --shot ids.png   (each pixel its part's texture index, red low byte
#       green high byte; prepare.zap writes the names beside the cell as textures.txt: diagnostics, see errorby.py)
#   zap run projects/skyrim/main.zap --d3d12      (Direct3D 12 instead of Vulkan, as ZAP_RUN=gpu=d3d12)
#   zap run projects/skyrim/main.zap --frames 60 --step 16 --replay "30:down i;45:down right" --shot inv.png
#       (the HUD and the game's menus from the install, interface/screen.zap: I the inventory,
#       Tab the tween menu, Esc the journal, T the wait menu, E what the crosshair is on; a menu
#       takes the keys while it is open; --bare leaves the interface out, unless --menus; --hour 9.5
#       sets the game's clock, --message "text;button" shows a message box)
#   zap run projects/skyrim/main.zap --music-trace   (the music printed as it starts and stops;
#       the inn sounds as the game's: game/sound)
#   zap run projects/skyrim/main.zap --hour 19    (the game's clock at 19 of the first day, not 8)
#   zap run projects/skyrim/main.zap --subtitles --frames 300 --step 16 --replay "5:drag -168 0;10:down w;10:down shift;200:up w;200:up shift;210:drag -260 0;230:down e;560:down down;570:down down;610:down enter" --shot skyrim-greeting.png
#   zap run projects/skyrim/main.zap --subtitles --frames 735 --step 16 --replay "5:drag -168 0;10:down w;10:down shift;200:up w;200:up shift;210:drag -260 0;230:down e;560:down down;570:down down;610:down enter" --shot skyrim-rumor.png
#   zap run projects/skyrim/main.zap --subtitles --frames 1110 --step 16 --replay "5:drag -168 0;10:down w;10:down shift;200:up w;200:up shift;210:drag -260 0;230:down e;560:down down;570:down down;610:down enter" --shot skyrim-topics.png
#       (run to the bar and talk to Orgnar, game/talk.zap and interface/dialogueFeed.zap: his
#       greeting said beside his topics; the rumors topic chosen by the arrows and Enter, his answer;
#       the topics after it once the answer's voice file ends; Tab leaves. --subtitles shows the
#       lines' texts as the ini's bDialogueSubtitles does)
#   zap run projects/skyrim/main.zap --frames 900 --step 16 --replay "5:drag -168 0;10:down w;10:down shift;200:up w;200:up shift;210:drag -260 0;230:down e;560:down down;610:down enter;880:down enter" --shot skyrim-barter.png
#   zap run projects/skyrim/main.zap --frames 960 --step 16 --replay "5:drag -168 0;10:down w;10:down shift;200:up w;200:up shift;210:drag -260 0;230:down e;560:down down;610:down enter;880:down enter;930:down enter" --shot skyrim-bought.png
#       (the goods topic chosen: once Orgnar has answered, bartermenu.swf opens fed from the game,
#       game/sim/barter.zap: his chest's stock under his name, the player's items after it, the
#       gold of both; Enter on a stack asks how many, Enter again buys them at the formula's price)
#   zap run projects/skyrim/main.zap --free --at -1390,-40,0 --eye 190 --look 90,-40 --kill 20:Orgnar --frames 75 --step 16 --shot skyrim-falling.png
#   zap run projects/skyrim/main.zap --free --at -1390,-40,0 --eye 190 --look 90,-40 --kill 20:Orgnar --frames 260 --step 16 --shot skyrim-fallen.png
#       (Orgnar killed at frame 20, as the combat flags a death, falls as his skeleton's ragdoll:
#       slumping over his counter, then lying on the floor behind it)
#   zap run projects/skyrim/main.zap --stand -1290,-20,100 --frames 60 --step 16 --replay "10:down r" --shot skyrim-fists.png
#   zap run projects/skyrim/main.zap --stand -1290,-20,100 --frames 112 --step 16 --replay "10:down r;80:down lmb;83:up lmb" --shot skyrim-punch.png
#   zap run projects/skyrim/main.zap --stand -1290,-20,100 --frames 240 --step 16 --replay "10:down r;80:down lmb;83:up lmb;130:down lmb;133:up lmb" --shot skyrim-fight.png
#       (--stand puts the player at x, y facing a heading in degrees, here behind the bar beside
#       Orgnar: R draws his fists; a click throws a punch, whose hit shows the enemy meter at the
#       top and is an assault, so Orgnar fights back with his mace)
#   zap run projects/skyrim/main.zap --free --stand -1290,-20,100 --at -1130,-33,0 --eye 128 --look -90,0 --frames 100 --step 16 --shot skyrim-lips-open.png
#   zap run projects/skyrim/main.zap --free --stand -1290,-20,100 --at -1130,-33,0 --eye 128 --look -90,0 --frames 400 --step 16 --shot skyrim-lips-closed.png
#       (Orgnar greets the player standing beside him and faces the camera across the counter: his
#       mouth follows the lip track of his hello, open in its words, shut once it is said; his
#       eyes blink every few seconds)
#   zap run projects/skyrim/main.zap --stand -1134,150,0 --frames 115 --step 16 --replay "10:down tab;40:down left;60:down enter;100:down left;110:down down" --shot skyrim-magic-menu.png
#   zap run projects/skyrim/main.zap --free --stand -1134,150,0 --at -1000,-60,0 --eye 150 --look -32,-3 --frames 240 --step 16 --replay "10:down tab;40:down left;60:down enter;100:down left;110:down down;120:down enter;140:down tab;190:down r;200:down lmb;260:up lmb" --shot skyrim-magic-cast.png
#       (Tab opens the tween menu, Left highlights Magic and Enter opens magicmenu.swf, fed from the
#       model (interface/spellMenu.zap): the spells the player knows by school, Flames' card with
#       its cost a second; Left reaches the list, Down the spell, Enter puts it in the right hand,
#       a right click in the left. Tab leaves, R raises the hands and the left button holds the
#       spell: Flames' stream over the fists' stance's arm costs 14 magicka a second and burns what
#       it meets (game/combat/magic.zap; the fire is the projectile's model, the light the
#       hand's, both prepared with the cell: game/spellArt.zap). Q opens the favorites menu, F
#       marks the spell or the item in the lists a favorite)
#   zap run projects/skyrim/main.zap --frames 160 --step 16 --use 30:13419 --shot skyrim-out.png
#       (the front door, reference 13419, used at frame 30: the screen fades, the game opens
#       Riverwood's exterior, the loaded grid of uGridsToLoad cells round the cell outside the
#       door (esm/area.zap), prepared first when missing, and the player stands where the door's
#       XTEL puts him; the door beside him, 13424, leads back. Pressing E on a load door does the
#       same. The grid is made again round the player's cell once he goes past its middle ring.
#       The land of the grid is drawn with the cell and walked on, game/land.zap)
#   zap run projects/skyrim/main.zap --cell exterior_60_5_-11 --free --at 23259,-44476,-8 --eye 128 --look -48,-5 --shot skyrim-town.png
#       (an exterior area opened by its id, exterior_<world's form id>_<x>_<y> of its centre cell)
#   R draws or sheathes the weapon (fists without one), the left button attacks (held, a power
#   attack), the right one blocks (game/fightScene.zap); the HUD shows while it is out
#   Ctrl starts and stops sneaking (game/stealth): the player walks at the sneak clips' speeds, the
#   HUD's eye opens over the crosshair and shows whether anyone has detected him (they read him
#   as the executable does: light, noise, view cone, line of sight, Sneak skills); E on an actor
#   then opens its pockets (interface/items.zap), each item with the chance of taking it

import engine
import engine.audio
import engine.physics
import game
import game.dialogue
import game.sim
import game.stealth
import interface
import game.sound
import math
import papyrus
import save
import skyrim
import skyrim.esm
import world

# the prepared cell, prepared first when it is missing or of an older format
fn openCell(dir str, id str):
	match game.openPrepared(id):
		found: found
		none:
			print("Skyrim prepares {id} from {dir} (once; zap run projects/skyrim/prepare.zap does it ahead)...")
			game.prepareCell(dir, id)
			game.openPrepared(id) ?? fail("the prepared cell cannot be read back")

# the camera at `eye` turned to look at `focus` (y up)
fn lookingAt(eye Vec3, focus Vec3):
	d = (focus - eye).normalized()
	engine.FlyCamera(
		eye,
		yaw = d.x.atan2(-d.z),
		pitch = d.y.asin(),
		speed = 200.0,
		fastFactor = 3.0,
		lookSpeed = 0.004
	)

# the interface from the install, none without it (the game runs on without menus); the dialogue's
# lines shown as subtitles when the ini's bDialogueSubtitles is on, or --subtitles asks
fn openScreen(dir str, settings {str: f64}, win engine.Window) interface.Screen?:
	subtitles = args.hasFlag("--subtitles") or
		skyrim.readIniSettings().isSettingOn("bDialogueSubtitles:Interface")
	match interface.openScreen(dir, settings, subtitles, win.width, win.height):
		s: s
		error:
			eprint("no interface: {error}")
			none

# the camera's view in the game's units (z up): its eye and the direction it looks along
fn viewInGame(eye Vec3, yaw f32, pitch f32):
	at = game.yUp.inverseAffine().applyPoint(eye)
	(at, Vec3(yaw.sin() * pitch.cos(), yaw.cos() * pitch.cos(), pitch.sin()))

fn cellTalkOf(dir str, id str) dialogue.Talk ? str:
	install = try skyrim.openInstall(dir)
	plugin = try esm.openEsm(install.installPlugin("Skyrim.esm"))
	dialogue.talkInCell(install, plugin, id)

# The game's model of the cell: its world as a new game has it, the Papyrus VM over it (its
# scripts bound and their OnInit run) and the dialogue, its clock at the hour of the first day (a
# new game's 8 when --hour is not given).
fn openTalk(dir str, id str, hour f32):
	t = cellTalkOf(dir, id) ?? fail("the game's model of {id} cannot be read: {error}")
	t.vm.rt.world.daysPassed = f64(hour) / 24.0
	t

# where the camera starts: --at and --look as given, else back from the focus along the hall
fn startCamera(head world.CellHead):
	at = args.optionNumbers("--at").map(f32(it))
	look = args.optionNumbers("--look").map(f32(it))
	given = at.len == 3
	raised = Vec3(0.0, 0.0, f32(args.optionNumbers("--eye").first ?? 0.0))
	eye = game.yUp.applyPoint(Vec3(at) + raised) if given
		else head.focus + Vec3(520.0, 140.0, 170.0)
	camera = eye.lookingAt(head.focus)
	if look.len == 2:
		camera.yaw = look[0] * pi / 180.0
		camera.pitch = look[1] * pi / 180.0
	camera

lookEvery = 0.25   # seconds between the watchers' looks (each reading is kept 1 s)
fadeSeconds = 0.4   # the screen's fade to black and back through a load door
dir = args.option("--install") ?? skyrim.defaultInstall
mut id = args.option("--cell") ?? game.defaultCell
mut arrival game.Arrival? = none   # where the player enters the next cell, none for its own start
mut previous sim.GameWorld? = none   # the world the player came from
mut visited {str: game.Left} = {}   # the cells the player left, by id
mut frames = engine.newFrames()
mut win = engine.openWindow("Skyrim", 1280, 960)
mut r = engine.newRenderer()
font = engine.loadFont("Segoe UI", 16)
mut ui interface.Screen? = none
mut fade f32 = 0.0   # the black laid over the screen, 0 clear to 1 black
mut quitting = false
audio.start()
while not quitting:
	started = clockSeconds()
	cell = openCell(dir, id)
	head = cell.head
	scene = head.newCellScene(cell.file)
	scene.debugIds = args.hasFlag("--ids")
	scene.pinnedDimmers = args.optionNumbers("--dimmers").map(f32(it))
	scene.picture.jitterPhase = i64(args.optionNumbers("--jitter-phase").first ?? 0.0)
	actors = head.cast.newActorScene(cell.file, scene)
	cell.file.file = []   # what the GPU holds is not kept in memory too (the body is most of the file)
	gaits = game.gaitsOf(actors.motions[0].clips, actors.speeds[0])
	stand = args.optionNumbers("--stand").map(f32(it))   # x, y and a heading in degrees
	startFeet = Vec3(stand[0], stand[1], 0.0) if stand.len == 3 else head.cast.start
	startHeading = stand[2].radians() if stand.len == 3 else head.cast.heading
	if arrival is through:
		startFeet = through.feet
		startHeading = through.heading
	player = startFeet.newPlayer(startHeading, gaits)
	hour = f32(args.optionNumbers("--hour").first ?? 8.0)
	talk = openTalk(dir, id, hour if previous == none else 0.0)
	if visited.get(id) is left: talk.vm.rt.world.returning(left)
	if previous is carried: carried.carryOver(talk.vm.rt.world)
	skyClock game.SkyClock? = none
	if esm.areaOf(id) is area:
		install = skyrim.openInstall(dir) ?? fail
		scene.showTerrain(install.terrainOfArea(talk.plugin, area))
		skyClock = talk.plugin.openSkyClock(area.world, (f32(area.x) + 0.5) * esm.cellSize,
			(f32(area.y) + 0.5) * esm.cellSize, game.hourOf(talk.vm.rt.world.daysPassed), 1)
		if skyClock is clock: scene.showSky(install.newSkyDrawing(clock))
	residents = head.cast.newResidents(actors.motions, actors.speeds,
		game.hourOf(talk.vm.rt.world.daysPassed), game.Load(dir.copy()))
	walker = residents.graph.newWalker(true)
	savesDir = save.savesDir() ?? "saves"
	iniSettings = skyrim.readIniSettings()
	follow = game.newFollow(player.heading)
	soundScene sound.Scene? = none   # none without the install
	match sound.openScene(dir, id, head.cast, residents.clipNames, cell.physics,
		game.hourOf(talk.vm.rt.world.daysPassed), esm.areaOf(id) == none):
		opened: soundScene = opened
		error: print("no sound: {error}")
	musicTrace = args.hasFlag("--music-trace")
	residents.syncDoors(head.cast, talk.vm.rt.world, cell.physics.world)
	waitedBefore = false   # the player was waiting or sleeping the frame before
	waitStart = 0.0   # the game days when the wait or sleep began
	fight = game.openFightScene(dir, id, residents.graph, residents.lengths[0])   # none without the install
	session = save.startSession(savesDir, talk, residents, head.cast, player, fight, walker,
		cell.physics.world)
	input = game.newInputSource()
	free = args.hasFlag("--free")
	print("Skyrim: {head.cell}, {head.refs} references, {head.models} models, {head.parts} parts, {head.textures.len} textures, {head.lights.len} lights, {talk.vm.rt.objects.len - 1} script objects, {residents.all.count(.present)} of {residents.all.len} actors in, ready in {(clockSeconds() - started):.2} s")
	camera = head.startCamera()
	fovY = game.fovY(f32(args.optionNumbers("--fov").first ?? f64(game.defaultFov)))
	bare = args.hasFlag("--bare")
	kill = game.killOrderOf(args.option("--kill") ?? "")
	if ui == none and (not bare or args.hasFlag("--menus")):
		ui = openScreen(dir, talk.vm.rt.world.settings, win)
	talkingTo = -1   # the resident in dialogue with the player
	if ui is mut s:
		s.setSaves(save.listSaves(savesDir))
		if args.option("--message") is message and visited.isEmpty:
			parts = message.split(";")
			s.showMessage(parts[0], parts[1..])
	fpsShown = 0
	going game.Arrival? = none   # the load door the player went through, the cell it leads to
	useAt, useDoor = game.useOrderOf(args.option("--use") ?? "")
	faceClock = 0.0   # the blinks' time
	lighting = game.detectionLighting(head.lights, head.light)   # the light on the actors, for detection
	sinceLook = 0.0   # seconds since the watchers last read the player
	appliedChoices = -1   # the settings pages' choices applied to the game (all at the first frame)
	while win.nextFrame(frames, escEnds = false):
		if engine.isKeyPressed(.Escape) and engine.isMouseCaptured():
			win.captureMouse(false)
		elif engine.isKeyPressed(.Escape) and ui == none:
			quitting = true
			break
		menuOpen = ui?.isMenuOpen() ?? false
		keys = game.PlayerKeys()
		if ui is shown: keys = shown.prefs.controls.playerKeys()
		i = input.readInput(frames.count, win, fight?.drawn ?? false, menuOpen, keys)
		if i.sneak and not menuOpen and not free: talk.vm.rt.world.toggleSneak()
		sneaking = talk.vm.rt.world.stealth.sneaking
		if sneaking != player.sneaking:
			player.sneaking = sneaking
			walker.animator.setVariable("iIsInSneak", 1.0 if sneaking else 0.0)
			walker.animator.sendEvent("SneakStart" if sneaking else "SneakStop")
		if menuOpen:
			pass
		elif free:
			camera.steer(frames.dt, i.look)
		else:
			follow.turnFollow(i.look)
			player.steerPlayer(i, follow.headingOf(), cell.physics.world, frames.dt)
			follow.followFeet(player.feetOf(), cell.physics.world.scene)
		walker.stepWalker(
			residents.graph,
			residents.lengths[0],
			player.feetOf(),
			player.heading,
			true,
			frames.dt
		)
		talk.vm.tick(f64(frames.dt))
		talk.vm.rt.world.learnPending(talk.plugin, talk.names)
		faceClock += f64(frames.dt)
		talked = 0
		if ui is shown: talked = shown.talkingTo() ?? 0
		speaker = residents.residentOf(head.cast, talk.vm.rt.world, talked)
		if speaker != talkingTo:
			residents.holdForTalk(talkingTo, false, player.feetOf(), iniSettings)
			residents.holdForTalk(speaker, true, player.feetOf(), iniSettings)
			talkingTo = speaker
		if talkingTo >= 0 and not free:
			follow.frameSpeaker(residents.headOf(head.cast, talkingTo), iniSettings, frames.dt)
		scene.setTime(world.capturedWeather, game.hourOf(talk.vm.rt.world.daysPassed))
		if skyClock is mut clock:
			hourNow = game.hourOf(talk.vm.rt.world.daysPassed)
			clock.advance(hourNow)
			sky = clock.skyAt(hourNow, 0.0)
			scene.setSky(sky, clock.imageSpaceAt(sky), f32(talk.vm.rt.world.daysPassed))
		waiting = talk.vm.rt.world.sleepWait != none
		if waiting and not waitedBefore: waitStart = talk.vm.rt.world.daysPassed
		if waitedBefore and not waiting:
			residents.skipTime(head.cast, game.hourOf(talk.vm.rt.world.daysPassed),
				(talk.vm.rt.world.daysPassed - waitStart) * 86400.0,
				f64(talk.vm.rt.world.settings.gmst("isecondstosleepperupdate")))
		waitedBefore = waiting
		residents.stepResidents(head.cast, game.hourOf(talk.vm.rt.world.daysPassed),
			f32(talk.vm.rt.world.timeScale), talk.vm.rt.world.evaluate, player.feetOf(),
			cell.physics.world, frames.dt)
		soundScene?.doorsOpened(residents.placeInWorld(head.cast, talk.vm.rt.world))
		sinceLook += frames.dt
		if sinceLook >= lookEvery and not free:
			placed = player.playerPlaced(sneaking, talk.vm.rt.world.player)
			watchers = residents.watchersOf(head.cast, talk.vm.rt.world, cell.physics.world.scene,
				placed)
			talk.vm.rt.world.stepDetections(lighting, placed, watchers, sinceLook)
			sinceLook = 0.0
		fight?.takeMagic(talk.vm.rt.world)
		fight?.stepFight(
			residents,
			head.cast,
			player,
			walker,
			i,
			follow.headingOf(),
			actors.motions,
			cell.physics.world, frames.dt)
		fight?.giveValues(talk.vm.rt.world)
		if kill is order and order.frame == frames.count:
			residents.killNamed(
				head.cast,
				order.editorId,
				actors.motions,
				cell.physics.world,
				frames.dt
			)
		cell.physics.world.step(frames.dt)
		for refId in scene.movableRefs():
			scene.setOpen(refId, (talk.vm.rt.world.forms.get(refId) ?? continue).open)
		scene.advance(frames.dt)
		eye = camera.eye if free else follow.eyeOf()
		view = camera.view() if free else follow.viewOf()
		soundScene?.stepScene(player, walker, residents, head.cast, cell.physics.world,
			eye.skyrimPoint(), camera.yaw if free else follow.headingOf(), frames.dt)
		for line in soundScene?.newLines(musicOnly = true) ?? []:
			if musicTrace: print(line)
		aspect = f32(win.width) / f32(win.height.max(1))
		projection = scene.picture.beginFrame(Mat4.perspective(fovY, aspect, 4.0, 20000.0), view,
			win.width, win.height)
		fight?.showSpells(scene, player)
		r.drawCell(scene, win.width, win.height, projection, view, eye)
		bodies world.ActorPose[] = [] if bare else residents.residentPoses()
		if not bare and (free or not follow.isInside()):
			walking = walker.poseOfWalker(
				residents.clipNames[0],
				residents.durations[0]
			) ??
				player.poseOf()
			bodies.push(world.ActorPose(model = 0, pose = walking,
				feet = game.yUp.applyPoint(player.feetOf()), yaw = -player.heading))
		for res in residents.all:
			if not res.present: continue
			mouth = soundScene?.mouthOf(res.npc) ?? none
			actors.setFace(res.npc + 1, game.faceWeights(res.npc, mouth, faceClock))
		r.drawActors(actors, bodies, projection, view, eye)
		r.finishCell(scene)
		r.beginOverlay(win.width, win.height, engine.Camera())
		if ui is mut s:
			yaw, pitch = (camera.yaw, camera.pitch) if free
				else (follow.orbit.yaw, follow.orbit.pitch)
			at, along = eye.viewInGame(yaw, pitch) if free else follow.pickRay()
			s.update(talk, i, frames.dt, f64(yaw).degrees(), at, along,
				fight?.enemyPercent() ?? -1.0)
			s.draw(r)
			for ask in s.takeSounds():
				if soundScene is mut sound: sound.book.playAsk(ask)
			scene.picture.blurBehind = s.dimsScene()
			if s.prefs.revision != appliedChoices:
				appliedChoices = s.prefs.revision
				if soundScene is mut sound:
					sound.book.setSliders(s.prefs.volumes())
				talk.vm.rt.world.difficulty = s.prefs.difficulty()
		if going == none:
			door = ui?.takeTravel() ?? 0
			if frames.count == useAt and useDoor != 0:
				a, _ = talk.vm.activateRef(useDoor, talk.vm.rt.world.player)
				if a is Teleported(through, _, _): door = through
			if door != 0:
				going = talk.vm.rt.world.arrivalThrough(door)
				if going is a: print("through {door:08X} to {a.place} at {a.feet}")
			elif esm.areaOf(id) is area and not free:
				# the loaded grid follows the player: made again around his cell once he is past
				# its middle ring (the cells beyond the world's edge do not exist)
				moved = area.recentered(player.feetOf(), player.heading)
				if moved is a and talk.plugin.hasCellAt(esm.areaOf(a.place) ?? area):
					going = a
					print("the loaded grid moves to {a.place}")
		if going?.fades ?? false: fade = (fade + frames.dt / fadeSeconds).min(1.0)
		elif fade > 0.0: fade = (fade - frames.dt / fadeSeconds).max(0.0)
		if fade > 0.0:
			r.fillRect(0.0, 0.0, f32(win.width), f32(win.height), Vec4(0.0, 0.0, 0.0, fade))
		if frames.count % 30 == 0:
			fpsShown = frames.clock.fps
		e = camera.eye if free else game.yUp.applyPoint(player.feetOf())
		if not bare:
			r.drawLabel(font, "Skyrim  {head.cell}  {e.x:.0}, {-e.z:.0}, {e.y:.0}  {fpsShown} fps")
		asked = []
		if ui is mut s: asked = s.takeRequests()
		shot save.Screenshot? = none
		if asked.any(.writesSave()):
			shot = r.screenshot().screenshotOf()
			frames.count += 1
		else:
			r.showFrame(win, frames)
		for request in asked:
			outcome = request.carryOut(session, save.listSaves(savesDir), talk, residents,
				head.cast, player, fight, walker, cell.physics.world, shot)
			if not outcome.said.isEmpty: print(outcome.said)
			if outcome.loaded is snap:
				fight?.restoreFight(snap)
				follow = game.newFollow(player.heading)
				talkingTo = -1
			if ui is mut s: s.setSaves(save.listSaves(savesDir))
			if outcome.quit: quitting = true
		if quitting or fade >= 1.0 or (going != none and not (going?.fades ?? true)): break
	if going is a and not quitting:
		visited[id] = talk.vm.rt.world.leaving()
		previous = talk.vm.rt.world.copy()
		id = a.place.copy()
		arrival = a
		continue
	quitting = true
	feet = player.feetOf()
	print("the player at {feet.x:.0}, {feet.y:.0}, {feet.z:.0}, facing {player.heading.degrees():.0}; the camera at {camera.eye.x:.0}, {-camera.eye.z:.0}, {camera.eye.y:.0}; {frames.fpsText()}")
	for line in residents.residentsText(head.cast):
		print(line)
	for line in fight?.fightLines() ?? []:
		print(line)
	frames.printFrames()
