# long: the dispatch, a line an operation
# An instruction that is no jump written as Zap: each operation's function, or a note that the
# translation (or Zap) lacks it.

pub fn emitInstr(mut e Emitter, i Instr):
	if i.op in [.Ssy, .Pbk, .Pcnt]: return   # flow.zap reads their targets
	e.openGuard(i)
	match i.op:
		Fadd: e.emitFadd(i)
		Fmul: e.emitFmul(i)
		Ffma: e.emitFfma(i)
		Fmnmx: e.emitFmnmx(i)
		Mufu: e.emitMufu(i)
		Rro: e.emitRro(i)
		Fsetp: e.emitFsetp(i)
		Fset: e.emitFset(i)
		Fcmp: e.emitFcmp(i)
		F2i: e.emitF2i(i)
		I2f: e.emitI2f(i)
		F2f: e.emitF2f(i)
		Iadd: e.emitIadd(i)
		Iadd3: e.emitIadd3(i)
		Iscadd: e.emitIscadd(i)
		Xmad: e.emitXmad(i)
		Shl: e.emitShl(i)
		Shr: e.emitShr(i)
		ShfL, ShfR: e.emitShf(i)
		Lop: e.emitLop(i)
		Lop3: e.emitLop3(i)
		Bfe: e.emitBfe(i)
		Bfi: e.emitBfi(i)
		Popc: e.emitPopc(i)
		Flo: e.emitFlo(i)
		I2i: e.emitI2i(i)
		Isetp: e.emitIsetp(i)
		Iset: e.emitIset(i)
		Icmp: e.emitIcmp(i)
		Imnmx: e.emitImnmx(i)
		Sel: e.emitSel(i)
		Mov: e.emitMov(i)
		Psetp: e.emitPsetp(i)
		Pset: e.emitPset(i)
		P2r: e.emitP2r(i)
		R2p: e.emitR2p(i)
		Ald: e.emitAld(i)
		Ast: e.emitAst(i)
		Ipa: e.emitIpa(i)
		Ldc: e.emitLdc(i)
		Ldl, Stl, Lds, Sts: e.emitLoadStore(i)
		S2r: e.emitS2r(i)
		Bar: e.emitBar(i)
		Texs: e.emitTexs(i)
		Tlds: e.emitTlds(i)
		Tex: e.emitTex(i)
		Tld: e.emitTld(i)
		Txq: e.emitTxq(i)
		Nop, Membar, Depbar: pass
		Dadd, Dmul, Dfma, Dmnmx, Dset, Dsetp: e.lack(
			i,
			"f64 (Zap's GPU code has no f64)",
			[i.rd, i.rd + 1]
		)
		Ldg, Stg, Ld, St, Atom, AtomCas, Red: e.lack(
			i,
			"global memory (Zap has bound storage buffers, no addresses)",
			[i.rd]
		)
		Tld4, Tld4s: e.lack(i, "a gather (Zap has none)", [i.rd])
		Suld, Sust, Sured, Suatom, SuatomCas: e.lack(
			i,
			"an image load or store (Zap has none)",
			[i.rd]
		)
		Tmml: e.lack(i, "a level-of-detail query (Zap has none)", [i.rd])
		Txd: e.lack(i, "a sample with gradients (Zap has none)", [i.rd])
		_: e.lack(i, "not translated", [])
	e.closeGuard(i)
