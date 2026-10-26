# How long an attack takes and when it lands: the clip's length and its "HitFrame" (the trigger the
# behavior graph's clip generator sends), both divided by the weapon's speed (WEAP DNAM), at which
# the graph plays the clip. They are measured by running the game's behavior graph with the events
# a fight sends (fightClips.zap in game), so no clip is named here.

# the behavior graph's events a strike sends (the ATKE names the race's attack data is keyed by)
pub attackEvent = "attackStart"
pub powerEvent = "attackPowerStartForward"
pub fistsPowerEvent = "attackPowerStartForwardH2HRightHand"
pub bashEvent = "bashStart"

# the event that starts a power attack: fists have their own
pub fn powerEventOf(fists bool) str:
	fistsPowerEvent if fists else powerEvent

pub type AttackTime:
	duration f32   # seconds at speed 1
	hit f32   # when it lands, seconds at speed 1

# the attacks of one hand: two plain ones in turn, a power attack
pub type Moveset:
	normal AttackTime[]
	power AttackTime

# how long the stagger clip lasts at each value of the graph's staggerMagnitude blend (the places
# of the blend's clips, rising)
pub type Staggers:
	magnitudes f32[]
	lengths f32[]

# the nearest the graph's blend goes to a stagger of this magnitude: inside the places it blends
pub fn clampMagnitude(s Staggers, magnitude f32) f32:
	if s.magnitudes.isEmpty: return magnitude
	magnitude.clamp(s.magnitudes[0], s.magnitudes[len - 1])

# the clip's length at the magnitude, the blend of the two lengths either side of it
pub fn lengthAt(s Staggers, magnitude f32) f32:
	if s.lengths.isEmpty: return 0.0
	m = s.clampMagnitude(magnitude)
	for k in 1..s.magnitudes.len:
		if m <= s.magnitudes[k]:
			span = (s.magnitudes[k] - s.magnitudes[k - 1]).max(1.0e-6)
			share = (m - s.magnitudes[k - 1]) / span
			return s.lengths[k - 1] + (s.lengths[k] - s.lengths[k - 1]) * share
	s.lengths[len - 1]

pub type Timings:
	armed Moveset
	unarmed Moveset
	bash AttackTime
	staggers Staggers
	castIntros f32[] = []   # the graph's wind-up of each kind of cast, by its place (fightMagic.zap)
