# Prints the character's behavior graph (0_master.hkx with the files it refers to): its size; with
# --event word the transitions on events whose name holds the word; with --tree n (a node's index or name) the generators
# from it down (--depth levels, default 4); with --variables the variables' initial values.
#
#   zap run projects/skyrim/graphInfo.zap [--install dir] [--event word] [--tree n] [--depth d]

import skyrim
import skyrim.hkx
import skyrim.actor

fn transitionText(g hkx.Graph, t hkx.Transition):
	cond = "" if t.condition.isEmpty else " if {t.condition}"
	"{t.event} -> {t.toState}/{t.nested}{cond} ({t.blend:.2} s, priority {t.priority})"

fn printTree(g hkx.Graph, at i64, depth i64, shown i64):
	if at < 0 or depth > shown: return
	n = g.nodes[at]
	pad = "  ".repeat(depth)
	clip = "" if n.clip.isEmpty else " clip {n.clip} x{n.speed}"
	bound = n.bindings.map("{.slot}:{.member}={.variable}").join(" ")
	print("{pad}{at} {n.kind} {n.name} start {n.start} {n.chooser}{clip} [{bound}] {n.positions} partial {n.partial} masks {n.bones.map(.weights.len)}")
	if n.kind == .Blender: print("{pad}  parametric {n.parametric} cyclic {n.cyclic} {n.low}..{n.high} parameter {n.parameter}")
	for m in n.modifiers:
		print("{pad}  expression {m.variable}{m.event} = {m.expression}")
	if n.kind == .Machine:
		for t in n.wildcards:
			print("{pad}  * {g.transitionText(t)}")
		for s in n.states:
			print("{pad}  state {s.id} {s.name} enter {s.enter} exit {s.exit}")
			for t in s.transitions:
				print("{pad}    {g.transitionText(t)}")
			g.printTree(s.generator, depth + 2, shown)
	else:
		for c in n.children:
			g.printTree(c, depth + 1, shown)

fn printEvents(g hkx.Graph, word str):
	for i, n in g.nodes:
		if n.kind != .Machine: continue
		for t in n.wildcards:
			if t.event.lower().indexOf(word.lower()) != none:
				print("machine {i} {n.name} *: {g.transitionText(t)}")
		for s in n.states:
			for t in s.transitions:
				if t.event.lower().indexOf(word.lower()) != none:
					print("machine {i} {n.name} state {s.id} {s.name}: {g.transitionText(t)}")

dir = args.option("--install") ?? skyrim.defaultInstall
install = skyrim.openInstall(dir) ?? fail("no install")
g = install.readCharacterGraph() ?? fail
print("{g.nodes.len} nodes, root {g.root}, {g.variables.len} variables")
if args.hasFlag("--variables"):
	for v in g.variables:
		print("  {v.name} = {v.value}")
if args.hasFlag("--classes"):
	counts {str: i64} = {}
	for n in g.nodes:
		if n.kind == .Other: counts[n.class.copy()] = (counts.get(n.class) ?? 0) + 1
	for c in counts.keys().sorted(): print("  {counts[c]} {c}")
if args.option("--event") is word: g.printEvents(word)
if args.option("--tree") is at:
	first = i64.parse(at) ?? (g.nodes.findIndex(.name == at) ?? 0)
	g.printTree(first, 0, i64.parse(args.option("--depth") ?? "4") ?? 4)
if args.hasFlag("--masks"):
	for i, n in g.nodes:
		for k, m in n.bones:
			if m.weights.isEmpty: continue
			held = m.weights.filter(it > 0.0).len
			print("{i} {n.name} child {k}: {m.weights.len} bones, {held} above 0, first {m.weights.findIndex(it > 0.0)}")
if args.option("--clip") is word:
	for i, n in g.nodes:
		if n.kind == .Clip and word.lower() in n.clip:
			print("{i} {n.name} {n.clip} x{n.speed} looping {n.looping} {n.triggers.map("{.event}@{.time}{"end" if .fromEnd else ""}").join(" ")}")
