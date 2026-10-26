# A BizHawk movie (.bk2, TASVideos') turned into the inputs of a route: BizHawk (winget install
# TASEmulators.BizHawk) plays it in the core that recorded it, on a hidden desktop, and
# bk2Route.lua writes the buttons of each frame that read the joypads; tools/oracle.lua's
# SNESRECOMP_POLLS gives them at Mesen 2's reads and writes the route by frame. Inputs only, nothing of
# the game. Run from the repository root:
#
#   zap run projects/recomp/snes/tools/bk2Route.zap movie.bk2 polls.txt [--rom <file>]
#
# Keyed by frame, as the movie is, the route drifts: a level's load lags a frame more or less in
# Mesen than in BizHawk's bsnes, and the buttons then land a frame off.

import fs
import win

# BizHawk writes its settings back when it ends: a fresh copy each run
settings = r"""
	{
	  "LastWrittenFrom": "2.11",
	  "SkipSuperuserPrivsCheck": true,
	  "FirstBoot": false,
	  "UpdateAutoCheckEnabled": false,
	  "SoundEnabled": false,
	  "RunInBackground": true,
	  "AcceptBackgroundInput": false,
	  "DispMethod": 1
	}
	"""

paths = args.positional()
if paths.len < 2: fail("usage: bk2Route.zap movie.bk2 polls.txt --rom <file>")
movie = fs.join(currentDir(), paths[0])
polls = fs.join(currentDir(), paths[1])
ini = "{polls}.ini"
fs.writeFile(ini, settings) ?? fail("cannot write {ini}: {error}")
exe = "{env.get("LOCALAPPDATA") ?? ""}/Microsoft/WinGet/Packages/TASEmulators.BizHawk_Microsoft.Winget.Source_8wekyb3d8bbwe/EmuHawk.exe"
if not fs.exists(exe): fail("no BizHawk at {exe}: winget install TASEmulators.BizHawk")
lua = fs.join(currentDir(), "projects/recomp/snes/tools/bk2Route.lua")
rom = fs.join(currentDir(), args.option("--rom") ?? fail("which cartridge? --rom <file>"))
env.set("SNESRECOMP_POLLS", polls)
_ = fs.deleteFile(polls)
# the 41 minutes of 3956M take BizHawk some 20 to 40, uncapped
code = win.runHidden(
	"\"{exe}\" --config={ini} --movie={movie} --lua={lua} {rom}",
	"zap-snes-bk2route",
	7_200_000
) ??
	fail("cannot run BizHawk: {error.code}")
if not fs.exists(polls): fail("the script did not run (BizHawk ended with {code})")
print("{(fs.readFile(polls) ?? "").lines().len} lines written")
