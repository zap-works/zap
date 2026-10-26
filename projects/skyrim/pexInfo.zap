# Papyrus scripts of the install: a script disassembled, the scripts bound in the inn, a function
# run, or every script parsed. Run from the repository root:
#
#   zap run projects/skyrim/pexInfo.zap <script>              a script's listing (as Champollion's)
#   zap run projects/skyrim/pexInfo.zap --inn                 the scripts bound in the inn's cell
#   zap run projects/skyrim/pexInfo.zap --run <script> <fn>   a function run in an empty world
#   zap run projects/skyrim/pexInfo.zap --all                 every PEX of the archives parsed
#   zap run projects/skyrim/pexInfo.zap --install D:/Data ... another install

import skyrim
import skyrim.esm
import papyrus

inn = "RiverwoodSleepingGiantInn"

fn showBindings(bindings papyrus.Binding[]):
	for b in bindings:
		place = "own" if b.record == b.placed else "base {b.kind} {b.record:08X} {b.editorId}"
		print("ref {b.placed:08X} ({place})")
		for s in b.vmad.scripts:
			print("  {s.name}")
			for p in s.properties:
				values = p.values.map(.vmadValueText()).join(", ")
				print("    {p.name} = {"[" if p.isArray() else ""}{values}{"]" if p.isArray() else ""}")

fn listAll(install skyrim.Install):
	keys = install.installFind(papyrus.scriptDir).filter(.endsWith(".pex"))
	failed = 0
	for key in keys:
		bytes = install.installRead(key) ?? fail("{key} is in no archive")
		if papyrus.readPex(bytes) is error:
			failed += 1
			print("{key}: {error}")
	print("{keys.len - failed} of {keys.len} scripts parse")

dir = args.option("--install") ?? skyrim.defaultInstall
args.options([skyrim.installOption, ArgOption("--run", true, "the script to run")])
words = args.positional()
install = skyrim.openInstall(dir) ?? fail
if args.hasFlag("--inn"):
	plugin = esm.openEsm(install.installPlugin("Skyrim.esm")) ?? fail
	bindings = plugin.cellBindings(inn) ?? fail("no {inn}")
	showBindings(bindings)
	vm = papyrus.newVm(install)
	natives {str: bool} = {}
	scripts {str: bool} = {}
	for b in bindings:
		for s in b.vmad.scripts:
			scripts[s.name.lower()] = true
	for name in scripts.keys():
		for key in vm.nativesOf(name):
			natives[key] = true
	print("scripts: {scripts.keys().sorted().join(" ")}")
	print("natives: {natives.keys().sorted().join(" ")}")
	ids = vm.bindCell(bindings)
	vm.tick(0.0)
	print("{ids.len} objects bound, OnInit run; the log:")
	for line in vm.rt.log:
		print("  {line}")
	return
if args.hasFlag("--all"):
	install.listAll()
	return
run = args.option("--run")
if run != none:
	vm = papyrus.newVm(install)
	script = run ?? ""
	object = vm.lib.newObject(vm.rt, 0xFF00_0001, script) if vm.ensureScript(script) else 0
	result = vm.callFunction(script, object, words[0] if not words.isEmpty else "OnInit", [])
	vm.runThreads()
	for line in vm.rt.log:
		print(line)
	print("result: {vm.rt.valueText(result)}")
	return
script = install.loadScript(words[0] if not words.isEmpty else "") ?? fail
print(script.listing())
