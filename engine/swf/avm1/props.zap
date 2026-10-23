# Members of values (Ruffle's core/src/avm1/object/script_object.rs and stage_object.rs): an
# object's own property, then its prototypes', a getter of addProperty called with the object as
# `this`; an array's elements and length; a movie clip's own properties first, then _root,
# _parent and _global, then its children by instance name, then its display properties (_x ...);
# a text field's text properties; a string's length and String.prototype's methods.

# the member of a value by name
import engine.swf

pub fn getMember(prog Program, mut m Machine, object Value, name str) Value ? Thrown:
	match object:
		Obj(id): try prog.getProp(m, id, name, object)
		Str(s):
			if name == "length": return Value.Num(f64(s.chars().len))
			try prog.readChain(m, m.protos.string, name, object)
		Num: try prog.readChain(m, m.protos.number, name, object)
		Bool: try prog.readChain(m, m.protos.boolean, name, object)
		_: Value.Undefined

fn getProp(prog Program, mut m Machine, id Handle<Obj>, name str, me Value) Value ? Thrown:
	if name == "__proto__":
		if m.heap[id].proto is p: return Value.Obj(p)
		return Value.Undefined
	match m.kindOf(id):
		Array:
			if name == "length": return Value.Num(f64(m.heap[id].items.len))
			if indexOfName(name) is k:
				return m.heap[id].items[k].copy() if k < m.heap[id].items.len else Value.Undefined
		Super(who, base): return try prog.readChain(m, m.heap[base].proto, name, .Obj(who))
		Clip(n):
			if m.heap[id].props.get(name) == none and n in m.stage.nodes:
				if prog.clipMember(m, n, name) is v: return v
		Text(n):
			if m.heap[id].props.get(name) == none and n in m.stage.nodes:
				if prog.textMember(m, n, name) is v: return v
				if prog.displayProperty(m, n, name) is v: return v
		Boxed(v):
			if name == "length" and v is Str(s): return Value.Num(f64(s.chars().len))
		_:
			if id == m.stageObject:
				if prog.stageMember(m, name) is v: return v
	try prog.readChain(m, id, name, me)

# a property found along the prototype chain from `start`, a getter called on me
pub fn readChain(
	prog Program,
	mut m Machine,
	start Handle<Obj>?,
	name str,
	me Value
) Value ? Thrown:
	holder = m.holderOf(start, name) ?? return Value.Undefined
	try prog.readProp(m, holder, name, me)

pub fn readProp(prog Program, mut m Machine, holder Handle<Obj>, name str, me Value) Value ? Thrown:
	p = m.heap[holder].props[name]
	if p.getter is getter: return try prog.callValue(m, .Obj(getter), me, [], holder)
	p.value.copy()

# whether a name is found on the object: its own and its prototypes' properties, an array's
# elements, a clip's children and display properties, a text field's properties
pub fn hasProperty(prog Program, m Machine, id Handle<Obj>, name str) bool:
	if m.holderOf(id, name) != none: return true
	match m.kindOf(id):
		Array: name == "length" or
			(indexOfName(name) ?? m.heap[id].items.len) < m.heap[id].items.len
		Clip(n):
			if n not in m.stage.nodes: return false
			if name in ["_root", "_parent", "_global", "_level0"]: return true
			m.stage.childNamed(n, name) != none or displayIndex(name) != none
		Text(n): isTextProperty(name) or displayIndex(name) != none
		_: false

# sets the member of a value: a setter of addProperty called, a read-only one left
pub fn setMember(prog Program, mut m Machine, object Value, name str, v Value) () ? Thrown:
	id = object.objectId() ?? return
	if name == "__proto__":
		m.heap[id].proto = v.objectId()
		return
	match m.kindOf(id):
		Array:
			if name == "length":
				m.setLength(id, toInt32(try prog.toNumber(m, v)))
				return
			if indexOfName(name) is k:
				if k >= m.heap[id].items.len: m.setLength(id, k + 1)
				m.heap[id].items[k] = v.copy()
				return
		Clip(n):
			if displayIndex(name) != none and n in m.stage.nodes:
				try prog.setDisplayProperty(m, n, name, v)
				return
		Text(n):
			if n in m.stage.nodes:
				if isTextProperty(name) or displayIndex(name) != none:
					if try prog.setTextMember(m, n, name, v): return
		Super(who, _):
			try prog.setMember(m, .Obj(who), name, v)
			return
		_:
			if id == m.stageObject and (name == "scaleMode" or name == "align"):
				text = try prog.toText(m, v)
				if name == "scaleMode": m.viewport.scaleMode = text
				else: m.viewport.align = text
				return
	if m.holderOf(id, name) is holder:
		p = m.heap[holder].props[name]
		if p.setter is setter:
			try prog.callValue(m, .Obj(setter), object, [v.copy()], holder)
			return
		if p.getter != none: return
		if holder == id and (p.flags & readOnly) != 0: return
	m.setOwn(id, name, v.copy())

pub fn setLength(mut m Machine, id Handle<Obj>, n i64):
	if n < m.heap[id].items.len:
		m.heap[id].items.truncate(n.max(0))
		return
	loop n - m.heap[id].items.len:
		m.heap[id].items.push(.Undefined)
