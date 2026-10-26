# zaplink: the command line of the daemon's world (README.md). The board's cards: checked, the
# next one to take, taken by a branch (the agent's session named on the card).
#
#   zap run projects/zaplink/zaplink.zap board check
#   zap run projects/zaplink/zaplink.zap board next
#   zap run projects/zaplink/zaplink.zap board take <id>... [--branch name] [--by session]

import cards

args.options([
	ArgOption(name = "--branch", takesValue = true, help = "the branch that takes the cards (the first id's name)"),
	ArgOption(
		name = "--by",
		takesValue = true,
		help = "the agent's session id (Claude Code's own by default)"
	)
])
words = args.positional()
here = currentDir().replace("\\", "/")
usage = "usage: zaplink board check | next | take <id>... [--branch name] [--by session]"
if words.len < 2 or words[0] != "board": exit(2, "{usage}\n{args.usage()}")
command = words[1]
if command == "check":
	problems = cards.checkCards(here)
	for line in problems:
		print(line)
	if not problems.isEmpty: exit(1, "{problems.len} problems")
	found, _ = cards.loadCards(here)
	print("{found.len} cards, well formed")
elif command == "next":
	texts {str: str} = {}
	board = cards.readBoard(here, texts)
	ready = board.placed.find(.lane == .Ready) ?? exit(1, "no card is ready")
	print("{ready.card.id}  {ready.card.title}  ({ready.card.size})  {ready.card.path}")
elif command == "take" and words.len > 2:
	ids = words[2..]
	branch = args.option("--branch") ?? ids[0]
	by = args.option("--by") ?? (env.get("CLAUDE_CODE_SESSION_ID") ?? "")
	tree = cards.takeCards(cards.mainCheckout(here), ids, branch, by) ?? exit(1, error.why)
	print("{ids.join(", ")} taken by {branch}: {tree}")
else:
	exit(2, "{usage}\n{args.usage()}")
