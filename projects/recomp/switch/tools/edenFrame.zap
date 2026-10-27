# Frames of a game as Eden draws them (the oracle's pictures), headless: Eden's Vulkan renderer
# runs on a hidden desktop (its window never shows; SDL's offscreen driver cannot make a Vulkan
# surface) under RenderDoc, which captures the presented frame at each wanted second. Eden, its
# configuration, the game (the user's own NSP) and RenderDoc are outside the repository. Run from
# the repository root:
#
#   zap run projects/recomp/switch/tools/edenFrame.zap --eden <dir of eden-cli> --game <nsp>
#       --renderdoc <dir of qrenderdoc> --out <absolute dir> [--at <seconds>,...]
#
# writes eden-<second>.png (1280 x 720) into --out for each second (60, 120 and 180 by default) after
# Eden starts, and frames.log; BotW's title screen shows from about the first minute.

import fs
import recomp.switch.oracle
import win

edenDir = args.option("--eden") ?? fail("--eden <dir of eden-cli>")
game = args.option("--game") ?? fail("--game <nsp>")
renderdocDir = args.option("--renderdoc") ?? fail("--renderdoc <dir of qrenderdoc>")
out = args.option("--out") ?? fail("--out <absolute dir>")
seconds = args.option("--at") ?? "60,120,180"
script = "projects/recomp/switch/oracle/frames.py"

oracle.setFrames(fs.join(edenDir, "user/config/sdl2-config.ini")) ?? fail(error.why)
fs.createDir(out) ?? fail("cannot make {out}: {error}")
job = fs.join(out, "job.txt")
fs.writeFile(
	job,
	[fs.join(edenDir, "eden-cli.exe"), edenDir, game, out.copy(), seconds].join("\n")
) ??
	fail("cannot write {job}: {error}")
env["ZAP_EDEN_FRAMES"] = job   # the script's only input, read by oracle/frames.py inside RenderDoc
env["VK_ADD_IMPLICIT_LAYER_PATH"] = renderdocDir   # the Vulkan loader finds RenderDoc's layer without a registry entry
code = win.runHidden(
	"{quoteArg(fs.join(renderdocDir, "qrenderdoc.exe"))} --python {quoteArg(script)}",
	"eden-frames",
	900_000
) ??
	fail("{error}")
if not fs.exists(fs.join(out, "done.txt")):
	fail("no frames: see {fs.join(out, "frames.log")} (exit {code})")
print("frames in {out}")
