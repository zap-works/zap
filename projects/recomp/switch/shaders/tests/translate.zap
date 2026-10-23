# deko3d's examples' compiled shaders (built by tools/homebrew.zap from switch-examples'
# graphics/deko3d GLSL): every instruction decodes, and each program's translation compiles.
#   needs: projects/recomp/switch/rom/homebrew/shaders/deko_examples/basic_vsh.dksh (built by tools/homebrew.zap)

import fs
import recomp.switch.shaders

root = "projects/recomp/switch/rom/homebrew/shaders"

fn dkshFiles():
	out = []
	for dir in ["deko_basic", "deko_examples"]:
		for name in fs.list("{root}/{dir}") ?? []:
			out.push("{root}/{dir}/{name}")
	out

test "every instruction of the examples' shaders decodes":
	t = shaders.newTable()
	unknown = []
	count = 0
	for path in dkshFiles():
		d = shaders.readDksh(fs.readBytes(path) ?? []) ?? fail("{path}: {error}")
		for i in t.decodeProgram(d.program.words):
			count += 1
			if i.op == .Unknown: unknown.push("{path} at {i.at:x}")
	expect count > 400
	expect unknown.isEmpty

test "each program's translation compiles, named by one program":
	sources = dkshFiles().map(shaders.readSource(it) ?? fail)
	out = "projects/recomp/switch/out/tests/shaders"
	done = shaders.writeModule(sources, out) ?? fail
	fs.writeFile("{out}/programs.zap", shaders.namingProgram(done.shaders, [])) ?? fail("{error}")
	built = Process.output("{zapPath()} build {out}/programs.zap")
	if built.code != 0: print(built.out)
	expect built.code == 0
	print(done.skipped.join("\n"))
	print(done.shaders.filter(not .missing.isEmpty).map(.name).join(" "))
	prints """
		DekoExamplesTessSimpleTcsh: a TessControl stage: Zap has vertex, pixel and compute stages
		DekoExamplesTessSimpleTesh: a TessEval stage: Zap has vertex, pixel and compute stages
		DekoExamplesSinewave
		"""
