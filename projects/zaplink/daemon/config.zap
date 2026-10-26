# The daemon's config (where it listens, the repository whose board it runs, how many agents may
# work at once) and its token, kept in the state dir; written with the defaults the first time.

import agents
import cards
import fs
import json
import win

pub defaultPort = 7781

pub type Config:
	host str   # the interface listened on: the loopback one unless a client comes from elsewhere
	port i64
	repo str   # the main checkout of the repository whose board the agents work from
	settings agents.Settings = agents.Settings()

	fn save():
		_ = fs.createDir(stateDir())
		_ = fs.writeFile(configPath(), self.toJson())

# where zaplink keeps its token, its config and its agents
pub fn stateDir() str:
	fs.join(env.get("LOCALAPPDATA") ?? currentDir(), "zaplink")

fn configPath():
	fs.join(stateDir(), "config.json")

fn tokenPath():
	fs.join(stateDir(), "token")

# the config kept, each key it lacks at its default (the repository the daemon started in); a
# config of an older shape keeps what it names
pub fn loadConfig() Config:
	config = Config(
		host = "127.0.0.1",
		port = defaultPort,
		repo = cards.mainCheckout(currentDir().replace("\\", "/"))
	)
	text = fs.readFile(configPath()) ?? ""
	if json.parse(text) is doc:
		r = doc.root
		if doc.textOf(r, "host") != "": config.host = doc.textOf(r, "host").copy()
		config.port = i64(doc.number(r, "port") ?? f64(config.port))
		if doc.textOf(r, "repo") != "": config.repo = doc.textOf(r, "repo").copy()
		if doc.get(r, "settings") is kept:
			out = []
			doc.write(kept, out)
			config.settings = config.settings.changedBy(str(out))
	config.save()
	config

# the token a client must give: the one kept, or a new one written for the clients of this user
pub fn loadToken() str:
	if fs.readFile(tokenPath()) is kept:
		if kept.trimmed().len >= 32: return kept.trimmed().copy()
	token = win.secureRandom(16).map("{it:02x}").join("")
	_ = fs.createDir(stateDir())
	_ = fs.writeFile(tokenPath(), token)
	token
