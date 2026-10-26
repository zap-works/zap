# The natives of forms over the GameWorld: Game's lookups, a form's id and update registrations,
# a reference's enabled state and position, quests' stages and global variables. Anything else
# falls to the stub (natives.zap).

import game.sim
import game.stealth

fn formOf(rt Runtime, c NativeCall):
	rt.objects[c.me].form

# RegisterForUpdate and its kin: real seconds, or game hours kept as days
fn register(mut rt Runtime, c NativeCall, repeat bool, gameTime bool) Value:
	rt.unregister(c, gameTime)
	amount = f64(c.arg(0).asFloat())
	span = amount / 24.0 if gameTime else amount
	now = rt.world.daysPassed if gameTime else rt.time
	rt.updates.push(
		Update(object = c.me, at = now + span, interval = span if repeat else 0.0, gameTime)
	)
	.None

fn unregister(mut rt Runtime, c NativeCall, gameTime bool) Value:
	k = rt.updates.len - 1
	while k >= 0:
		if rt.updates[k].object == c.me and rt.updates[k].gameTime == gameTime: rt.updates.remove(k)
		k -= 1
	.None

fn setEnabled(mut rt Runtime, c NativeCall, enabled bool) Value:
	form = rt.formOf(c)
	rt.world.addForm(form)
	rt.world.forms[form].enabled = enabled
	.None

fn isEnabled(rt Runtime, c NativeCall):
	match rt.world.forms.get(rt.formOf(c)):
		f: f.enabled
		none: true

fn position(rt Runtime, c NativeCall, axis i64) Value:
	match rt.world.forms.get(rt.formOf(c)):
		f: .Float([f.x, f.y, f.z][axis])
		none: .Float(0.0)

# ObjectReference.CreateDetectionEvent(akOwner, aiSoundLevel): a noise at the reference's place that
# the owner made, at the sound level given as it is (0x140a451f0)
fn createDetectionEvent(mut rt Runtime, c NativeCall) Value:
	owner = rt.formArg(c, 0)
	f = rt.world.forms.get(rt.formOf(c)) ?? return .None
	if owner == 0: return .None
	rt.world.createEvent(owner, Vec3(f.x, f.y, f.z), c.arg(1).asInt(), rt.formOf(c))
	.None

fn setPosition(mut rt Runtime, c NativeCall) Value:
	form = rt.formOf(c)
	rt.world.addForm(form)
	rt.world.forms[form].x = c.arg(0).asFloat()
	rt.world.forms[form].y = c.arg(1).asFloat()
	rt.world.forms[form].z = c.arg(2).asFloat()
	.None

fn baseObject(lib Library, mut rt Runtime, c NativeCall) Value:
	base = (rt.world.forms.get(rt.formOf(c)) ?? return .None).base
	.Object(lib.objectFor(rt, base, "form"))

fn setStage(mut rt Runtime, c NativeCall) Value:
	quest = rt.formOf(c)
	stage = c.arg(0).asInt()
	rt.world.setStage(quest, stage)
	rt.note("quest {quest:08X} stage {stage}")
	.Bool(true)

fn stageDone(rt Runtime, c NativeCall) Value:
	.Bool(rt.world.isStageDone(rt.formOf(c), c.arg(0).asInt()))

fn setRunning(mut rt Runtime, c NativeCall, running bool) Value:
	rt.world.runningQuests[rt.formOf(c)] = running
	.Bool(true) if c.returnType.lower() == "bool" else .None

fn setGlobal(mut rt Runtime, c NativeCall) Value:
	rt.world.globals[rt.formOf(c)] = c.arg(0).asFloat()
	.None

# long: the table of the forms' natives, one arm per function
# a native of the game's forms, or the stub
pub fn formNative(lib Library, mut rt Runtime, c NativeCall) Value:
	match c.key:
		"game.getplayer": .Object(lib.objectFor(rt, rt.world.player, "actor"))
		"game.getform": .Object(lib.objectFor(rt, c.arg(0).asInt(), "form"))
		"form.getformid": .Int(rt.formOf(c))
		"form.registerforupdate", "alias.registerforupdate", "activemagiceffect.registerforupdate": rt.register(
			c,
			true,
			false
		)
		"form.registerforsingleupdate", "alias.registerforsingleupdate", "activemagiceffect.registerforsingleupdate": rt.register(
			c,
			false,
			false
		)
		"form.unregisterforupdate", "alias.unregisterforupdate", "activemagiceffect.unregisterforupdate": rt.unregister(
			c,
			false
		)
		"form.registerforupdategametime", "alias.registerforupdategametime", "activemagiceffect.registerforupdategametime": rt.register(
			c,
			true,
			true
		)
		"form.registerforsingleupdategametime", "alias.registerforsingleupdategametime", "activemagiceffect.registerforsingleupdategametime": rt.register(
			c,
			false,
			true
		)
		"form.unregisterforupdategametime", "alias.unregisterforupdategametime", "activemagiceffect.unregisterforupdategametime": rt.unregister(
			c,
			true
		)
		"form.registerforsleep", "alias.registerforsleep", "activemagiceffect.registerforsleep":
			if c.me not in rt.sleepers: rt.sleepers.push(c.me)
			.None
		"form.unregisterforsleep", "alias.unregisterforsleep", "activemagiceffect.unregisterforsleep":
			rt.sleepers = rt.sleepers.filter(it != c.me)
			.None
		"message.show":
			rt.world.shownMessages.push(rt.meForm(c))
			.Int(0)
		"objectreference.enable": rt.setEnabled(c, true)
		"objectreference.disable": rt.setEnabled(c, false)
		"objectreference.isdisabled": .Bool(not rt.isEnabled(c))
		"objectreference.getbaseobject": lib.baseObject(rt, c)
		"objectreference.getpositionx": rt.position(c, 0)
		"objectreference.getpositiony": rt.position(c, 1)
		"objectreference.getpositionz": rt.position(c, 2)
		"objectreference.setposition": rt.setPosition(c)
		"objectreference.createdetectionevent": rt.createDetectionEvent(c)
		"quest.getstage", "quest.getcurrentstageid": .Int(rt.world.stages.get(rt.formOf(c)) ?? 0)
		"quest.setstage", "quest.setcurrentstageid": rt.setStage(c)
		"quest.getstagedone": rt.stageDone(c)
		"quest.isrunning": .Bool(rt.world.runningQuests.get(rt.formOf(c)) ?? false)
		"quest.start": rt.setRunning(c, true)
		"quest.stop": rt.setRunning(c, false)
		"topicinfo.getowningquest":
			.Object(lib.objectFor(rt, rt.world.dialogueQuests.get(rt.formOf(c)) ?? 0, "quest"))
		"globalvariable.getvalue": .Float(rt.world.globals.get(rt.formOf(c)) ?? 0.0)
		"globalvariable.setvalue": rt.setGlobal(c)
		_: lib.referenceNative(rt, c)
