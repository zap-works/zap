# How much of a module's code the decoder knows: every word of an NSO's .text decoded, the
# unknown ones counted by their encoding group (bits 28-25, in hex) and the commonest shown with their
# top 11 bits. Run from the repository root:
#
#   zap run projects/recomp/switch/tools/coverage.zap <exefs file (an NSO stored whole)>

import fs
import recomp.switch.arm64
import recomp.switch.package

path = args.positional().first ??
	fail("usage: zap run projects/recomp/switch/tools/coverage.zap <nso>")
file = fs.readBytes(path) ?? fail("cannot read {path}: {error}")
nso = package.readNso(file) ?? fail("{path} is no NSO")
text = nso.segments[0]
groups {i64: i64} = {}
tops {i64: i64} = {}
unknown = 0
words = text.size / 4
for k in 0..words:
	w = i64(file.u32le(text.fileAt + k * 4))
	if arm64.decode(w, text.memoryAt + k * 4).op != .Unknown: continue
	unknown += 1
	g = (w >> 25) & 15
	groups[g] = (groups.get(g) ?? 0) + 1
	t = w >> 21
	tops[t] = (tops.get(t) ?? 0) + 1
print("{words} words, {words - unknown} known ({(words - unknown) * 1000 / words / 10}.{(words - unknown) * 1000 / words % 10}%)")
for g, n in groups:
	print("  group {g:x}: {n}")
ranked = tops.keys().sortedBy(-(tops.get(it) ?? 0))
for t in ranked[..ranked.len.min(25)]:
	print("  top {t:03x}: {tops.get(t) ?? 0}")
