# The access codes of the 120 levels, by the scheme Herman Perk worked out from the DOS game
# (as Lemmini's LevelCode has it): ten letters, a seed plus the level, the percent saved and a
# "magic" spread over the first seven in nibbles, those seven rotated by the level, the level's
# two nibbles on the 8th and 9th and a checksum on the 10th. The level is the index over the
# four ratings (Fun 1 is 0), the percent what the player saved on the level before.

seed = "AJHLDHBBCJ"
codeLength = 10
magicMask = [1, 2, 4, 24, 32, 64, 0]
magicLeft = [1, 2, 0, 0, 0, 0, 0]
magicRight = [0, 0, 2, 1, 5, 5, 0]
levelLeft = [3, 1, 0, 0, 0, 0, 0]
levelRight = [0, 0, 0, 3, 3, 5, 4]
percentLeft = [2, 0, 0, 0, 0, 0, 0]
percentRight = [0, 1, 1, 2, 1, 3, 6]

seedCodes = seed.chars().map(.charCode())

# the nibble `i` carries: the three fields' bits placed
fn nibble(i i64, level i64, percent i64, magic i64):
	bit = 1 << i
	(((magic & magicMask[i]) << magicLeft[i]) >> magicRight[i]) +
		(((level & bit) << levelLeft[i]) >> levelRight[i]) +
		(((percent & bit) << percentLeft[i]) >> percentRight[i])

# the code of a level (0..119) after saving `percent` on the one before
pub fn accessCode(level i64, percent i64, magic i64 = 0) str:
	letters = seedCodes
	out i64[10]
	sum = 0
	for i in 0..7:
		letters[i] = (letters[i] + nibble(i, level, percent, magic)) & 255
		out[(i + 8 - level % 8) % 7] = letters[i]
		sum += letters[i]
	out[7] = (letters[7] + (level & 15)) & 255
	out[8] = (letters[8] + ((level & 240) >> 4)) & 255
	sum += (out[7] + out[8]) & 255
	out[9] = (letters[9] + (sum & 15)) & 255
	out.map(str.fromCode(it)).join("")

# the level (0..119) a code names, none for a code the scheme does not make
pub fn levelOfCode(code str) i64?:
	if code.len != codeLength: return none
	letters = code.upper().chars().map(.charCode())
	level = ((letters[7] - seedCodes[7]) & 15) + (((letters[8] - seedCodes[8]) & 15) << 4)
	unrotated i64[7]
	for i in 0..7:
		unrotated[(i + 6 + level % 8) % 7] = letters[i]
	levelBack = 0
	percent = 0
	for i in 0..7:
		n = (unrotated[i] - seedCodes[i]) & 255
		levelBack += ((n << levelRight[i]) >> levelLeft[i]) & (1 << i)
		percent += ((n << percentRight[i]) >> percentLeft[i]) & (1 << i)
	if level != levelBack or percent > 100 or level >= 120: return none
	level

test "codes the DOS game gives come out of the scheme and back":
	expect accessCode(2, 100) == "NJLDLCADCY"
	expect accessCode(33, 96, 1) == "KJHLDMCCEO"
	expect accessCode(90, 100) == "NJMFLGALHM"
	expect (levelOfCode("NJMFLGALHM") ?? -1) == 90
	expect (levelOfCode("njldlcadcy") ?? -1) == 2
	expect levelOfCode("AAAAAAAAAA") == none
	for level in 0..120:
		expect (levelOfCode(accessCode(level, 73)) ?? -1) == level
