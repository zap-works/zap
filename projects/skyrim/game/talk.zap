# Talking to an actor in the scene, as the game runs a conversation. Activating the actor opens it
# with the actor's greeting (game/dialogue: a blocking branch's line, else the hello), the topics
# offered at once (the game's capture shows them beside the greeting); its lines are said one after
# the other, each as long as its voice file sounds (decoded; fDialogSpeechDelaySeconds without
# one), its voice and lip track given to `speak`. A topic chosen is answered the same way, the
# topics after it offered once the answer ends; a goodbye answer, or leaving, ends it. The actor
# holds its package meanwhile (IsInDialogueWithPlayer true for the conditions), one standing turned
# to the player over fDialogueRotationSecs, one at a marker going on at it; leaving lets it go on.
# The dialogue menu shows what a conversation keeps (interface/dialogueFeed.zap).

import game.dialogue
import game.sim
import math
import engine.physics
import skyrim
import skyrim
import world

pub type Phase:
	Greeting   # the greeting said, the topics offered beside it
	Choosing   # the topics offered, nothing said
	Answering   # a chosen topic's answer said, the topics put away
	Ended   # over: the menu closes

pub type Conversation:
	speaker i64   # the actor's reference
	name str   # its name
	phase Phase = .Greeting
	lines dialogue.Spoken[] = []   # what is being said
	line i64 = 0   # the line being said, lines.len once all are
	left f64 = 0.0   # seconds left of it
	spoken i64 = 0   # counts the lines begun
	answer dialogue.Line? = none   # the answer said last
	goodbye bool = false   # what is being said ends the conversation
	topics dialogue.MenuTopic[] = []
	listed i64 = 0   # counts the times the topics were offered
	chosen i64 = -1   # the index of the topic chosen last, -1 for none

# How long a line is said and its lip track: its voice file's sound decoded, else the setting's
# seconds with no track.
fn voiceOf(t dialogue.Talk, key str) (f64, skyrim.Lip?):
	silent = f64(t.vm.rt.world.settings.gmst("fdialogspeechdelayseconds"))
	install = t.vm.install ?? return (silent, none)
	if key.isEmpty: return (silent, none)
	match install.readVoice(key):
		v: (v.seconds, v.lip)
		error:
			eprint("dialogue: {error}")
			(silent, none)

fn startLine(mut c Conversation, t dialogue.Talk):
	if c.line >= c.lines.len: return
	key = c.lines[c.line].voice.copy()
	seconds, lip = t.voiceOf(key)
	speak(c.speaker, key, lip)
	c.left = seconds
	c.spoken += 1

# the INFO said: its lines begun, what it does done
fn sayLine(mut c Conversation, mut t dialogue.Talk, line dialogue.Line):
	said = t.say(c.speaker, line.info)
	c.lines = said.lines
	c.line = 0
	c.goodbye = said.goodbye
	c.startLine(t)

# The conversation the player opens by activating the actor: none when the actor is not one to talk
# to or has nothing to say.
pub fn startConversation(mut t dialogue.Talk, speaker i64) Conversation?:
	line = try t.activateActor(speaker)
	c = Conversation(speaker, name = (t.people.get(speaker)?.name ?? "").copy())
	c.sayLine(t, line)
	c.topics = t.menuAfter(speaker, line)
	c.listed = 1
	c

pub fn isSaying(c Conversation) bool:
	c.line < c.lines.len

# The text of the line being said, none between lines.
pub fn lineText(c Conversation) str?:
	if not c.isSaying(): return none
	c.lines[c.line].text.copy()

# The conversation's frame: the line being said goes on, the next begins as it ends; when the last
# ends the topics are offered again, or the conversation ends after a goodbye.
pub fn stepConversation(mut c Conversation, mut t dialogue.Talk, dt f32):
	if c.phase == .Ended or not c.isSaying(): return
	c.left -= f64(dt)
	if c.left > 0.0: return
	c.line += 1
	if c.isSaying():
		c.startLine(t)
		return
	if c.goodbye:
		c.endConversation(t)
		return
	if c.phase == .Answering:
		c.topics = t.menuAfter(c.speaker, c.answer ?? return)
		c.listed += 1
	c.phase = .Choosing

# The topic at the index of the topics offered chosen: its answer said, what was being said cut.
pub fn chooseTopic(mut c Conversation, mut t dialogue.Talk, index i64):
	if c.phase == .Ended or c.phase == .Answering or index < 0 or index >= c.topics.len: return
	topic = c.topics[index].topic
	line = t.respond(c.speaker, topic) ?? return
	c.chosen = index
	c.answer = line
	c.phase = .Answering
	c.sayLine(t, line)

# the line being said cut short, as a click on it does
pub fn skipLine(mut c Conversation):
	c.left = 0.0

# The conversation left: the actor no longer in dialogue with the player.
pub fn endConversation(mut c Conversation, mut t dialogue.Talk):
	c.phase = .Ended
	c.lines = []
	c.line = 0
	if t.partner == c.speaker: t.partner = 0

# the resident that is the world's actor reference, -1 for none in the scene
pub fn residentOf(rs Residents, cast world.CastHead, w sim.GameWorld, refId i64) i64:
	npc = (w.actors.get(refId) ?? return -1).npc
	rs.all.findIndex(cast.npcs[.npc].formId == npc) ?? -1

# The actor's package held while it talks to the player standing at `player` (its feet, Z up), or
# let go again: one walking stops where it is, one standing turns to the player within the
# setting's seconds.
pub fn holdForTalk(mut rs Residents, k i64, on bool, player Vec3, settings skyrim.IniSettings):
	if k < 0 or rs.all[k].talking == on: return
	rs.all[k].talking = on
	if not on: return
	if rs.all[k].doing == .Walking:
		rs.free(k)
		rs.all[k].doing = .Standing
		rs.all[k].until = 0.0
	away = math.angleBetween(rs.all[k].body.heading, rs.headingTo(k, player)).abs()
	seconds = f32(settings.iniNumber("fDialogueRotationSecs:Dialogue")).max(0.01)
	rs.all[k].turnRate = (away / seconds).max(0.01)

fn headingTo(rs Residents, k i64, at Vec3) f32:
	to = at - rs.all[k].body.feetOf()
	to.x.atan2(to.y)

# A talking actor's frame: standing, it turns to the player; at a marker it goes on at it without
# leaving; going in or out of one, it finishes that.
fn holdTalking(
	mut rs Residents,
	cast world.CastHead,
	k i64,
	timeScale f32,
	player Vec3,
	mut w physics.World,
	dt f32
):
	match rs.all[k].doing:
		Standing:
			rs.all[k].clock += dt
			heading = math.turnToward(rs.all[k].body.heading, rs.headingTo(k, player),
				rs.all[k].turnRate * dt)
			rs.all[k].body.heading = heading
			rs.all[k].body.steerPlayer(still(), heading, w, dt)
		Using: rs.all[k].clock += dt
		_: rs.act(cast, k, timeScale, w, dt)
