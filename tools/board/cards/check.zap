# What is wrong with a checkout's cards: the files that are no card, two cards of one id, a need
# that names no card open or landed, and needs that wait on each other in a circle.

# the problems of the cards under root/board, each a line naming its file
pub fn checkCards(root str) str[]:
	cards, problems = loadCards(root)
	ids = cards.map(.id.copy())
	landed = landedIds(root)
	for i, card in cards:
		if card.id in ids[..i]: problems.push("{card.path}: a second card {card.id}")
		for need in card.needs:
			if need == card.id: problems.push("{card.path}: needs itself")
			elif need not in ids and need not in landed:
				problems.push("{card.path}: needs {need}, which is no card, open or landed")
	for card in cards:
		seen = []
		if waitsOnItself(cards, card.id, card.id, seen):
			problems.push("{card.path}: its needs come back to it")
	problems

# whether `from`'s needs lead back to `target` (seen: the ids already followed)
fn waitsOnItself(cards Card[], from str, target str, mut seen str[]) bool:
	card = cards.find(.id == from) ?? return false
	for need in card.needs:
		if need == target: return true
		if need in seen: continue
		seen.push(need.copy())
		if waitsOnItself(cards, need, target, seen): return true
	false
