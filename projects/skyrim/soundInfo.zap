# Prints a sound of the player's Skyrim install, its format and what it decodes to; or the sounds
# of an interior cell (the Sleeping Giant Inn by default) as the plugin names them: the acoustic
# space's ambient loop and region, the music type's tracks, the sound markers placed and the
# looping sounds of the objects placed (the fire), each resolved to the archives' keys; or the
# inn run headless (its actors, its physics, the player walking ahead from 1 s to 5 s) with the
# log of its sounds (when each started, at what volume and distance), the loudness of their mix
# by half seconds, and the mix written to a WAV file with --wav.
#
#   zap run projects/skyrim/soundInfo.zap [--install dir] <key> [--wav out.wav]
#   zap run projects/skyrim/soundInfo.zap [--install dir] --inn [cell]
#   zap run projects/skyrim/soundInfo.zap [--install dir] --scene [cell] [--seconds 10] [--hour 8] [--wav out.wav]

import fs
import skyrim
import skyrim.esm
import engine.audio
import engine.audio.wav
import engine.audio.xwma
import game.sound

fn xwmaLine(bytes ref u8[]):
	f = xwma.readXwmaFormat(bytes) ?? return "xWMA whose chunks do not read"
	codec = "WMA version 2" if f.tag == xwma.tagWma2
		else "WMA Pro" if f.tag == xwma.tagWmaPro
		else "?"
	seconds = f64(f.declaredFrames()) / f64(f.sampleRate.max(1))
	"xWMA, {codec} (tag 0x{f.tag:X}), {f.channels} channels, {f.sampleRate} Hz, {f.bitRate / 1000} kb/s, packets of {f.blockAlign} bytes, {seconds:.3} s declared"

# the file's container and codec
fn formatLine(bytes ref u8[]):
	if xwma.isXwma(bytes): return xwmaLine(bytes)
	if wav.isWav(bytes):
		f = wav.readWavFormat(bytes) ?? return "WAV whose format does not read"
		return "WAV, format {f.format}, {f.channels} channels, {f.sampleRate} Hz, {f.bits} bits"
	"neither xWMA nor WAV"

# what the samples are: their length, peak, loudness and clipped samples
fn statsLine(pcm wav.Pcm):
	peak f32 = 0.0
	sum = 0.0
	clipped = 0
	for x in pcm.samples:
		peak = peak.max(x.abs())
		sum += f64(x) * f64(x)
		if x.abs() >= 1.0: clipped += 1
	rms = (sum / pcm.samples.len.max(1)).sqrt()
	seconds = f64(pcm.frames()) / f64(pcm.sampleRate.max(1))
	"decoded {pcm.frames()} frames ({seconds:.3} s), peak {peak:.4}, rms {rms:.4}, {clipped} clipped"

# a FUZ file's sound (its lip data said), another file's bytes as they are
fn voiceSound(found str, move bytes u8[]):
	if not found.endsWith(".fuz"): return bytes
	fuz = skyrim.readFuz(bytes) ?? fail("{found}: {error}")
	print("FUZ version {fuz.version}, lip data {fuz.lip.len} bytes, sound {fuz.sound.len} bytes")
	fuz.sound

fn showSound(install skyrim.Install, key str, wavOut str?):
	found = install.installSound(key.lower()) ?? fail("{key} is in no archive")
	bytes = install.installRead(found) ?? fail("{found} cannot be read")
	print("{found}: {bytes.len} bytes")
	sound = voiceSound(found, move bytes)
	print(formatLine(sound))
	pcm = audio.decodeAudio(move sound) ?? fail("it does not decode")
	print(pcm.statsLine())
	out = wavOut ?? return
	fs.writeBytes(out, wav.encodeWav(pcm.samples, pcm.channels, pcm.sampleRate)) ??
		fail("cannot write {out}")
	print("written to {out}")

# the cell run headless: its sounds' log, the loudness of their mix, the mix written
fn showScene(dir str, cell str, wavOut str?):
	seconds = f32(args.optionNumbers("--seconds").first ?? 10.0)
	hour = f32(args.optionNumbers("--hour").first ?? 8.0)
	run = sound.runScene(dir, cell, hour, seconds, 1.0, 5.0, true) ?? fail
	for line in run.sound.book.logText(0):
		print(line)
	levels = sound.loudness(run.mix, 0.5)
	peak f32 = 0.0
	for x in run.mix:
		peak = peak.max(x.abs())
	print("loudness by half seconds (RMS): {levels.map("{it:.3}").join(" ")}")
	print("peak {peak:.3}, {run.steps} footsteps of the player")
	out = wavOut ?? return
	fs.writeBytes(out, wav.encodeWav(run.mix, 2, sound.mixRate)) ?? fail("cannot write {out}")
	print("written to {out}")

# the files a descriptor or marker plays, each as the install holds it
fn keysLine(install skyrim.Install, mut plugin esm.Esm, formId i64):
	keys = plugin.soundFiles(formId).map(install.installSound(it) ?? "{it} (missing)")
	keys.join(", ")

fn editorId(mut plugin esm.Esm, formId i64):
	r = plugin.recordOf(formId) ?? return "{formId:08X}"
	esm.textOf(r.body, r.fields, "EDID")

fn showAcoustics(install skyrim.Install, mut plugin esm.Esm, cell esm.Cell):
	space = plugin.recordOf(cell.acoustics) ?? return print("no acoustic space")
	print("acoustic space {esm.textOf(space.body, space.fields, "EDID")}")
	ambient = space.formOf("SNAM") ?? 0
	if ambient != 0:
		print("  ambient loop {plugin.editorId(ambient)}: {install.keysLine(plugin, ambient)}")
	region = space.formOf("RDAT") ?? 0
	print("  region {plugin.editorId(region)}" if region != 0 else "  no region")
	reverb = space.formOf("BNAM") ?? 0
	if reverb != 0: print("  reverb {reverb:08X}")

fn showMusic(install skyrim.Install, mut plugin esm.Esm, cell esm.Cell):
	if cell.music == 0: return print("no music type")
	print("music {plugin.editorId(cell.music)}")
	for id in (plugin.musicType(cell.music) ?? return).tracks:
		track = plugin.musicTrack(id) ?? continue
		files = [track.file, track.finale].filter(it != "")
		found = files.map(install.installSound(it) ?? "{it} (missing)")
		print("  track {track.editorId}: {found.join(", ")}")
		for sub in track.tracks:
			print("    palette track {plugin.editorId(sub)}")

# the sound markers and the objects with a looping sound (SNAM of a static, an activator, a light)
fn showPlaced(install skyrim.Install, mut plugin esm.Esm, cell esm.Cell):
	for r in cell.refs:
		b = plugin.recordOf(r.base) ?? continue
		sound = r.base if b.kind == "SOUN" else 0
		if b.kind in ["MSTT", "ACTI", "LIGH"]: sound = b.formOf("SNAM") ?? 0
		if sound == 0: continue
		at = "{r.position.x:.0} {r.position.y:.0} {r.position.z:.0}"
		name = esm.textOf(b.body, b.fields, "EDID")
		print("{b.kind} {name} {r.formId:08X} at {at}: {install.keysLine(plugin, sound)}")

dir = args.option("--install") ?? skyrim.defaultInstall
install = skyrim.openInstall(dir) ?? fail
args.options(
	[
		skyrim.installOption,
		ArgOption("--wav", true, "the WAV file to write"),
		ArgOption("--seconds", true, "how long the scene lasts"),
		ArgOption("--hour", true, "the hour of the day")
	]
)
rest = args.positional()
if "--scene" in args:
	return showScene(dir, rest[0] if not rest.isEmpty else "RiverwoodSleepingGiantInn",
		args.option("--wav"))
if "--inn" in args:
	plugin = esm.openEsm(install.installPlugin("Skyrim.esm")) ?? fail
	name = rest[0] if not rest.isEmpty else "RiverwoodSleepingGiantInn"
	cell = plugin.findCell(name) ?? fail("no interior cell {name}")
	print("{cell.editorId} {cell.formId:08X}")
	install.showAcoustics(plugin, cell)
	install.showMusic(plugin, cell)
	install.showPlaced(plugin, cell)
	return
if rest.isEmpty: fail("usage: soundInfo.zap [--install dir] <key> [--wav out.wav] | --inn [cell]")
install.showSound(rest[0], args.option("--wav"))
