# The interpreter's functions for the operations forms.zap writes (cpu/forms.zap, written by
# tools/forms.zap and checked current by cpu/tests/forms.zap): for each, a function over the decoded
# instruction that branches on the attributes that shape the form's text, each branch the form
# with the fields read from the instruction.

import fs
import recomp.switch.arm64

# an attribute that shapes a form: its name in Instr and the values it takes
type Attribute:
	name str
	values i64[]
	isFlag bool = false   # a bool's: its two values are false and true

# an attribute of two values, a bool's
fn flag(name str):
	Attribute(name = name.copy(), values = [0, 1], isFlag = true)

# the operations with forms and the attributes each one's form depends on
formed = [
	(arm64.Op.AddImm, [flag("sf"), flag("setFlags"), flag("subtract")]),
	(arm64.Op.AddShifted, [flag("sf"), flag("setFlags"), flag("subtract")]),
	(arm64.Op.LogicImm, [flag("sf"), Attribute(name = "opc", values = [0, 1, 2, 3])]),
	(arm64.Op.LogicShifted, [flag("sf"), Attribute(name = "opc", values = [0, 1, 2, 3]), flag("subtract")]),
	(arm64.Op.Load, [flag("vector"), flag("signed"), flag("sf"), Attribute(name = "mode", values = [0, 1, 2, 3])]),
	(arm64.Op.Store, [flag("vector"), Attribute(name = "mode", values = [0, 1, 2, 3])]),
	(arm64.Op.LoadPair, [flag("vector"), flag("signed"), Attribute(name = "mode", values = [0, 1, 2])]),
	(arm64.Op.StorePair, [flag("vector"), Attribute(name = "mode", values = [0, 1, 2])]),
	(arm64.Op.MoveWide, [flag("sf"), Attribute(name = "opc", values = [0, 2, 3])]),
	(arm64.Op.Adr, []),
	(arm64.Op.CondSelect, [flag("sf"), Attribute(name = "opc", values = [0, 1, 2, 3])]),
	(arm64.Op.BranchCond, []),
	(arm64.Op.AddExtended, [flag("sf"), flag("setFlags"), flag("subtract")]),
	(arm64.Op.AddCarry, [flag("sf"), flag("setFlags"), flag("subtract")]),
	(arm64.Op.Bitfield, [flag("sf"), Attribute(name = "opc", values = [0, 1, 2])]),
	(arm64.Op.Extract, [flag("sf")]),
	(arm64.Op.CondCompare, [flag("sf"), flag("subtract"), flag("pair")]),
	(arm64.Op.ThreeSource, [flag("sf"), Attribute(name = "opc", values = [0, 1, 2, 3, 4, 10, 11, 12])]),
	(arm64.Op.CompareBranch, [flag("sf"), Attribute(name = "opc", values = [0, 1])]),
	(arm64.Op.TestBranch, [Attribute(name = "opc", values = [0, 1])])
]

modes = [arm64.Mode.Offset, arm64.Mode.PreIndex, arm64.Mode.PostIndex, arm64.Mode.RegisterOffset]

# i with the attribute set to the value
fn withAttribute(i arm64.Instr, name str, v i64):
	out = i.copy()
	match name:
		"sf": out.sf = v == 1
		"setFlags": out.setFlags = v == 1
		"subtract": out.subtract = v == 1
		"vector": out.vector = v == 1
		"signed": out.signed = v == 1
		"opc": out.opc = v
		"pair": out.pair = v == 1
		_: out.mode = modes[v]
	out

# the branches over attributes[at..] of i's form, at `depth` tabs
fn branches(i arm64.Instr, attributes Attribute[], at i64, depth i64) str[]:
	tab = "\t".repeat(depth)
	if at == attributes.len: return (i.formLines(readFields()) ?? ["pass"]).map("{tab}{it}")
	a = attributes[at]
	out = []
	if a.isFlag:
		out.push("{tab}if i.{a.name}:")
		out.extend(i.withAttribute(a.name, 1).branches(attributes, at + 1, depth + 1))
		out.push("{tab}else:")
		out.extend(i.withAttribute(a.name, 0).branches(attributes, at + 1, depth + 1))
		return out
	out.push("{tab}match i.{a.name}:")
	for v in a.values:
		label = "{modes[v]}" if a.name == "mode" else "{v}"
		out.push("{tab}\t{label}:")
		out.extend(i.withAttribute(a.name, v).branches(attributes, at + 1, depth + 2))
	if a.name != "mode" or a.values.len < modes.len: out.push("{tab}	_: pass")
	out

# The text of cpu/forms.zap.
pub fn interpreterForms() str:
	lines = [
		"# Written by tools/forms.zap from translate/forms.zap, the forms the translation writes: do",
		"# not edit. Each is the interpreter's function for one operation (execute.zap calls them).",
		"",
		"import recomp.switch.arm64"
	]
	for (op, attributes) in formed:
		lines.push("")
		lines.push("pub fn form{op}(mut c Cpu, i arm64.Instr):")
		lines.extend(branches(arm64.Instr(op), attributes, 0, 1))
	"{lines.join("\n")}\n"

# The interpreter's forms written to path and laid out by zap fmt (zap the compiler's path); why
# not, when they cannot be.
pub fn writeInterpreter(path str, zap str) ? str:
	fs.writeFile(path, interpreterForms()) ?? return "cannot write {path}: {error}"
	laid = Process.output("{zap} fmt {path}")
	if laid.code != 0: return "zap fmt {path}: {laid.out}"
