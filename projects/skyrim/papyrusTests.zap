# The VM on hand-assembled scripts, without the game: arithmetic, branches, strings, arrays, calls,
# a latent wait and an update the scheduler sends.

import game.sim
import papyrus

fn id(name str) papyrus.Operand:
	.Ident(name.copy())

fn op(name str, args papyrus.Operand[]):
	papyrus.Instruction(
		op = papyrus.opcodeOf(name) ?? fail("no opcode {name}"),
		args = args.copy(),
		varargs = []
	)

fn call(name str, args papyrus.Operand[], varargs papyrus.Operand[]):
	papyrus.Instruction(
		op = papyrus.opcodeOf(name) ?? fail("no opcode {name}"),
		args = args.copy(),
		varargs = varargs.copy()
	)

fn typed(pairs str[]):
	out = []
	for k in 0..pairs.len / 2:
		out.push(papyrus.TypedName(name = pairs[2 * k].copy(), typeName = pairs[2 * k + 1].copy()))
	out

fn fun(
	name str,
	returnType str,
	params str[],
	locals str[],
	code papyrus.Instruction[],
	flags i64
):
	papyrus.Function(
		name = name.copy(),
		returnType = returnType.copy(),
		doc = "",
		userFlags = 0,
		flags,
		params = typed(params),
		locals = typed(locals),
		code = code.copy()
	)

fn script(
	name str,
	parent str,
	variables papyrus.Variable[],
	functions papyrus.Function[]
):
	o = papyrus.ScriptObject(
		name = name.copy(),
		parent = parent.copy(),
		doc = "",
		userFlags = 0,
		autoState = "",
		variables = variables.copy(),
		properties = [],
		states = [papyrus.State(name = "", functions = functions.copy())]
	)
	papyrus.Script(
		major = 3,
		minor = 2,
		gameId = 1,
		compiled = 0,
		source = "{name}.psc",
		user = "",
		machine = "",
		modified = 0,
		debug = [],
		userFlags = [],
		objects = [o]
	)

# Calc: Sum(a, b), Loop() adding 1 to 10, Text() joining strings, Arrays() over an int[]
fn calc():
	sum = fun("Sum", "int", ["a", "int", "b", "int"], ["::temp0", "int"], [
		op("iadd", [id("::temp0"), id("a"), id("b")]),
		op("return", [id("::temp0")])
	], 0)
	loopCode = [
		op("assign", [id("i"), .Int(1)]),
		op("cmp_le", [id("::temp0"), id("i"), .Int(10)]),
		op("jmpf", [id("::temp0"), .Int(5)]),
		call("callmethod", [id("Sum"), id("self"), id("total")], [id("total"), id("i")]),
		op("iadd", [id("i"), id("i"), .Int(1)]),
		op("jmp", [.Int(-4)]),
		op("nop", []),
		op("return", [id("total")])
	]
	loops = fun("Loop", "int", [], ["i", "int", "total", "int", "::temp0", "bool"], loopCode, 0)
	text = fun("Text", "string", [], ["s", "string", "same", "bool"], [
		op("strcat", [id("s"), .Text("Riverwood "), .Int(7)]),
		op("strcat", [id("s"), id("s"), .Float(0.5)]),
		op("cmp_eq", [id("same"), .Text("ABC"), .Text("abc")]),
		op("jmpt", [id("same"), .Int(2)]),
		op("assign", [id("s"), .Text("case matters")]),
		op("return", [id("s")])
	], 0)
	arrays = fun("Arrays", "int", [], ["arr", "int[]", "x", "int", "n", "int", "at", "int", "out", "int"], [
		op("array_create", [id("arr"), .Int(3)]),
		op("array_setelement", [id("arr"), .Int(1), .Int(7)]),
		op("array_getelement", [id("x"), id("arr"), .Int(1)]),
		op("array_length", [id("n"), id("arr")]),
		op("array_findelement", [id("arr"), id("at"), .Int(7), .Int(0)]),
		op("imul", [id("out"), id("x"), .Int(100)]),
		op("imul", [id("n"), id("n"), .Int(10)]),
		op("iadd", [id("out"), id("out"), id("n")]),
		op("iadd", [id("out"), id("out"), id("at")]),
		op("return", [id("out")])
	], 0)
	script("Calc", "", [], [sum, loops, text, arrays])

test "a hand-assembled script adds, loops, joins strings and fills an array":
	vm = papyrus.newVm(none)
	vm.lib.addScript(calc())
	me = vm.lib.newObject(vm.rt, 0x100, "Calc")
	expect vm.callFunction("Calc", me, "Sum", [.Int(2), .Int(40)]) == .Int(42)
	expect vm.callFunction("Calc", me, "Loop", []) == .Int(55)
	expect vm.callFunction("Calc", me, "Text", []) == .Str("Riverwood 70.500000")
	expect vm.callFunction("Calc", me, "Arrays", []) == .Int(731)
	expect vm.rt.log.isEmpty

test "ints wrap at 32 bits, division by zero gives 0 and says so":
	expect papyrus.wrap32(0x7FFF_FFFF + 1) == -0x8000_0000
	vm = papyrus.newVm(none)
	vm.lib.addScript(script("Div", "", [], [fun("D", "int", [], ["x", "int"], [
		op("idiv", [id("x"), .Int(5), .Int(0)]),
		op("return", [id("x")])
	], 0)]))
	expect vm.callFunction("Div", 0, "D", []) == .Int(0)
	expect vm.rt.log == ["error: division by zero"]

# Form with the native RegisterForSingleUpdate, Utility with the latent Wait, and Timer, which
# registers in OnInit, counts its updates and marks a wait's end
fn timerScripts():
	native = 2 | 1
	form = script(
		"Form",
		"",
		[],
		[fun("RegisterForSingleUpdate", "None", ["afInterval", "float"], [], [], 2)]
	)
	utility = script(
		"Utility",
		"",
		[],
		[fun("Wait", "None", ["afSeconds", "float"], [], [], native)]
	)
	onInit = fun("OnInit", "None", [], ["::NoneVar", "None"], [
		call("callmethod", [id("RegisterForSingleUpdate"), id("self"), id("::NoneVar")], [.Float(2.0)]),
		call("callstatic", [id("Utility"), id("Wait"), id("::NoneVar")], [.Float(1.0)]),
		op("assign", [id("waited"), .Bool(true)])
	], 0)
	onUpdate = fun("OnUpdate", "None", [], [], [op("iadd", [id("count"), id("count"), .Int(1)])], 0)
	variables = [
		papyrus.Variable(name = "count", typeName = "int", userFlags = 0, initial = .Null),
		papyrus.Variable(name = "waited", typeName = "bool", userFlags = 0, initial = .Null)
	]
	[form, utility, script("Timer", "Form", variables, [onInit, onUpdate])]

test "the scheduler wakes a wait and sends a single update once":
	vm = papyrus.newVm(none)
	for s in timerScripts():
		vm.lib.addScript(s.copy())
	me = vm.bindScript(0x200, "Timer", []) ?? fail("Timer does not bind")
	noArgs = []
	sent = vm.sendEvent(me, "OnInit", noArgs)
	expect sent
	vm.runThreads()
	expect vm.rt.objects[me].vars["waited"] == .Bool(false)
	vm.tick(1.0)
	expect vm.rt.objects[me].vars["waited"] == .Bool(true)
	expect vm.rt.objects[me].vars["count"] == .Int(0)
	vm.tick(1.5)
	expect vm.rt.objects[me].vars["count"] == .Int(1)
	vm.tick(5.0)
	expect vm.rt.objects[me].vars["count"] == .Int(1)
	expect vm.rt.threads.isEmpty and vm.rt.updates.isEmpty

fn nativeCall(me i64, key str, returnType str):
	papyrus.NativeCall(key = key.copy(), me, args = [], thread = 0, returnType = returnType.copy())

test "EvaluatePackage asks the AI to pick a package again; GetCurrentLocation is the ref's; no one is in dialogue":
	vm = papyrus.newVm(none)
	orgnar = 0x1_3486
	vm.rt.world.addForm(orgnar)
	vm.rt.world.forms[orgnar].location = 0x1_3163
	me = vm.lib.objectFor(vm.rt, orgnar, "actor")
	vm.lib.callNative(vm.rt, nativeCall(me, "actor.evaluatepackage", "None"))
	expect vm.rt.world.evaluate.get(orgnar) != none
	expect vm.lib.callNative(vm.rt, nativeCall(me, "actor.isindialoguewithplayer", "Bool")) ==
		.Bool(false)
	match vm.lib.callNative(
		vm.rt,
		nativeCall(me, "objectreference.getcurrentlocation", "Location")
	):
		Object(id): expect vm.rt.objects[id].form == 0x1_3163
		_: fail("no location")

test "Actor.AddPerk, HasPerk and RemovePerk change the perks an actor holds; a perk the world lacks waits to be learned":
	vm = papyrus.newVm(none)
	player = vm.rt.world.player
	vm.rt.world.addForm(player)
	vm.rt.world.actors[player] = sim.ActorState(npc = 7, race = 1, level = 1, values = {})
	me = vm.lib.objectFor(vm.rt, player, "actor")
	perk = vm.lib.objectFor(vm.rt, 0x777, "perk")
	asked = papyrus.NativeCall(key = "actor.hasperk", me, args = [.Object(perk)], thread = 0,
		returnType = "Bool")
	expect vm.lib.callNative(vm.rt, asked.copy()) == .Bool(false)
	given = papyrus.NativeCall(key = "actor.addperk", me, args = [.Object(perk)], thread = 0,
		returnType = "None")
	vm.lib.callNative(vm.rt, given.copy())
	expect vm.lib.callNative(vm.rt, asked.copy()) == .Bool(true)
	expect vm.rt.world.perkRank(player, 0x777) == 1 and vm.rt.world.unlearned == [0x777]
	taken = papyrus.NativeCall(key = "actor.removeperk", me, args = [.Object(perk)], thread = 0,
		returnType = "None")
	vm.lib.callNative(vm.rt, taken.copy())
	expect vm.lib.callNative(vm.rt, asked.copy()) == .Bool(false)
