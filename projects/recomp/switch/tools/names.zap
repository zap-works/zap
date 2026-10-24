# Names guest addresses by the modules' symbols (the sdk's .dynsym): the nearest symbol at or
# before each, with the distance. Run from the repository root:
#
#   zap run projects/recomp/switch/tools/names.zap <exefs dir> <hex address>...

import recomp.switch.horizon
import recomp.switch.translate

given = args.positional()
path = given.first ?? fail("usage: names.zap <exefs dir> <hex address>...")
k = horizon.loadCode(path) ?? fail
names {i64: str} = {}
for m in k.modules:
	for at, name in translate.symbolNames(m.at):
		names[at] = name.copy()
starts = names.keys().sorted()
for text in given[1..]:
	at = i64.parse("0x{text}") ?? fail("{text} is no hex address")
	moduleAt = 0
	for m in k.modules:
		if m.at <= at and at < m.at + m.textSize: moduleAt = m.at
	owner = "module at {moduleAt:x}" if moduleAt != 0 else "no module"
	best = -1
	for s in starts:
		if s <= at: best = s
		else: break
	if best >= 0 and at - best < 0x10000:
		print("{text}: {names[best]} + {at - best:x} ({owner})")
	else:
		print("{text}: {owner}, {at - moduleAt:x} into it")
