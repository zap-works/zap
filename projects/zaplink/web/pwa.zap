# What makes the page installable on a phone: the manifest, the icon and the service worker, and
# the script that turns an agent's change of state into a notice.

manifest = r"""
	{
		"name": "zaplink",
		"short_name": "zaplink",
		"start_url": "/",
		"scope": "/",
		"display": "standalone",
		"background_color": "#09090b",
		"theme_color": "#09090b",
		"icons": [{"src": "/icon.svg", "sizes": "any", "type": "image/svg+xml", "purpose": "any maskable"}]
	}
	"""

icon = r"""
	<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
		<rect width="512" height="512" fill="#09090b"/>
		<path d="M136 144h240l-170 224h170v0H136l170-224H136z" fill="#2dd4bf"/>
	</svg>
	"""

# the notice of an agent comes from the page (showNotification), so the worker only has to take
# the viewer back to the page when the notice is tapped
worker = r"""
	self.addEventListener("install", () => self.skipWaiting());
	self.addEventListener("activate", e => e.waitUntil(self.clients.claim()));
	self.addEventListener("fetch", () => {});
	self.addEventListener("notificationclick", e => {
		e.notification.close();
		const url = e.notification.data || "/";
		e.waitUntil(self.clients.matchAll({ type: "window" }).then(all => {
			for (const c of all) if ("focus" in c) { c.navigate(url); return c.focus(); }
			return self.clients.openWindow(url);
		}));
	});
	"""

# the content type and text of an asset, "" for a path that is none
pub fn asset(path str) Tuple2<str, str>:
	if path == "/manifest.webmanifest": return ("application/manifest+json", manifest.copy())
	if path == "/icon.svg": return ("image/svg+xml", icon.copy())
	if path == "/sw.js": return ("text/javascript", worker.copy())
	("", "")

# registers the worker and, once the viewer turns notices on (a tap, the browser asks only then),
# tells when an agent ends a turn and waits, or stops, while the page is hidden or shows another
# agent; the agents come from /agents.json, as the page's own poll reads them
pub noticeScript = r"""
	let worker = null, known = null;
	if ("serviceWorker" in navigator) navigator.serviceWorker.register("/sw.js").then(r => worker = r).catch(() => {});
	const noticeText = () =>
		!("Notification" in window) ? "Notices are not supported here" :
		Notification.permission === "granted" ? "Notices are on" :
		Notification.permission === "denied" ? "Notices are blocked in the browser" : "Turn notices on";
	function announce(a, state) {
		const title = a.name + (state === "Stopped" ? " stopped" : " is waiting for you");
		const options = { body: a.card || a.prompt.slice(0, 80), tag: a.id, data: "/?view=agents&agent=" + a.id };
		if (worker) worker.showNotification(title, options);
		else new Notification(title, options);
	}
	async function watch() {
		if (!("Notification" in window) || Notification.permission !== "granted") return;
		try {
			const { agents } = await (await fetch("/agents.json")).json();
			const now = {};
			for (const a of agents) {
				const state = a.state.$tag, before = known && known[a.id];
				now[a.id] = state;
				const ended = state === "Stopped" || (state === "Idle" && before === "Working");
				if (before && before !== state && ended && (document.hidden || a.id !== live)) announce(a, state);
			}
			known = now;
		} catch (e) {}
	}
	// the controls are made again on each change of the agents, so the button is found each time
	function showNotice() {
		const button = document.getElementById("notify");
		if (button && button.textContent !== noticeText()) button.textContent = noticeText();
	}
	document.addEventListener("click", async e => {
		if (!e.target.closest("#notify")) return;
		if ("Notification" in window && Notification.permission === "default") await Notification.requestPermission();
		showNotice();
	});
	setInterval(showNotice, 500);
	setInterval(watch, 2000);
	"""
