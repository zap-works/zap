# The client of a live page (live.zap), the script the page carries: written by hand until the JS
# target (compiler-23) writes it from Zap. It opens the page's WebSocket and applies the patches
# that come (encoded()'s, `patched` in Zap; "l" reloads the page, as a socket the server no longer
# knows asks), and sends as JSON lists of strings what the viewer does: a click on an element with
# `event="name:value"` ["click", name, value], a link to this site followed (the address changed by
# history.pushState) or the back button ["nav", path and query], a submitted form with
# `event="name"` ["submit", name, field, value, ...] (then reset), a key pressed in an element with
# `keys="name"` ["key", name, key, the element's value]. A socket that closes is opened again
# after a second.
clientScript = r"""
	(() => {
	const me = document.currentScript.dataset.zapx, here = () => location.pathname + location.search;
	let ws = null;
	const send = m => ws && ws.readyState === 1 && ws.send(JSON.stringify(m));
	const at = p => p.reduce((n, i) => n.childNodes[i], { childNodes: [document.documentElement] });
	const make = h => { const t = document.createElement("template"); t.innerHTML = h; return t.content.firstChild; };
	const prop = (n, k, v) => {
		if (k === "value" && "value" in n) n.value = v ?? "";
		else if ((k === "checked" || k === "selected") && k in n) n[k] = v !== null;
	};
	function order(n, slots) {
		const old = [...n.childNodes], kids = [];
		for (const s of slots) {
			if (typeof s === "string") kids.push(make(s));
			else if (typeof s === "number") kids.push(old[s]);
			else for (let i = s[0]; i <= s[1]; i++) kids.push(old[i]);
		}
		kids.forEach((k, i) => { if (n.childNodes[i] !== k) n.insertBefore(k, n.childNodes[i] || null); });
		while (n.childNodes.length > kids.length) n.lastChild.remove();
	}
	function apply(patches) {
		for (const [op, path, a, b] of patches) {
			if (op === "l" || !path.length) return location.reload();
			const n = at(path);
			if (op === "o") order(n, a);
			else if (op === "t") n.data = a;
			else if (op === "a") { n.setAttribute(a, b); prop(n, a, b); }
			else if (op === "r") { n.removeAttribute(a); prop(n, a, null); }
			else if (op === "h") n.innerHTML = a;
		}
	}
	function connect() {
		ws = new WebSocket((location.protocol === "https:" ? "wss://" : "ws://") + location.host + "/zapx-live?s=" + me);
		ws.onmessage = m => apply(JSON.parse(m.data));
		ws.onclose = () => setTimeout(connect, 1000);
	}
	document.addEventListener("click", e => {
		const el = e.target.closest("[event]");
		if (el && el.tagName !== "FORM") {
			e.preventDefault();
			const v = el.getAttribute("event"), i = v.indexOf(":");
			return send(["click", i < 0 ? v : v.slice(0, i), i < 0 ? "" : v.slice(i + 1)]);
		}
		const a = e.target.closest("a[href]");
		if (!a || a.origin !== location.origin || a.target || e.button || e.ctrlKey || e.metaKey || e.shiftKey) return;
		if (a.pathname + a.search === here() && a.hash) return;
		e.preventDefault();
		history.pushState(null, "", a.href);
		send(["nav", here()]);
	});
	addEventListener("popstate", () => send(["nav", here()]));
	document.addEventListener("submit", e => {
		const f = e.target.closest("[event]");
		if (!f) return;
		e.preventDefault();
		send(["submit", f.getAttribute("event"), ...[...new FormData(f)].flatMap(([k, v]) => [k, String(v)])]);
		f.reset();
	});
	document.addEventListener("keydown", e => {
		const el = e.target.closest && e.target.closest("[keys]");
		if (el) send(["key", el.getAttribute("keys"), e.key, e.target.value ?? ""]);
	});
	connect();
	})();
	"""
