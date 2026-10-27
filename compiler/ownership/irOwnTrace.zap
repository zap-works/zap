# The ownership checker's trace words and its worked examples (irOwn.zap).

# Under `zap test` (the zaps it starts too) and with ZAP_RUN=irown, a function is verified as
# lowered and after each pass of irSimplify that changed it, which a fault then names; a plain
# build verifies nothing. Each function keeps its own (the passes run on several at once).
type IrOwnCheck:
	everyPass bool = false
	pass str = ""
	fault IrOwnFault? = none
	seconds f64 = 0.0   # spent verifying
	dump str = ""   # with ZAP_RUN=irown, the form as the faulty pass left it

mut irOwnSeconds = 0.0   # every function's verifying

fn irOwnWord():
	TraceWord(
		"irown",
		"the ownership verifier after each pass, and the time it took; a function whose ownership a pass broke: its form as that pass left it"
	)

fn irLoweredWord():
	TraceWord(
		"irlowered",
		"each function's form as lowered and its ownership checked, before the passes (irlowered=name: that function's)"
	)

# whether this zap verifies each pass: started by `zap test`, or asked
fn irOwnEveryPass():
	inTestRun() or irOwnWord().on()

# f its first fault (none: a new function) kept, with the pass after which it showed, when each
# pass is verified
fn irOwnAfter(mut f IrFn, pass str):
	if not f.check.everyPass or f.check.fault != none: return
	start = clockSeconds()
	found = f.irOwnFault()
	f.check.seconds += clockSeconds() - start
	if found != none:
		f.check.pass = pass.copy()
		f.check.fault = found
		if irOwnWord().on():
			f.check.dump = f.irOwnDumpText()

# changed passed through, f verified after pass when it is true
fn irOwnAfterChange(mut f IrFn, pass str, changed bool):
	if changed:
		f.irOwnAfter(pass)
	changed

# f's blocks and instructions on stderr
fn irOwnDump(f IrFn):
	eprint(f.irOwnDumpText().trimmedEnd())

# f's blocks and instructions said once the function settles
fn irSayForm(mut g Gen, f IrFn):
	g.irSay(f.irOwnDumpText().trimmedEnd())

# a trace of the lowering or the ownership check, kept for the thread that settles the function
# (irOwnSettle) to print: a lowering run on another thread prints nothing
fn irSay(mut g Gen, line str):
	g.irSaid.push(line.copy())

# f's blocks and instructions, a line each
fn irOwnDumpText(f IrFn):
	out = []
	for b in 0..f.blocks.len:
		out.push("b{b}:\n")
		insts = f.blocks[b].insts
		for k, inst in insts:
			out.push("  {k}: op {inst.op} dst v{inst.dst} a v{inst.a} b v{inst.b} c v{inst.c} d v{inst.d} imm {inst.imm} cond {inst.cond} size {inst.size} -> {inst.target}/{inst.other} {inst.key}{inst.args} line {inst.line}\n")
	out.join("")

# ---------- examples ----------

# What the verifier says of small forms, one of each fault and some clean ones, a line each
# ("name: verdict"), for compiler/zap.zap's test: a frame slot v0 owning a str, then a case's
# instructions.
pub fn irOwnExamples() str[]:
	out = []
	end = (how i64): IrInst(op = irOwnEnd, a = 0, cond = i32(how))
	out.push(
		irOwnExample("dropped", [IrInst(op = irDrop, a = 0), end(ownDropped), IrInst(op = irRet)])
	)
	out.push(irOwnExample("never consumed", [IrInst(op = irRet)]))
	out.push(
		irOwnExample(
			"moved, then dropped",
			[end(ownMoved), IrInst(op = irDrop, a = 0), end(ownDropped)]
		)
	)
	out.push(
		irOwnExample(
			"moved as it is, then dropped",
			[end(ownMovedAsIs), IrInst(op = irDrop, a = 0)]
		)
	)
	out.push(irOwnExample("consumed twice", [end(ownMovedAsIs), end(ownDropped)]))
	out.push(irOwnExample("begun twice", [IrInst(op = irOwn, a = 0, imm = i64(tyStr))]))
	out.push(
		irOwnExample("read after a move", [end(ownMoved), IrInst(op = irLoad, dst = 1, a = 0)])
	)
	out.push(
		irOwnExample(
			"an address used after a drop",
			[
				IrInst(op = irConst, dst = 1, imm = 8),
				IrInst(op = irAdd, dst = 2, a = 0, b = 1),
				end(ownDropped),
				IrInst(op = irLoad, dst = 3, a = 2)
			]
		)
	)
	for how in [ownMoved, ownDropped]:
		out.push(
			irOwnExample(
				"items used after a {"move" if how == ownMoved else "drop"}",
				[
					IrInst(op = irLoad, dst = 1, a = 0, header = true),
					end(how),
					IrInst(op = irLoad, dst = 2, a = 1)
				]
			)
		)
	# consumed on one path only (block 1), the function returns on both
	f = irOwnExampleFn(
		[IrInst(op = irBranch, a = 0, b = 0, cond = irEq, target = 1, other = 2)]
	)
	f.irBlock()
	f.irBlock()
	f.irEnter(1)
	f.irAppend(end(ownMoved))
	f.irAppend(IrInst(op = irRet))
	f.irEnter(2)
	f.irAppend(IrInst(op = irRet))
	out.push("consumed on one path: {f.irOwnVerdict()}")
	# a pass that loses the drop, named
	g = irOwnExampleFn([end(ownDropped), IrInst(op = irRet)])
	g.check = IrOwnCheck(everyPass = true)
	g.irOwnAfter("lowering")
	g.blocks[0].insts.remove(2)
	g.irOwnAfter("a pass that loses the drop")
	out.push("named: {g.check.pass}")
	out

fn irOwnExample(name str, insts IrInst[]):
	"{name}: {irOwnExampleFn(insts).irOwnVerdict()}"

# a frame slot v0 owning a str, then insts (their vregs from v1 on)
fn irOwnExampleFn(insts IrInst[]):
	f = newIrFn()
	f.irAppend(IrInst(op = irFrameSlot, dst = f.irVreg(irInt), imm = 24))
	f.irAppend(IrInst(op = irOwn, a = 0, imm = i64(tyStr)))
	for inst in insts:
		while inst.dst >= f.classes.len:
			f.irVreg(irInt)
		f.irAppend(inst.copy())
	f

fn irOwnVerdict(f IrFn):
	if f.irOwnFault() is fault: "{fault.what} at b{fault.block}:{fault.inst}" else: "clean"

# ---------- borrows: a place changed while a name that borrows it is still used ----------
