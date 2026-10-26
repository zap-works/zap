# Waiting and sleeping as the player does them: PlayerCharacter::StartWaiting (0x1407414c0) and
# Actor::StartSleeping (0x140741370) set the seconds left, the hours chosen times 3600; each frame
# Actor::AdvanceSleepWaitTick (0x140749560) moves the clock on by iSecondsToSleepPerUpdate (900
# game seconds) and updates the actors as that time at the time scale passes in real seconds
# (their health, magicka and stamina regenerate); with none left 0x1407415a0 ends it and sends
# the sleep or the wait's stop event (the Rested spells are PlayerSleepQuestScript's, on
# OnSleepStop).

pub type SleepWait:
	sleeping bool
	secondsLeft f64

regenValues = ["health", "magicka", "stamina"]
regenRates = ["healrate", "magickarate", "staminarate"]

pub fn startSleepWait(mut w GameWorld, hours i64, sleeping bool):
	w.sleepWait = SleepWait(sleeping, secondsLeft = hours.max(0) * 3600)

# One frame of the wait or the sleep: the clock and the actors moved on; whether it ended now.
pub fn stepSleepWait(mut w GameWorld) bool:
	s = (w.sleepWait ?? return false).copy()
	step = f64(w.settings.gmst("isecondstosleepperupdate")).min(s.secondsLeft)
	w.daysPassed += step / 86400.0
	elapsed = f32(step / w.timeScale.max(1.0))
	for id in w.actors.keys().sorted():
		w.regenerate(id, elapsed)
	left = s.secondsLeft - step
	if left <= 0.0:
		w.sleepWait = none
		return true
	w.sleepWait = SleepWait(..s, secondsLeft = left)
	false

# the hours left of the wait or the sleep, as the menu's slider shows them (rounded up)
pub fn hoursLeft(w GameWorld) i64:
	s = w.sleepWait ?? return 0
	(i64(s.secondsLeft) + 3599) / 3600

# an actor's health, magicka and stamina regenerated over `seconds` of real time out of combat:
# its base and modifier times its rate (percent a second)
fn regenerate(mut w GameWorld, refId i64, seconds f32):
	a = (w.actors.get(refId) ?? return).copy()
	for i, name in regenValues:
		v = a.values.get(name) ?? continue
		amount = (v.base + v.modifier) * a.valueOf(regenRates[i]) / 100.0 * seconds
		if amount > 0.0: w.actors[refId].restoreNamed(name, amount)
