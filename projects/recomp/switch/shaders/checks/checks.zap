# What the shaders' tests share: Maxwell words written by hand, a program's translation checked
# for parts, a module built, a kernel run on a GPU backend against the CPU.

import fs
import recomp.switch.shaders

pub exit u64 = 0xE300_0000_0007_000F

# an ALU word: the opcode's top 16 bits, PT as the guard, then the fields
pub fn alu(top i64, fields (i64, i64)[]) i64:
	w = top << 48 | (7 << 16)
	for (at, value) in fields:
		w |= value << at
	w

# an ALU word of rd, ra and B at 20, then the other fields
pub fn regs(top i64, d i64, a i64, b i64, more (i64, i64)[] = []) i64:
	fields = [(0, d), (8, a), (20, b)]
	fields.extend(more)
	alu(top, fields)

# the program of the words in a stage (a compute one by groups of `group`), EXIT appended
pub fn sourceOf(
	name str,
	words i64[],
	stage shaders.Stage = .Compute,
	group i64[] = [1, 1, 1]
) shaders.Source:
	code = words.copy()
	code.push(i64.wrap(exit))
	program = shaders.Program(stage, header = none, words = code, start = 0)
	shaders.Source(name = name.copy(), program, group = group.copy() if stage == .Compute else [])

# What the translation of the source lacks: its instructions left out, then the parts its text does
# not hold (the text printed when any).
pub fn lacks(s shaders.Source, parts str[]) str[]:
	t = shaders.newTable().translateProgram(s.program, "T", [], s.group, {}) ?? return ["{error}"]
	out = t.missing.copy()
	out.extend(parts.filter(it not in t.text))
	if not out.isEmpty: print(t.text)
	out

# What building the module of the sources said: "" when it built with every instruction translated.
pub fn built(sources shaders.Source[], dir str) str:
	done, said = shaders.writeBuilt(sources, "projects/recomp/switch/build/tests/{dir}") ??
		return "{error}"
	if said != "": return said
	lacking = done.shaders.filter(not .missing.isEmpty).map(.name)
	"" if lacking.isEmpty else "instructions left out in {lacking.join(" ")}"

# the end of a program of gpuVerdict: its window, then the verdict printed
programEnd = r"""

mut frames = engine.newFrames()
mut win = engine.openWindow("Checks", 16, 16)
if not win.nextFrame(frames): fail("the window closed")
n = wrongs()
said = "right" if n == 0 else "not on this device" if n < 0 else "{n} WRONG"
print("{engine.backendName()}: {said}")
"""

# The verdict of `body`'s `fn wrongs() i64` (the count of the GPU's results unlike the CPU's, -1
# when the device cannot give them) run on the backend: "right", "not on this device" or the
# count wrong. `kernel` is the GPU file of the module `kernels` the body reads (in the project's
# build/, where its modules are found).
pub fn gpuVerdict(name str, gpu str, kernel str, body str) str:
	dir = "projects/recomp/switch/build/tests/{name}{gpu}"
	_ = fs.createDir("{dir}/kernels")
	fs.writeFile("{dir}/kernels/kernels.gpu.zap", kernel) ?? return "{error}"
	program = "import engine\nimport kernels\n\n{body}{programEnd}"
	fs.writeFile("{dir}/{name}.zap", program) ?? return "{error}"
	run = Process.output("{zapPath()} run {dir}/{name}.zap", vars = [runAssignment("gpu={gpu}")])
	said = run.out.trimmed().split(": ").last ?? ""
	if said != "right" and said != "not on this device": print(run.out)
	said.copy()
