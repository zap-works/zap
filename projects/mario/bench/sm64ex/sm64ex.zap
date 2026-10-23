# The PC port the rewrite is measured and traced against: sm64ex built with the harness
# (projects/mario/bench/README.md).

import fs

defaultDir = "projects/mario/bench/pc/sm64ex/build/us_pc"

# the dir of the port's build: --pc <dir> of the program, else the default
pub fn dir() str:
	args.option("--pc") ?? defaultDir

# the port's executable, named whole (it runs from its own dir) as the system names one
pub fn exe() str:
	fs.join(currentDir(), "{dir()}/sm64.us.f3dex2e{exeSuffix()}")
