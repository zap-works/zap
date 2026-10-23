# The sound's volume as the player sets it (a phone's menu bar): kept beside the dump
# (<stem>.volume, a number 0..1) so the next start sounds the same.

import engine.audio
import fs
import recomp.touch

fn volumeFile():
	besideDump("volume")

# the volume kept, heard from now on and shown on the menu's bar
fn startVolume():
	v = (f64.parse((fs.readFile(volumeFile()) ?? "").trimmed()) ?? 1.0).clamp(0.0, 1.0)
	audio.setMasterVolume(f32(v))
	overlay.setLevel("volume", v)

fn setVolume(v f64):
	audio.setMasterVolume(f32(v))
	fs.writeFile(volumeFile(), "{v}\n") ?? eprint("cannot write {volumeFile()}: {error}")
