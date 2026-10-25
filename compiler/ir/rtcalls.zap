# Calls of the runtime's functions, and the runtime function a builtin is.

alias nodes = g.c.nodes

fn rtDecl(g Gen, name str):
	if g.c.findFunc("rt__{name}") is d: return d
	die("x64: the runtime has no function '{name}'")
	0

# call rt__name with the arguments already pushed (bytes, argWord), no result or a scalar result
# in rax; a function that takes its arguments in registers gets them popped (or read) into those
fn callRtNamed(mut g Gen, name str, pushed i64):
	fnd = g.rtDecl(name)
	n = pushed / 8
	if g.takesRegArgs(fnd, false):
		regs = regArgRegs()
		i = n - 1
		while i >= 0:
			if g.f.area:
				g.a.memOp(true, 0x8B, -1, regs[i], 4, -1, 8 * (n - 1 - i))   # mov reg, [rsp+...]
			else:
				if regs[i] >= 8:
					g.a.em1(0x41)
				g.a.em1(0x58 | (regs[i] & 7))   # pop the register
			i -= 1
		g.a.callLabel(fnLabel(g.fnLabels, g.a, "rt__{name}"))
		return
	g.a.callLabel(fnLabel(g.fnLabels, g.a, "rt__{name}"))
	g.argsTaken(n)

# call rt__name with its arguments in the registers args (the first argument's first); one that
# takes them in registers while rsp stays put gets them moved there, the last first (none of these
# sources is a register an argument before it goes to)
fn callRtWith(mut g Gen, name str, args i64[]):
	if g.f.area and g.takesRegArgs(g.rtDecl(name), false):
		i = args.len - 1
		while i >= 0:
			g.irMov(regArgRegs()[i], args[i])
			i -= 1
		g.a.callLabel(fnLabel(g.fnLabels, g.a, "rt__{name}"))
		return
	for k, r in args:
		g.argWord(r, k, args.len)
	g.callRtNamed(name, 8 * args.len)

# The generic runtime instance of fn `name` for the type arguments, recorded for generation.
fn rtInstance(mut g Gen, name str, args TypeId[]):
	"rt__{name}_{g.rtMangle(name, args)}"

# the runtime's generic function name for args recorded: its instance's mangled types
fn rtMangle(mut g Gen, name str, args TypeId[]):
	fnd = g.rtDecl(name)
	generics = nodes[fnd].names()
	if generics.len != args.len:
		die("x64: runtime function '{name}' takes {generics.len} type argument(s)")
	sub = Subst(names = generics.copy(), types = args.copy())
	g.noteAsk(KeptAsk(keptInstance, name.copy(), types = args.map(i64(it))))
	mangle = g.askInstance(fnd, sub)   # made by the backend: the declaration is its site
	g.noteInstanceAsked(fnd, mangle)
	mangle

# the builtins whose runtime function has another name
builtinRenamed = [("exit", "exitWith")]

# the runtime function a builtin is, "" when it is none
fn builtinRtName(nm str):
	if builtinAt(nm) < 0: return ""
	renamed = pairedName(builtinRenamed, nm)
	nm.copy() if renamed == "" else renamed

# the second of the pair whose first is `name`, or ""
fn pairedName(pairs (str, str)[], name str):
	for (first, second) in pairs:
		if first == name: return second.copy()
	""
