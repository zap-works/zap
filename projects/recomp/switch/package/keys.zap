# The console's keys as Lockpick writes them (prod.keys: `name = hex` a line) and the title keys
# (title.keys: `rights id = key`). They are the player's own, read where the player keeps them
# and never copied into the project.

import cipher
import fs

pub type Keys:
	named {str: u8[]} = {}
	titles {str: u8[]} = {}

	# a ticket's title key (its common form, sealed by the titlekek of its generation) kept by its
	# rights id
	fn addTicket(ticket u8[]) ? str:
		if ticket.len < 0x2B0: return "the ticket is cut short"
		rights = ticket[0x2A0..0x2B0].map("{it:02x}").join("")
		gen = i64(ticket[0x285])
		kek = try get("titlekek_{generationName((gen - 1).max(0))}")
		titles[rights] = cipher.aes128(kek).decryptEcb(ticket[0x180..0x190].copy())

	# the key of this name, or why it is missing
	fn get(name str) u8[] ? str:
		(
			named.get(name) ??
				return "prod.keys has no {name}: dump the keys again with Lockpick_RCM on the console"
		).copy()

# every `name = hex` line of a keys file, the names lowercase
fn keyLines(text str):
	out {str: u8[]} = {}
	for line in text.lines():
		at = line.indexOf("=") ?? continue
		name = line[..at].trimmed().lower()
		if cipher.fromHex(line[at + 1..].trimmed()) is bytes: out[name] = bytes
	out

# The keys in dir (prod.keys, and title.keys when there), or a message that says what to do.
pub fn readKeys(dir str) Keys ? str:
	prod = fs.join(dir, "prod.keys")
	text = fs.readFile(prod) ?? return "no {prod}: the keys are the console's own; dump them with Lockpick_RCM and put prod.keys beside the game"
	titles = keyLines(fs.readFile(fs.join(dir, "title.keys")) ?? "")
	Keys(named = keyLines(text), titles)

# a key generation's two hexadecimal digits, as the keys' names end
pub fn generationName(n i64) str:
	"{n:02x}"
