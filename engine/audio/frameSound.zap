# An emulated console's sound, made by the program as it runs and handed over a frame at a time:
# heard through a feed once the program opens it (a window's run), and kept whole for a WAV file
# when the run asks for one (`--wav path`).

import fs
import engine.audio.wav

# Where a program's own samples go: interleaved, `channels` of them at `rate` frames a second.
pub type FrameSound:
	rate i64
	channels i64 = 2
	wavPath str = ""   # the file the run's sound is written to at its end; "" none
	feeds Feed[] = []
	recorded f32[] = []

# The samples pushed from now on are heard (the audio thread started).
pub fn hear(mut frameSound FrameSound):
	start()
	frameSound.feeds.push(newFeed())

# whether anything takes the samples: worth making them
pub fn isWanted(frameSound FrameSound) bool:
	not frameSound.feeds.isEmpty or not frameSound.wavPath.isEmpty

# A frame's samples, heard after those before and recorded for the WAV.
pub fn pushFrame(mut frameSound FrameSound, samples ref f32[]):
	if not frameSound.wavPath.isEmpty: frameSound.recorded.extend(samples)
	if not frameSound.feeds.isEmpty:
		frameSound.feeds[0].push(samples, frameSound.channels, frameSound.rate)

# The run's sound written to the WAV file, when one was asked for.
pub fn saveWav(frameSound FrameSound):
	if frameSound.wavPath.isEmpty: return
	fs.writeBytes(
		frameSound.wavPath,
		wav.encodeWav(frameSound.recorded, frameSound.channels, frameSound.rate)
	) ??
		eprint("cannot write {frameSound.wavPath}: {error}")
