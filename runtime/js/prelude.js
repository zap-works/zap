// The JS target's prelude (compiler/targets/js/): what the runtime does over raw memory or the
// system, written for JS. A function here named as one of the runtime's (rt__name) takes its
// place; the module the compiler writes starts with this text. It runs under node and in a browser.

const rt$node = typeof process !== "undefined" && process.versions && process.versions.node;
const rt$fs = rt$node ? await import("node:fs") : null;

class rt__Err {
	constructor(e) { this.e = e; }
}

// a test the JS target cannot run: its function says why when the tests run
class rt$Skipped extends Error {}

function rt$skip(why) {
	throw new rt$Skipped(why);
}

class rt$Stop extends Error {
	constructor(code, message) { super(message); this.code = code; }
}

// the program stops on a bug as a native run does: its code and message (runtime/core/errors.zap's
// failTable) on stderr, exit code 3
function rt$stop(code, message) {
	throw new rt$Stop(code, message);
}

function rt$outOfBounds() { rt$stop("index-out-of-bounds", "index out of bounds"); }
function rt$overflow(why) { rt$stop("integer-overflow", "integer overflow: the result does not fit its type" + (why ? " (" + why + ")" : "")); }

function rt__fail(message) { rt$stop("failure", message); }

// ---------- output ----------

let rt$out = "";
let rt$buffered = true;   // while main runs: written at its end, or when full
let rt$capturing = false;
let rt$captured = "";

function rt$write(text, err) {
	if (err) {
		rt$flush();
		if (rt$fs) rt$fs.writeSync(2, text); else console.error(text);
		return;
	}
	if (rt$capturing) { rt$captured += text; return; }
	rt$out += text;
	if (rt$out.length > 65536 || !rt$buffered) rt$flush();
}

function rt$flush() {
	if (rt$out === "") return;
	if (rt$fs) rt$fs.writeSync(1, rt$out); else console.log(rt$out.replace(/\n$/, ""));
	rt$out = "";
}

function rt__printLine(text, err) {
	rt$write(text + "\n", err === 1 || err === true);
}

function rt__streamPrint(stream, text) {
	rt$write(text + "\n", stream.handle === 2);
}

// the program's start run: a stop reported as a native run reports it, its exit code 1
function rt$run(start) {
	try {
		start();
		rt$flush();
		rt$buffered = false;   // what callbacks print later (timers, events) goes out at once
		return;
	} catch (e) {
		if (e instanceof rt$Skipped) {
			rt__printLine(e.message, 0);
			rt__exit(0);
		}
		if (!(e instanceof rt$Stop)) throw e;
		rt__exit(3, "zap: error[" + e.code + "]: " + e.message);
	}
}

function rt__exit(code, message) {
	if (message !== undefined && message !== "") rt$write(message + "\n", true);
	rt$flush();
	if (rt$node) process.exit(code);
	throw new rt$Stop("exit", "exited with code " + code);
}

// ---------- numbers ----------

function rt__i64(x) {
	if (typeof x === "bigint") return BigInt.asIntN(64, x);   // a float's bits, carried as they are
	if (!Number.isSafeInteger(x)) rt$overflow("past 2^53 under the JS target");
	return x;
}

function rt__u64(x) {
	if (typeof x === "bigint") return BigInt.asUintN(64, x);
	if (!Number.isSafeInteger(x) || x < 0) rt$overflow("a u64 past 0..2^53 under the JS target");
	return x;
}

function rt__fitInt(x, bits) {
	const top = 2 ** (bits - 1);
	if (x < -top || x >= top) rt$overflow();
	return x;
}

function rt__wrapInt(x, bits, signed) {
	if (bits === 32) return signed ? x | 0 : x >>> 0;
	if (bits === 64) return signed ? rt__i64(x) : rt__u64(x);
	const m = 2 ** bits;
	let r = ((x % m) + m) % m;
	if (signed && r >= m / 2) r -= m;
	return r;
}

function rt__mulU(a, b, bits) {
	if (bits === 32) return Math.imul(a, b) >>> 0;
	return rt__wrapInt(a * b, bits, false);
}

function rt__div(a, b) {
	if (b === 0) rt$stop("division-by-zero", "division by zero");
	return Math.trunc(a / b);
}

function rt__mod(a, b) {
	if (b === 0) rt$stop("division-by-zero", "division by zero");
	const r = a % b;
	return r === 0 ? 0 : r;
}

function rt$big(a) { return BigInt.asIntN(64, BigInt(a)); }

function rt$fromBig(r, bits, signed) {
	r = signed ? BigInt.asIntN(bits, r) : BigInt.asUintN(bits, r);
	return Number(r);
}

function rt__band(a, b, bits, signed) {
	if (bits <= 32) return rt__wrapInt(a & b, bits, signed);
	return rt$fromBig(rt$big(a) & rt$big(b), bits, signed);
}

function rt__bor(a, b, bits, signed) {
	if (bits <= 32) return rt__wrapInt(a | b, bits, signed);
	return rt$fromBig(rt$big(a) | rt$big(b), bits, signed);
}

function rt__bxor(a, b, bits, signed) {
	if (bits <= 32) return rt__wrapInt(a ^ b, bits, signed);
	return rt$fromBig(rt$big(a) ^ rt$big(b), bits, signed);
}

function rt__shl(a, n, bits, signed) {
	if (n < 0 || n >= bits) rt$stop("shift-out-of-range", "shift out of range (the count must be 0 .. the width - 1)");
	const r = rt$fromBig(rt$big(a) << BigInt(n), bits, signed);
	return bits === 64 ? (signed ? rt__i64(r) : rt__u64(r)) : r;
}

function rt__shr(a, n, bits, signed) {
	if (n < 0 || n >= bits) rt$stop("shift-out-of-range", "shift out of range (the count must be 0 .. the width - 1)");
	if (signed) return Math.floor(a / 2 ** n);
	return Math.floor(a / 2 ** n);
}

function rt__bnot(a, bits, signed) {
	return rt$fromBig(~rt$big(a), bits, signed);
}

function rt__toInt(x, bits, signed) {
	if (typeof x === "bigint") return signed ? BigInt.asIntN(bits, x) : BigInt.asUintN(bits, x);
	const lo = signed ? -(2 ** (bits - 1)) : 0;
	const hi = signed ? 2 ** (bits - 1) : 2 ** bits;
	if (x < lo || x >= hi) rt$stop("integer-overflow", "the value does not fit the type it is converted to");
	return x;
}

function rt__inRange(x, lo, hi) {
	if (x < lo || x > hi) rt$stop("integer-overflow", "the value does not fit the type it is converted to");
	return x;
}

function rt__floatToInt(x, bits, signed) {
	if (Number.isNaN(x)) return 0;
	const lo = signed ? -(2 ** (bits - 1)) : 0;
	const hi = signed ? 2 ** (bits - 1) - 1 : 2 ** bits - 1;
	return Math.min(Math.max(Math.trunc(x), lo), hi);
}

// a float as print writes it: the shortest text that reads back as the same number (an f32's,
// as the same single)
function rt__fmtFloat(x, bits) {
	if (bits === 32 && Number.isFinite(x)) {
		for (let p = 1; p <= 9; p++) {
			const s = x.toPrecision(p);
			if (Math.fround(Number(s)) === x) return String(Number(s));
		}
	}
	return String(x);
}

// x with n decimals, the exact binary value rounded half to even (as a native run's fmtFixed)
function rt__f64ToFixed(x, n) {
	if (!Number.isFinite(x)) return String(x);
	const view = new DataView(new ArrayBuffer(8));
	view.setFloat64(0, Math.abs(x));
	const bits = view.getBigUint64(0);
	const exp = Number((bits >> 52n) & 0x7ffn);
	let mant = bits & 0xfffffffffffffn;
	let e = -1074;
	if (exp !== 0) { mant |= 1n << 52n; e = exp - 1075; }
	let num = mant * 10n ** BigInt(n);
	let den = 1n;
	if (e >= 0) num <<= BigInt(e); else den <<= BigInt(-e);
	let q = num / den;
	const r = num % den;
	if (2n * r > den || (2n * r === den && (q & 1n) === 1n)) q += 1n;
	const digits = q.toString().padStart(n + 1, "0");
	const text = n > 0 ? digits.slice(0, -n) + "." + digits.slice(-n) : digits;
	return (x < 0 && q !== 0n ? "-" : "") + text;
}
function rt__intToFixed(x, n) { return rt__f64ToFixed(x, n); }
function rt__fmtFixed(x, n) { return rt__f64ToFixed(x, n); }
function rt__intMin(a, b) { return Math.min(a, b); }
function rt__intMax(a, b) { return Math.max(a, b); }
function rt__intClamp(x, lo, hi) { return Math.min(Math.max(x, lo), hi); }
function rt__intAbs(x) { return Math.abs(x); }
function rt__f64Min(a, b) { return Math.min(a, b); }
function rt__f64Max(a, b) { return Math.max(a, b); }
function rt__f64Clamp(x, lo, hi) { return Math.min(Math.max(x, lo), hi); }
function rt__f64Abs(x) { return Math.abs(x); }
function rt__f64Floor(x) { return Math.floor(x); }
function rt__f64Ceil(x) { return Math.ceil(x); }
function rt__f64Round(x) { return Math.round(x); }
function rt__f64Sqrt(x) { return Math.sqrt(x); }
function rt__intToHex(x, upper) {
	const s = (x < 0 ? BigInt.asUintN(64, BigInt(x)) : x).toString(16);
	return upper ? s.toUpperCase() : s;
}

// ---------- values ----------

function rt__copy(v) {
	if (v === null || typeof v !== "object") return v;
	if (Array.isArray(v)) return v.map(rt__copy);
	if (v instanceof Map) return new v.constructor([...v].map(([k, x]) => [k, rt__copy(x)]));
	if (v instanceof rt__Err) return new rt__Err(rt__copy(v.e));
	const out = {};
	for (const k in v) out[k] = rt__copy(v[k]);
	return out;
}

function rt__eq(a, b) {
	if (a === b) return true;
	if (a === null || b === null || typeof a !== "object" || typeof b !== "object") return false;
	if (Array.isArray(a)) {
		if (!Array.isArray(b) || a.length !== b.length) return false;
		for (let i = 0; i < a.length; i++) if (!rt__eq(a[i], b[i])) return false;
		return true;
	}
	if (a instanceof Map) {
		if (!(b instanceof Map) || a.size !== b.size) return false;
		for (const [k, x] of a) if (!b.has(k) || !rt__eq(x, b.get(k))) return false;
		return true;
	}
	if (a instanceof rt__Err) return b instanceof rt__Err && rt__eq(a.e, b.e);
	for (const k in a) if (!rt__eq(a[k], b[k])) return false;
	return true;
}

function rt__cmp(a, b) {
	if (typeof a === "number" || typeof a === "string" || typeof a === "boolean") return a < b ? -1 : a > b ? 1 : 0;
	if (a === null) return b === null ? 0 : -1;
	if (b === null) return 1;
	if (Array.isArray(a)) {
		for (let i = 0; i < a.length && i < b.length; i++) {
			const c = rt__cmp(a[i], b[i]);
			if (c !== 0) return c;
		}
		return a.length - b.length;
	}
	for (const k in a) {
		const c = rt__cmp(a[k], b[k]);
		if (c !== 0) return c;
	}
	return 0;
}

// ---------- lists ----------

function rt__index(xs, i) {
	if (!(i >= 0 && i < xs.length)) rt$outOfBounds();
	return xs[i];
}

function rt__at(xs, i) {
	if (!(i >= 0 && i < xs.length)) rt$outOfBounds();
	return i;
}

function rt__range(lo, hi, step) {
	const out = [];
	const s = step === undefined ? 1 : step;
	if (s > 0) for (let i = lo; i < hi; i += s) out.push(i);
	else for (let i = lo; i > hi; i += s) out.push(i);
	return out;
}

function rt__listSlice(xs, lo, hi) {
	if (lo < 0 || hi > xs.length || lo > hi) rt$outOfBounds();
	return xs.slice(lo, hi);
}

function rt__listPush(xs, x) { return xs.push(x) - 1; }
function rt__listPop(xs) { return xs.length === 0 ? null : xs.pop(); }
function rt__listExtend(xs, ys) { for (const y of ys) xs.push(y); }
function rt__listClear(xs) { xs.length = 0; }
function rt__listTruncate(xs, n) { if (n < xs.length) xs.length = n; }
function rt__listReserve(xs, n) {}
function rt__listInsert(xs, i, x) { xs.splice(i, 0, x); }
function rt__listRemove(xs, i) { rt__at(xs, i); return xs.splice(i, 1)[0]; }
function rt__listFirst(xs) { return xs.length === 0 ? null : xs[0]; }
function rt__listLast(xs) { return xs.length === 0 ? null : xs[xs.length - 1]; }
function rt__listContains(xs, x) { return xs.some(y => rt__eq(x, y)); }
function rt__listIndexOf(xs, x) { const i = xs.findIndex(y => rt__eq(x, y)); return i < 0 ? null : i; }
function rt__listJoin(xs, sep) { return xs.join(sep); }
function rt__listReversed(xs) { return xs.slice().reverse(); }
function rt__listReverse(xs) { xs.reverse(); }
function rt__listSorted(xs) { return xs.slice().sort(rt__cmp); }
function rt__listSort(xs) { xs.sort(rt__cmp); }
function rt__listSortedBy(xs, f) { return xs.slice().sort((a, b) => rt__cmp(f(a), f(b))); }
function rt__listSortBy(xs, f) { xs.sort((a, b) => rt__cmp(f(a), f(b))); }
function rt__listMap(xs, f) { return xs.map(x => f(x)); }
function rt__listFilter(xs, f) { return xs.filter(x => f(x)); }
function rt__listAny(xs, f) { return xs.some(x => f(x)); }
function rt__listAll(xs, f) { return xs.every(x => f(x)); }
function rt__listFind(xs, f) { const i = xs.findIndex(x => f(x)); return i < 0 ? null : xs[i]; }
function rt__listFindIndex(xs, f) { const i = xs.findIndex(x => f(x)); return i < 0 ? null : i; }
function rt__listCount(xs, f) { let n = 0; for (const x of xs) if (f(x)) n++; return n; }
function rt__listSum(xs, f) { let n = 0; for (const x of xs) n += f === undefined ? x : f(x); return n; }
function rt__listMin(xs) { return xs.length === 0 ? null : xs.reduce((a, b) => rt__cmp(b, a) < 0 ? b : a); }
function rt__listMax(xs) { return xs.length === 0 ? null : xs.reduce((a, b) => rt__cmp(b, a) > 0 ? b : a); }
function rt__listCopy(xs) { return rt__copy(xs); }
function rt__listIsEmpty(xs) { return xs.length === 0; }
function rt__listLen(xs) { return xs.length; }
function rt__listRepeat(xs, n) { const out = []; for (let i = 0; i < n; i++) for (const x of xs) out.push(rt__copy(x)); return out; }
function rt__listSwap(xs, i, j) { const t = xs[i]; xs[i] = xs[j]; xs[j] = t; }
function rt__listEnumerate(xs) { return xs.map((x, i) => ({ _0: i, _1: x })); }
function rt__fill(n, x) { const out = []; for (let i = 0; i < n; i++) out.push(rt__copy(x)); return out; }

// ---------- strs: JS strings, their bytes UTF-8's ----------

const rt$enc = new TextEncoder();
const rt$dec = new TextDecoder();
let rt$lastStr = null;
let rt$lastBytes = null;

// the UTF-8 bytes of s, kept for the last str asked (a loop over one str's bytes)
function rt$bytesOf(s) {
	if (s !== rt$lastStr) {
		rt$lastStr = s;
		rt$lastBytes = rt$enc.encode(s);
	}
	return rt$lastBytes;
}

function rt$isAscii(s) { return rt$bytesOf(s).length === s.length; }

function rt__sLen(s) { return rt__strLen(s); }
function rt__strLen(s) { return rt$isAscii(s) ? s.length : rt$bytesOf(s).length; }
function rt__strIsEmpty(s) { return s.length === 0; }

function rt__strByte(s, i) {
	const b = rt$bytesOf(s);
	if (!(i >= 0 && i < b.length)) rt$outOfBounds();
	return b[i];
}

function rt__strSlice(s, lo, hi) {
	const b = rt$bytesOf(s);
	if (lo < 0 || hi > b.length || lo > hi) rt$outOfBounds();
	if (b.length === s.length) return s.slice(lo, hi);
	return rt$dec.decode(b.subarray(lo, hi));
}

function rt__strWindow(s, lo, hi) { return rt__strSlice(s, lo, hi); }
function rt__strBytes(s) { return Array.from(rt$bytesOf(s)); }
function rt__strOfBytes(bytes) { return rt$dec.decode(Uint8Array.from(bytes)); }

// the byte index of the UTF-16 index i of s
function rt$byteIndex(s, i) { return rt$isAscii(s) ? i : rt$enc.encode(s.slice(0, i)).length; }

function rt__strContains(s, t) { return s.includes(t); }
function rt__strStartsWith(s, t) { return s.startsWith(t); }
function rt__strEndsWith(s, t) { return s.endsWith(t); }
function rt__strIndexOf(s, t, from) {
	const at = from === undefined ? s.indexOf(t) : s.indexOf(t, rt__strSlice(s, 0, from).length);
	return at < 0 ? null : rt$byteIndex(s, at);
}
function rt__strLastIndexOf(s, t) { const at = s.lastIndexOf(t); return at < 0 ? null : rt$byteIndex(s, at); }
function rt__strUpper(s) { return s.replace(/[a-z]+/g, m => m.toUpperCase()); }
function rt__strLower(s) { return s.replace(/[A-Z]+/g, m => m.toLowerCase()); }
function rt__strReplace(s, a, b) { return a === "" ? s : s.split(a).join(b); }
function rt__strRepeat(s, n) { return s.repeat(n); }
function rt__strSplit(s, sep) { return sep === "" ? Array.from(s) : s.split(sep); }
function rt__strLines(s) {
	if (s === "") return [];
	const out = s.split("\n").map(l => l.endsWith("\r") ? l.slice(0, -1) : l);
	if (s.endsWith("\n")) out.pop();
	return out;
}
function rt__strWords(s) { return s.split(/[ \t\r\n]+/).filter(w => w !== ""); }
function rt__strChars(s) { return Array.from(s); }
function rt__strCount(s, t) { return t === "" ? 0 : s.split(t).length - 1; }
function rt__strPadStart(s, n, c) { return s.padStart(n + s.length - rt__strLen(s), c === undefined ? " " : c); }
function rt__strPadEnd(s, n, c) { return s.padEnd(n + s.length - rt__strLen(s), c === undefined ? " " : c); }
function rt__strCopy(s) { return s; }
function rt__strHash(s) { let h = 0; for (const b of rt$bytesOf(s)) h = (Math.imul(h, 31) + b) | 0; return h; }

function rt__intIsSpace(b) { return b === 32 || (b >= 9 && b <= 13); }
function rt__intIsDigit(b) { return b >= 48 && b <= 57; }
function rt__intIsUpper(b) { return b >= 65 && b <= 90; }
function rt__intIsLower(b) { return b >= 97 && b <= 122; }
function rt__intIsAlpha(b) { return rt__intIsUpper(b) || rt__intIsLower(b); }
function rt__intIsAlnum(b) { return rt__intIsAlpha(b) || rt__intIsDigit(b); }
function rt__intIsWordByte(b) { return rt__intIsAlnum(b) || b === 95; }

// i64.parse: decimal digits or 0x and hex ones after an optional sign; none for anything else
function rt__i64Parse(s) {
	const m = /^([+-]?)(?:0[xX]([0-9a-fA-F]+)|([0-9]+))$/.exec(s);
	if (m === null) return null;
	const v = m[2] !== undefined ? parseInt(m[2], 16) : Number(m[3]);
	return rt__i64(m[1] === "-" ? -v : v);
}
function rt__f64Parse(s) {
	const t = s;
	if (t === "" || !/^[+-]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][+-]?[0-9]+)?$/.test(t)) return null;
	return Number(t);
}

// ---------- values as text, onto a list of bytes (derived code's printing) ----------

function rt$push(out, s) {
	const b = rt$bytesOf(s);
	for (let i = 0; i < b.length; i++) out.push(b[i]);
}

function rt__outStr(out, s) { rt$push(out, s); }
function rt__outInt(out, v) { rt$push(out, String(v)); }
function rt__outUint(out, v) { rt$push(out, String(v)); }
function rt__outBool(out, b) { rt$push(out, b ? "true" : "false"); }
function rt__outFloat(out, x) { rt$push(out, rt__fmtFloat(x, 64)); }
function rt__outJsonFloat(out, x) { rt$push(out, Number.isFinite(x) ? rt__fmtFloat(x, 64) : "null"); }
function rt__outQuoted(out, s) { rt$push(out, rt__jsonQuote(s)); }
function rt__fmtBool(b) { return b ? "true" : "false"; }
function rt__fmtInt(v) { return String(v); }
function rt__fmtUint(v) { return String(v); }

// s as a JSON string literal: " \ and the control characters escaped
function rt__jsonQuote(s) {
	return '"' + s.replace(/["\\\x00-\x1f]/g, c => {
		if (c === '"' || c === "\\") return "\\" + c;
		if (c === "\n") return "\\n";
		if (c === "\r") return "\\r";
		if (c === "\t") return "\\t";
		return "\\u00" + c.charCodeAt(0).toString(16).padStart(2, "0");
	}) + '"';
}

// ---------- maps ----------

// a map whose keys are structs or lists: each kept under its canonical text, as JS compares
// objects by identity and Zap by value
class rt$KeyMap extends Map {
	get(k) { const e = super.get(rt$canon(k)); return e === undefined ? undefined : e[1]; }
	set(k, v) { return super.set(rt$canon(k), [k, v]); }
	has(k) { return super.has(rt$canon(k)); }
	delete(k) { return super.delete(rt$canon(k)); }
	*keys() { for (const e of super.values()) yield e[0]; }
	*values() { for (const e of super.values()) yield e[1]; }
	*entries() { for (const e of super.values()) yield [e[0], e[1]]; }
	[Symbol.iterator]() { return this.entries(); }
	forEach(f) { for (const [k, v] of this.entries()) f(v, k, this); }
}

function rt$canon(k) {
	if (k === null || typeof k !== "object") return typeof k + ":" + String(k);
	if (Array.isArray(k)) return "[" + k.map(rt$canon).join(",") + "]";
	return "{" + Object.keys(k).sort().map(f => f + "=" + rt$canon(k[f])).join(",") + "}";
}

function rt__mapSet(m, k, v) { m.set(k, v); }
function rt__mapIndex(m, k) {
	if (!m.has(k)) rt$stop("failure", "the key is not in the map");
	return m.get(k);
}
function rt__mapGet(m, k) { return m.has(k) ? m.get(k) : null; }
function rt__mapHas(m, k) { return m.has(k); }
function rt__mapRemove(m, k) { const v = m.has(k) ? m.get(k) : null; m.delete(k); return v; }
function rt__mapKeys(m) { return [...m.keys()]; }
function rt__mapValues(m) { return [...m.values()]; }
function rt__mapClear(m) { m.clear(); }
function rt__mapLen(m) { return m.size; }
function rt__mapIsEmpty(m) { return m.size === 0; }
function rt__mapAdd(m, k, n) { m.set(k, (m.has(k) ? m.get(k) : 0) + n); }
function rt__mapAddText(m, k, n) { rt__mapAdd(m, k, n); }

// ---------- the tests of zap test ----------

const rt$test = { failures: 0, ran: 0, ranFailed: 0, counts: "", updates: "", caseIndex: -1, caseShown: "", caseFailures: 0, casesFailed: 0 };

function rt__testCountsBeside() {
	if (rt$node) rt$test.counts = process.argv[1].replace(/\.mjs$/, "") + ".counts";
}

function rt__testUpdatesTo(file) { rt$test.updates = file; }

function rt__testFail(where, text, details) {
	rt$test.failures += 1;
	let msg = "    " + where + ": expect " + text + " failed";
	for (const d of details) msg += "\n        " + rt$cut(d, 300);
	rt__printLine(msg, 1);
}

function rt$cut(text, most) {
	if (text.length <= most) return text;
	return text.slice(0, most) + "... (" + (text.length - most) + " more bytes)";
}

function rt__testRun(file, name, body) {
	rt$endTestInput();
	rt$test.failures = 0;
	rt$test.caseIndex = -1;
	rt$test.casesFailed = 0;
	try {
		body();
	} catch (e) {
		if (e instanceof rt$Skipped) {
			rt__printLine(e.message, 0);
			return 0;
		}
		if (!(e instanceof rt$Stop)) throw e;
		rt$capturing = false;
		rt__printLine("    " + file + ": zap: error[" + e.code + "]: " + e.message, 1);
		rt$test.failures += 1;
	}
	if (rt$test.caseIndex >= 0 && rt$test.failures === rt$test.caseFailures) {
		rt$test.ran += rt$test.caseIndex + 1;
		rt$test.ranFailed += rt$test.casesFailed;
	} else {
		rt$test.ran += 1;
		rt$test.ranFailed += rt$test.failures > 0 ? 1 : 0;
	}
	if (rt$test.failures > 0) {
		rt__printLine("FAIL " + file + ": " + name, 1);
		return 1;
	}
	return 0;
}

// the arguments and the options a test gave are taken back before the next (test.zap's endTestInput)
function rt$endTestInput() {
	rt__programArgs = rt$node ? process.argv.slice(2) : [];
	if (typeof rt__declaredOptions !== "undefined") rt__declaredOptions = [];
}

function rt__testCaptureStart() {
	rt$flush();
	rt$captured = "";
	rt$capturing = true;
}

function rt__testCaptureStop() {
	rt$capturing = false;
	if (rt$captured !== "") {
		rt$out += rt$captured;
		rt$captured = "";
	}
}

function rt__testPrints(expected, where) {
	const got = rt$captured.replace(/\n$/, "");
	rt$captured = "";
	const want = expected.replace(/\n$/, "");
	if (got === want) return;
	if (rt$test.updates !== "" && rt$fs) {
		rt$fs.appendFileSync(rt$test.updates, where + "\n" + rt__strLen(got) + "\n" + got + "\n");
		rt__printLine("    " + where + ": the expected text is rewritten", 1);
		return;
	}
	rt$test.failures += 1;
	const indent = s => "        " + s.split("\n").join("\n        ");
	rt__printLine("    " + where + ": printed\n" + indent(got) + "\n    instead of\n" + indent(want), 1);
}

function rt__testCaseStart(shown) {
	rt$test.caseIndex += 1;
	rt$test.caseShown = shown;
	rt$test.caseFailures = rt$test.failures;
}

function rt__testCaseEnd(file, name) {
	if (rt$test.failures > rt$test.caseFailures) {
		rt$test.casesFailed += 1;
		rt__printLine("FAIL " + file + ": " + name + " [" + rt$test.caseIndex + "] " + rt$test.caseShown, 1);
	}
	rt$test.caseFailures = rt$test.failures;
}

function rt__testSummary(ran, failed) {
	return failed === 0 ? "ok   " + ran + " tests" : failed + " of " + ran + " tests failed";
}

function rt__testExit(failed) {
	rt__printLine(rt__testSummary(rt$test.ran, rt$test.ranFailed), 1);
	if (rt$test.counts !== "" && rt$fs) rt$fs.writeFileSync(rt$test.counts, rt$test.ran + " " + rt$test.ranFailed);
	rt__exit(Math.min(failed, 255));
}

// ---------- the console's streams and the program's arguments ----------

const rt__stdout = { handle: 1 };
const rt__stderr = { handle: 2 };
let rt__programArgs = rt$node ? process.argv.slice(2) : [];

function rt__Stream__write(stream, text) { rt$write(text, stream.handle === 2); }
function rt__Stream__writeBytes(stream, bytes) { rt$write(rt__strOfBytes(bytes), stream.handle === 2); }

// ---------- a map's cells, as derived code walks them: a snapshot of its entries ----------

function rt__mapEntryCount(m) { m.$cells = [...m]; return m.$cells.length; }
function rt__mapEntryAlive(m, i) { return true; }
function rt__mapKeyAt(m, i) { return m.$cells[i][0]; }
function rt__mapValAt(m, i) { return m.$cells[i][1]; }
function rt__mapSortedCells(m) {
	m.$cells = [...m].sort((a, b) => rt__cmp(a[0], b[0]));
	return m.$cells.map((_, i) => i);
}

// ---------- the environment's variables ----------

const rt__env = {};

function rt__Environment__get(env, name) {
	if (!rt$node) return null;
	const v = process.env[name];
	return v === undefined ? null : v;
}

function rt__Environment__set(env, name, value) {
	if (rt$node) process.env[name] = value;
}

function rt__Environment__index(env, name) {
	const v = rt__Environment__get(env, name);
	if (v === null) rt$stop("failure", "the environment variable " + name + " is not set");
	return v;
}

// ---------- random numbers: xorshift64* over 64 bits (BigInt), the same sequence as a native run ----------

const rt__randomStart = -7046029254386353131n;

function rt$nextBits(r) {
	let x = BigInt.asUintN(64, BigInt(r.state === 0 || r.state === 0n ? rt__randomStart : r.state));
	x ^= x >> 12n;
	x = BigInt.asUintN(64, x ^ (x << 25n));
	x ^= x >> 27n;
	r.state = BigInt.asIntN(64, x);
	return BigInt.asUintN(64, x * 2685821657736338717n);
}

function rt__Random__nextBits(r) { return rt__u64(Number(rt$nextBits(r))); }

function rt__Random__nextInt(r, lo, hi) {
	if (hi <= lo) rt__fail("random from an empty range " + lo + ".." + hi);
	return lo + Number((rt$nextBits(r) >> 1n) % BigInt(hi - lo));
}

function rt__Random__nextFloat(r, lo, hi) {
	return lo + (hi - lo) * (Number(rt$nextBits(r) >> 11n) / 9007199254740992.0);
}

// ---------- an integer's bits (a value of `bits` bits, signed or not) ----------

function rt$bitsOf(x, bits) { return BigInt.asUintN(bits, BigInt(x)); }
function rt$fromBits(b, bits, signed) { return Number(signed ? BigInt.asIntN(bits, b) : BigInt.asUintN(bits, b)); }
function rt$bitAt(n, bits) { if (n < 0 || n >= bits) rt$stop("shift-out-of-range", "shift out of range (the count must be 0 .. the width - 1)"); return BigInt(n); }

function rt__intBit(x, n, bits, signed) { return ((rt$bitsOf(x, bits) >> rt$bitAt(n, bits)) & 1n) === 1n; }
function rt__intBits(x, from, count, bits, signed) {
	rt$bitAt(from, bits);
	if (count < 0 || from + count > bits) rt$stop("shift-out-of-range", "shift out of range (the count must be 0 .. the width - 1)");
	return rt$fromBits((rt$bitsOf(x, bits) >> BigInt(from)) & ((1n << BigInt(count)) - 1n), bits, signed && count === bits);
}
function rt__intWithBit(x, n, on, bits, signed) {
	const m = 1n << rt$bitAt(n, bits);
	const b = rt$bitsOf(x, bits);
	return rt$fromBits(on ? b | m : b & ~m, bits, signed);
}
function rt__intWithBits(x, from, count, v, bits, signed) {
	rt$bitAt(from, bits);
	const m = ((1n << BigInt(count)) - 1n) << BigInt(from);
	const b = (rt$bitsOf(x, bits) & ~m) | ((BigInt.asUintN(64, BigInt(v)) << BigInt(from)) & m);
	return rt$fromBits(b, bits, signed);
}
function rt__intBitCount(x, bits) { let b = rt$bitsOf(x, bits), n = 0; while (b) { n += Number(b & 1n); b >>= 1n; } return n; }
function rt__intTrailingZeros(x, bits) { let b = rt$bitsOf(x, bits); if (b === 0n) return bits; let n = 0; while (!(b & 1n)) { b >>= 1n; n++; } return n; }
function rt__intLeadingZeros(x, bits) { const b = rt$bitsOf(x, bits); return b === 0n ? bits : bits - b.toString(2).length; }
function rt__intRotateLeft(x, n, bits, signed) { const b = rt$bitsOf(x, bits), k = BigInt(((n % bits) + bits) % bits); return rt$fromBits((b << k) | (b >> (BigInt(bits) - k)), bits, signed); }
function rt__intRotateRight(x, n, bits, signed) { return rt__intRotateLeft(x, bits - (((n % bits) + bits) % bits), bits, signed); }
function rt__intByteSwap(x, bits, signed) { let b = rt$bitsOf(x, bits), r = 0n; for (let i = 0; i < bits / 8; i++) { r = (r << 8n) | (b & 255n); b >>= 8n; } return rt$fromBits(r, bits, signed); }

// a float's bits as a BigInt (past 2^53 they are no JS number), and back
function rt__floatToBits(x, bits) {
	const v = new DataView(new ArrayBuffer(8));
	if (bits === 32) { v.setFloat32(0, x); return BigInt(v.getUint32(0)); }
	v.setFloat64(0, x);
	return v.getBigUint64(0);
}
function rt__floatFromBits(b, bits) {
	const v = new DataView(new ArrayBuffer(8));
	if (bits === 32) { v.setUint32(0, Number(BigInt.asUintN(32, BigInt(b)))); return v.getFloat32(0); }
	v.setBigUint64(0, BigInt.asUintN(64, BigInt(b)));
	return v.getFloat64(0);
}
function rt__f64Trunc(x) { return Math.trunc(x); }

// derived printing of a float, from the bits of its f64 (an f32's value widened)
function rt__pushFloat(out, bits, size) { rt$push(out, rt__fmtFloat(rt__floatFromBits(bits, 64), size)); }

// ---------- bytes of strs: searches by byte index ----------

function rt__byteIndex(s, b, start) {
	const bytes = rt$bytesOf(s);
	return bytes.indexOf(b & 255, Math.max(start, 0));
}

function rt__findBytes(s, start, sub) {
	if (rt$isAscii(s) && rt$isAscii(sub)) return s.indexOf(sub, Math.max(start, 0)) >= 0 ? s.indexOf(sub, Math.max(start, 0)) : -1;
	const a = rt$enc.encode(s), b = rt$enc.encode(sub);
	outer: for (let i = Math.max(start, 0); i + b.length <= a.length; i++) {
		for (let j = 0; j < b.length; j++) if (a[i + j] !== b[j]) continue outer;
		return i;
	}
	return -1;
}

function rt__strFromU8(bytes) { return rt__strOfBytes(bytes); }
