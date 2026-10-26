# The daemon's config (where it listens, the repository whose board it runs, how many agents may
# work at once) and its token, kept in the state dir; written with the defaults the first time.

import cards
import fs
import win

pub defaultPort = 7781

pub type Config:
	host str   # the interface listened on: the loopback one unless a client comes from elsewhere
	port i64
	repo str   # the main checkout of the repository whose board the agents work from
	limit i64 = 7   # agents working at once on this machine, the ones opened by hand included

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

# the config kept, or the defaults with the repository the daemon started in
pub fn loadConfig() Config:
	if fs.readFile(configPath()) is text:
		if Config.fromJson(text) is config: return config
	config = Config(
		host = "127.0.0.1",
		port = defaultPort,
		repo = cards.mainCheckout(currentDir().replace("\\", "/"))
	)
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
