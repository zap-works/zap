# The interpreter: a block's actions run from one index to another over an activation (the stack,
# the registers, the constant pool, the scope chain, `this` and the target clip), after Ruffle's
# core/src/avm1/activation.rs. A jump out of the range being run (a `break` out of a with block)
# ends the range and goes on in the one around it; a thrown value is the error of the result.

import engine.swf

pub type Activation:
	block i64
	pool i64 = -1
	stack Value[] = []
	registers Value[] = []
	scope Handle<Scope>
	me Value   # this
	target Handle<swf.Node>   # the node SetTarget aims the timeline actions at
	base Handle<swf.Node>   # the node the code runs in
	superBase Handle<Obj>? = none   # the prototype `super` looks past
	arguments Handle<Obj>? = none   # the arguments array, none when not made
	callee Value = .Undefined

# the most actions the queue runs at once: a script stuck in a loop is stopped there
stepBudget = 20_000_000

pub type Flow:
	Next
	Jump(to i64)
	Return(v Value)

pub fn pop(mut a Activation) Value:
	a.stack.pop() ?? .Undefined

# the value on top of the stack, left there
pub fn top(a Activation) Value:
	if a.stack.last is v: return v.copy()
	.Undefined

pub fn push(mut a Activation, move v Value):
	a.stack.push(v)

fn popNumber(prog Program, mut m Machine, mut a Activation) f64 ? Thrown:
	v = a.pop()
	try prog.toNumber(m, v)

fn popText(prog Program, mut m Machine, mut a Activation) str ? Thrown:
	v = a.pop()
	try prog.toText(m, v)

# the arguments a call pops: their count, then each, the first on top
pub fn popArgs(prog Program, mut m Machine, mut a Activation) Value[] ? Thrown:
	n = toInt32(try prog.popNumber(m, a)).clamp(0, 255)
	args = []
	loop n:
		args.push(a.pop())
	args

# runs actions from .. to of the activation's block
pub fn execRange(prog Program, mut m Machine, mut a Activation, from i64, to i64) Flow ? Thrown:
	pc = from
	block = ref prog.blocks[a.block]
	while pc < to and pc < block.actions.len:
		m.steps += 1
		if m.steps > stepBudget: return Thrown(.Str("a script ran past {stepBudget} actions"))
		at = pc
		pc += 1
		flow = try prog.step(m, a, block.actions[at], at)
		match flow:
			Next: pass
			Jump(t):
				if t < from or t > to: return Flow.Jump(t)
				pc = t
			Return: return flow
	Flow.Next

# long: the dispatch of the actions with data, one arm each
fn step(prog Program, mut m Machine, mut a Activation, action Action, at i64) Flow ? Thrown:
	match action:
		Op(code): return prog.op(m, a, code)
		Push(items):
			for item in items:
				a.push(prog.pushed(a, item))
		ConstantPool: a.pool = at
		StoreRegister(r):
			v = a.top()
			if r < a.registers.len: a.registers[r] = v
		Jump(to): return Flow.Jump(to)
		If(to):
			if a.pop().isTrue(): return Flow.Jump(to)
		Function(def):
			prog.defineFunction(m, a, def, at)
			return Flow.Jump(def.end)
		With(end):
			object = a.pop()
			return try prog.runWith(m, a, object, at + 1, end)
		Try(def): return try prog.runTry(m, a, def, at + 1)
		GotoFrame(frame): prog.gotoFrame(m, a.target, frame, false)
		GotoLabel(label): prog.gotoLabel(m, a.target, label, false)
		GotoFrame2(play, bias):
			frame = a.pop()
			try prog.gotoValue(m, a, frame, play, bias)
		SetTarget(name): a.target = prog.targetNode(m, a, name) ?? a.base
		GetUrl(url, target): prog.getUrl(m, url, target)
		GetUrl2:
			target = try prog.popText(m, a)
			url = try prog.popText(m, a)
			prog.getUrl(m, url, target)
		WaitForFrame, WaitForFrame2:
			if action is WaitForFrame2: a.pop()
		Call:
			frame = a.pop()
			try prog.callFrame(m, a, frame)
		Unknown(code, _): m.missing(actionName(code))
	Flow.Next

# the value a Push item stands for
fn pushed(prog Program, a Activation, item PushItem):
	match item:
		Text(s): Value.Str(s.copy())
		Number(x): Value.Num(x)
		Null: Value.Null
		Undefined: Value.Undefined
		Register(r): a.registers[r].copy() if r < a.registers.len else .Undefined
		Boolean(b): Value.Bool(b)
		Constant(k): prog.poolText(a, k)

fn poolText(prog Program, a Activation, k i64):
	if a.pool < 0: return Value.Undefined
	if prog.blocks[a.block].actions[a.pool] is ConstantPool(items):
		if k < items.len: return .Str(items[k].copy())
	.Undefined

# DefineFunction: a function value made over the activation's scope chain, defined by its name
# or pushed when it has none
fn defineFunction(prog Program, mut m Machine, mut a Activation, def FunctionDef, at i64):
	f = ScriptFn(block = a.block, at, pool = a.pool, scope = a.scope, base = a.base)
	id = m.newOf(m.protos.function, .Function(f))
	proto = m.newObject(m.protos.object)
	m.define(proto, "constructor", .Obj(id), dontEnum)
	m.define(id, "prototype", .Obj(proto), dontEnum)
	if def.name.isEmpty:
		a.push(.Obj(id))
		return
	prog.defineLocal(m, a, def.name, .Obj(id))

# a with block: its object first in the scope chain while it runs
fn runWith(
	prog Program,
	mut m Machine,
	mut a Activation,
	object Value,
	from i64,
	end i64
) Flow ? Thrown:
	id = prog.toObject(m, object) ?? return Flow.Jump(end)
	saved = a.scope
	a.scope = m.newScope(saved, within, id)
	flow = prog.execRange(m, a, from, end)
	a.scope = saved
	result = try flow
	if result is Next: return Flow.Jump(end)
	result

# try, catch and finally: a value thrown in the try block goes to the catch block when there is
# one, the finally block runs after either, and a value thrown and not caught goes on after it
fn runTry(prog Program, mut m Machine, mut a Activation, def TryDef, from i64) Flow ? Thrown:
	result = prog.execRange(m, a, from, def.tryEnd)
	caught Value? = match result:
		error: error.value.copy()
		_: none
	if def.hasCatch:
		if caught is thrown:
			if def.catchRegister >= 0:
				if def.catchRegister < a.registers.len:
					a.registers[def.catchRegister] = thrown.copy()
			else:
				prog.defineLocal(m, a, def.catchName, thrown.copy())
			result = prog.execRange(m, a, def.tryEnd, def.catchEnd)
	if def.hasFinally:
		after = try prog.execRange(m, a, def.catchEnd, def.finallyEnd)
		match after:
			Next: pass
			_: return after
	flow = try result
	if flow is Next: return Flow.Jump(def.finallyEnd)
	flow

# GetURL and GetURL2: "FSCommand:name" with its argument goes to the game; other URLs are logged
fn getUrl(prog Program, mut m Machine, url str, target str):
	if url.lower().startsWith("fscommand:"):
		m.external.push(
			ExternalCall(name = "fscommand:{url[10..]}", args = [.Str(target.copy())])
		)
		return
	m.log.push("getURL {url} {target}")

# Call: the actions of a frame of the target clip run now
fn callFrame(prog Program, mut m Machine, mut a Activation, frame Value) () ? Thrown:
	n = a.target
	if n not in m.stage.nodes: return
	f = try prog.frameOfValue(m, n, frame) ?? return
	blocks = (prog.frameBlocks.get((m.stage.nodes[n].placed.character << 24) | f) ?? return).copy()
	for b in blocks:
		try prog.runBlock(m, b, n)

# GotoFrame2: a frame number (from 1) or a label, plus the scene bias
fn gotoValue(
	prog Program,
	mut m Machine,
	mut a Activation,
	frame Value,
	play bool,
	bias i64
) () ? Thrown:
	n = a.target
	if frame is Str(s):
		if ":" in s:
			parts = s.split(":")
			n = prog.targetNode(m, a, parts[0]) ?? return
			return try prog.gotoValue(m, a, .Str(parts[1].copy()), play, bias)
	f = try prog.frameOfValue(m, n, frame) ?? return
	prog.gotoFrame(m, n, f + bias, play)

# a frame given as a number from 1 or a label: its index from 0
pub fn frameOfValue(prog Program, mut m Machine, n Handle<swf.Node>, frame Value) (i64?) ? Thrown:
	if frame is Str(s):
		number = textNumber(s)
		if isNaN(number):
			node = m.stage.nodes.get(n) ?? return none
			t = prog.scene.timelineOf(node.placed.character) ?? return none
			return t.frameOfLabel(s)
		return i64(number) - 1
	i64(try prog.toNumber(m, frame)) - 1

pub fn gotoLabel(prog Program, mut m Machine, n Handle<swf.Node>, label str, play bool):
	node = m.stage.nodes.get(n) ?? return
	t = prog.scene.timelineOf(node.placed.character) ?? return
	f = t.frameOfLabel(label) ?? return
	prog.gotoFrame(m, n, f, play)

# the node shows frame f (from 0) and plays or stops; the frame's code is queued
pub fn gotoFrame(prog Program, mut m Machine, n Handle<swf.Node>, f i64, play bool):
	if n not in m.stage.nodes: return
	count = m.stage.frameCount(prog.scene, n)
	m.stage.nodes[n].playing = play
	target = f.clamp(0, count - 1)
	if target != m.stage.nodes[n].frame: m.stage.showFrame(prog.scene, n, target)
	match prog.takeStageChanges(m, none):
		error: m.fault("taking the stage's changes: {prog.describe(m, error.value)}")
		_: pass

# a block run now with the node as its target and `this`, its scope the node's
pub fn runBlock(prog Program, mut m Machine, b i64, n Handle<swf.Node>) () ? Thrown:
	if n not in m.stage.nodes: return
	me = m.objectOfNode(prog, n)
	scope = m.newScope(m.globalScope, target, me)
	a = Activation(
		block = b,
		registers = fill(4, .Undefined),
		scope,
		me = .Obj(me),
		target = n,
		base = n)
	saved = m.library
	m.library = prog.libraries[b]
	flow = prog.execRange(m, a, 0, prog.blocks[b].actions.len)
	m.library = saved
	try flow
