# Skyrim's sounds read from the player's install: the inn's music decoded as FFmpeg decodes it, a
# voice's FUZ, the inn's sounds as the plugin names them, and the inn heard as the game runs it
# (its music, its loops at the game's volumes, the player's footsteps, the mix); skipped quietly
# without the install.

import fs
import skyrim
import skyrim.esm
import engine.audio
import engine.audio.xwma
import game
import game.sound
import skyrim.actor
import skyrim.hkx

music = "music/tavern/mus_tavern_01.xwm"
inn = "RiverwoodSleepingGiantInn"

fn installed() skyrim.Install?:
	match skyrim.openInstall(skyrim.defaultInstall):
		i: i
		error:
			eprint("skipped: {error}")
			none

# the floats of a raw little-endian f32 file
fn floatsAt(path str):
	b = fs.readBytes(path) ?? return []
	(0..b.len / 4).map(b.f32le(4 * it))

# FFmpeg's decoding of an xWMA file, none when ffmpeg is not on the PATH
fn ffmpegDecoded(bytes u8[]) f32[]?:
	input = "{testDir()}in.xwm"
	output = "{testDir()}out.f32"
	fs.writeBytes(input, bytes) ?? fail("cannot write {input}")
	line = "ffmpeg -v error -y -i {quoteArg(input)} -f f32le {quoteArg(output)}"
	if Process.run(line) != 0: return none
	floatsAt(output)

test "the inn's music is WMA version 2, decodes to the size its dpds declares, and as ffmpeg does":
	install = installed() ?? return
	bytes = install.installRead(music) ?? fail("no {music}")
	f = xwma.readXwmaFormat(bytes) ?? fail("no xWMA format")
	expect f.tag == xwma.tagWma2 and f.channels == 2 and f.sampleRate == 44_100
	pcm = audio.decodeAudio(bytes.copy()) ?? fail("it does not decode")
	expect pcm.frames() == f.declaredFrames()
	reference = ffmpegDecoded(bytes) ?? return eprint("skipped the comparison: no ffmpeg")
	expect reference.len == pcm.samples.len
	worst f32 = 0.0
	for i in 0..reference.len:
		worst = worst.max((reference[i] - pcm.samples[i]).abs())
	expect worst < 1e-5

test "a voice's FUZ holds its lip data and an xWMA line that decodes":
	install = installed() ?? return
	keys = install.installFind("sound/voice/skyrim.esm/femaleeventoned/")
	expect not keys.isEmpty
	bytes = install.installRead(keys[0]) ?? fail("no {keys[0]}")
	fuz = skyrim.readFuz(bytes) ?? fail
	expect fuz.version == 1 and not fuz.lip.isEmpty
	f = xwma.readXwmaFormat(fuz.sound) ?? fail("no xWMA in the FUZ")
	expect f.tag == xwma.tagWma2 and f.channels == 1
	pcm = audio.decodeAudio(fuz.sound) ?? fail("the line does not decode")
	expect pcm.frames() == f.declaredFrames() and pcm.samples.any(it != 0.0)

test "the inn's sounds: its ambient loop, its tavern music and its fire, each in the archives":
	install = installed() ?? return
	plugin = esm.openEsm(install.installPlugin("Skyrim.esm")) ?? fail
	cell = plugin.findCell("RiverwoodSleepingGiantInn") ?? fail("no inn")
	space = plugin.recordOf(cell.acoustics) ?? fail("no acoustic space")
	ambient = plugin.soundFiles(space.formOf("SNAM") ?? 0)
	expect ambient == ["sound/fx/ambt/ambt_interiorgeneric_01_lp.wav"]
	tracks = (plugin.musicType(cell.music) ?? fail("no music type")).tracks
	files = tracks.map((plugin.musicTrack(it) ?? fail("no track")).file)
	expect files.len == 2 and install.installSound(files[0]) == music
	fires = 0
	for r in cell.refs:
		b = plugin.recordOf(r.base) ?? continue
		if b.kind != "MSTT": continue
		for key in plugin.soundFiles(b.formOf("SNAM") ?? continue):
			expect install.installSound(key) != none
			if "fire" in key: fires += 1
	expect fires == 3

test "a material's Havok hash is the CRC-32 of its name begun at 0, as NifSkope's SKY_HAV_MAT_STONE":
	expect esm.materialHash("Stone") == 3_741_512_247

# the inn's sounds heard as the game runs them for 5 s, the player walking ahead from 0.5 s
# (game.sound's runScene); none without the install
fn innRun() sound.SceneRun?:
	if installed() == none: return none
	sound.runScene(skyrim.defaultInstall, inn, 8.0, 5.0, 0.5, 5.0, false) ?? fail

# the volume a descriptor of the SFX category plays at with this static attenuation: the
# category's static volume times the master's (both 0xE665 of 0xFFFF), the attenuation in dB
fn sfxVolume(attenuation f32):
	share f32 = f32(0xE665) / 65_535.0
	share * share * sound.decibels(-attenuation)

fn near(a f32, b f32):
	(a - b).abs() < 0.001

# the files of the inn's music type's tracks
fn innMusic(install skyrim.Install):
	plugin = esm.openEsm(install.installPlugin("Skyrim.esm")) ?? fail
	cell = plugin.findCell(inn) ?? fail("no inn")
	tracks = (plugin.musicType(cell.music) ?? fail("no music type")).tracks
	tracks.map((plugin.musicTrack(it) ?? fail("no track")).file)

# its first track plays as the player enters
fn checkMusic(run sound.SceneRun, files str[]):
	first = run.sound.book.log.find(.why.startsWith("music: MUSTavern plays")) ?? fail("no music")
	expect first.time == 0.0 and first.key in files

# the acoustic space's loop and the fires' loops start at frame 0 at the game's volumes
fn checkLoops(run sound.SceneRun):
	log = run.sound.book.log.filter(.time == 0.0)
	ambient = log.find(.what == "AMBtInteriorGeneric01LPSD") ?? fail("no ambient loop")
	expect ambient.distance < 0.0 and near(ambient.volume, sfxVolume(12.78))
	fires = log.filter(.what == "FXFireCampfireLPSD")
	expect fires.len == 3 and fires.all(.distance > 0.0 and near(.volume, sfxVolume(13.22)))

# the player's walk sounds a footstep every half of its cycle, from the stone floor's set
fn checkSteps(run sound.SceneRun, install skyrim.Install):
	key = install.actorAnimationKey(game.walkClip, false) ?? fail("no walk clip")
	cycle = (hkx.readClipTimes(install.installRead(key) ?? []) ?? fail).duration
	steps = run.sound.book.log.filter(.why.startsWith("the player Foot"))
	expect steps.len >= 6
	for k in 1..steps.len:
		expect (f32(steps[k].time - steps[k - 1].time) - cycle / 2.0).abs() < 0.04
	expect steps.all(
		.why.endsWith("on MaterialStone") and .what.startsWith("FSTPlayerBarefootStone")
	)

# the first 2 s of the mix are heard and stay below full scale
fn checkMix(run sound.SceneRun):
	two = run.mix[..2 * 2 * sound.mixRate]
	peak f32 = 0.0
	for x in two:
		peak = peak.max(x.abs())
	loud = sound.loudness(two, 0.5)
	expect loud.all(it > 0.005) and peak < 1.0

test "the inn's music type resolves to its two tracks, each in the archives":
	install = installed() ?? return
	files = install.innMusic()
	expect files.len == 2 and files.all(install.installSound(it) != none)

# one run checked for all, as the offline mix is the program's one
test "the inn heard for 5 s: its music at entry, its loops at the game's volumes, the player's steps, its mix":
	install = installed() ?? return
	run = innRun() ?? return
	run.checkMusic(install.innMusic())
	run.checkLoops()
	run.checkSteps(install)
	run.checkMix()

# the character graph, its clips' lengths and the footstep keys its locomotion clips carry
type Locomotion:
	graph hkx.Graph
	lengths {str: f32}
	keys sound.StepKeys

fn locomotion():
	install = skyrim.openInstall(skyrim.defaultInstall) ?? fail
	g = install.readCharacterGraph() ?? fail
	lengths = install.clipDurations(g.clipNamesOf())
	keys = install.stepKeysOf(g.locomotionClips(lengths), false)
	Locomotion(graph = g, lengths, keys)

test "the footsteps' keys are those the clips of the graph's locomotion carry, in seconds into the clip":
	if not fs.exists(esm.defaultEsm()): return
	l = locomotion()
	keys = l.keys
	lengths = l.lengths
	walk = keys.clips.get(game.walkClip) ?? fail("no walk keys")
	expect walk.map(.tag).sorted() == ["FootLeft", "FootRight"]
	expect walk.all(.at > 0.0 and .at < keys.lengths[game.walkClip])
	expect (keys.lengths[game.walkClip] - lengths[game.walkClip]).abs() < 0.001
	expect keys.clips.get(game.runClip) != none
	expect keys.clips.keys().all(.startsWith("mt_"))

test "a body walking has the graph play the walk clip, whose key the footstep follows":
	if not fs.exists(esm.defaultEsm()): return
	l = locomotion()
	g = l.graph
	lengths = l.lengths
	keys = l.keys
	w = g.newWalker(true)
	feet = Vec3(0.0, 0.0, 0.0)
	crossed = []
	was = 0.0
	for frame in 0..180:
		if frame >= 30: feet.y += 82.45 / 60.0
		w.stepWalker(g, lengths, feet, 0.0, true, 1.0 / 60.0)
		lead = w.animator.layers[0]
		if frame > 60 and lead.clip == game.walkClip:
			phase = lead.time % keys.lengths[game.walkClip]
			for k in keys.clips[game.walkClip]:
				if phase >= k.at and was < k.at: crossed.push(k.tag.copy())
			was = phase
		else:
			was = 0.0
	expect crossed.len >= 2
	expect crossed[0] != crossed[1]
