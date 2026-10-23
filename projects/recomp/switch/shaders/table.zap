# long: the opcode table, a line an encoding
# Maxwell's encodings: an instruction's top 16 bits against a pattern of 1s, 0s and don't-cares
# (-), the most specific pattern winning (the order of yuzu's maxwell.inc and Ryujinx's
# InstTable). An instruction's operand B comes in forms: a register (Reg), a constant buffer
# word (Cbuf), a 19-bit immediate (Imm), a 32-bit one (Imm32: the *32I encodings); with a third
# source, B a register and C a constant (Rc) or B a constant and C a register (Cr). Bindless:
# a texture instruction whose handle is in a register.

pub type Op:
	Unknown
	Al2p
	Ald
	Ast
	AtomCas
	Atom
	AtomsCas
	Atoms
	B2r
	Bar
	Bfe
	Bfi
	Bpt
	Bra
	Brk
	Brx
	Cal
	Cctl
	Cctll
	Cont
	Cs2r
	Cset
	Csetp
	Dadd
	Depbar
	Dfma
	Dmnmx
	Dmul
	Dset
	Dsetp
	Exit
	F2f
	F2i
	Fadd
	Fchk
	Fcmp
	Ffma
	Flo
	Fmnmx
	Fmul
	Fset
	Fsetp
	Fswzadd
	Getcrsptr
	Getlmembase
	Hadd2
	Hfma2
	Hmul2
	Hset2
	Hsetp2
	I2f
	I2i
	Iadd
	Iadd3
	Icmp
	Ide
	Idp
	Imad
	Imadsp
	Imnmx
	Imul
	Ipa
	Isberd
	Iscadd
	Iset
	Isetp
	Jcal
	Jmp
	Jmx
	Kil
	Ld
	Ldc
	Ldg
	Ldl
	Lds
	LeaHi
	LeaLo
	Lepc
	Longjmp
	Lop
	Lop3
	Membar
	Mov
	Mufu
	Nop
	Out
	P2r
	Pbk
	Pcnt
	Pexit
	Pixld
	Plongjmp
	Popc
	Pret
	Prmt
	Pset
	Psetp
	R2b
	R2p
	Ram
	Red
	Ret
	Rro
	Rtt
	S2r
	Sam
	Sel
	Setcrsptr
	Setlmembase
	ShfL
	ShfR
	Shfl
	Shl
	Shr
	Ssy
	St
	Stg
	Stl
	Stp
	Sts
	Suatom
	SuatomCas
	Suld
	Sured
	Sust
	Sync
	Tex
	Texs
	Tld
	Tld4
	Tld4s
	Tlds
	Tmml
	Txa
	Txd
	Txq
	Vabsdiff
	Vabsdiff4
	Vadd
	Vmad
	Vmnmx
	Vote
	VoteVtg
	Vset
	Vsetp
	Vshl
	Vshr
	Xmad

pub type Form:
	None
	Reg
	Cbuf
	Imm
	Imm32
	Rc
	Cr
	Bindless

# (operation, form, pattern of bits 63..48)
encodings = [
	(Op.Al2p, Form.None, "1110 1111 1010 0---"),
	(Op.Ald, Form.None, "1110 1111 1101 1---"),
	(Op.Ast, Form.None, "1110 1111 1111 0---"),
	(Op.AtomCas, Form.None, "1110 1110 1111 ----"),
	(Op.Atom, Form.None, "1110 1101 ---- ----"),
	(Op.AtomsCas, Form.None, "1110 1110 ---- ----"),
	(Op.Atoms, Form.None, "1110 1100 ---- ----"),
	(Op.B2r, Form.None, "1111 0000 1011 1---"),
	(Op.Bar, Form.None, "1111 0000 1010 1---"),
	(Op.Bfe, Form.Reg, "0101 1100 0000 0---"),
	(Op.Bfe, Form.Cbuf, "0100 1100 0000 0---"),
	(Op.Bfe, Form.Imm, "0011 100- 0000 0---"),
	(Op.Bfi, Form.Reg, "0101 1011 1111 0---"),
	(Op.Bfi, Form.Rc, "0101 0011 1111 0---"),
	(Op.Bfi, Form.Cr, "0100 1011 1111 0---"),
	(Op.Bfi, Form.Imm, "0011 011- 1111 0---"),
	(Op.Bpt, Form.None, "1110 0011 1010 ----"),
	(Op.Bra, Form.None, "1110 0010 0100 ----"),
	(Op.Brk, Form.None, "1110 0011 0100 ----"),
	(Op.Brx, Form.None, "1110 0010 0101 ----"),
	(Op.Cal, Form.None, "1110 0010 0110 ----"),
	(Op.Cctl, Form.None, "1110 1111 011- ----"),
	(Op.Cctll, Form.None, "1110 1111 100- ----"),
	(Op.Cont, Form.None, "1110 0011 0101 ----"),
	(Op.Cs2r, Form.None, "0101 0000 1100 1---"),
	(Op.Cset, Form.None, "0101 0000 1001 1---"),
	(Op.Csetp, Form.None, "0101 0000 1010 0---"),
	(Op.Dadd, Form.Reg, "0101 1100 0111 0---"),
	(Op.Dadd, Form.Cbuf, "0100 1100 0111 0---"),
	(Op.Dadd, Form.Imm, "0011 100- 0111 0---"),
	(Op.Depbar, Form.None, "1111 0000 1111 0---"),
	(Op.Dfma, Form.Reg, "0101 1011 0111 ----"),
	(Op.Dfma, Form.Rc, "0101 0011 0111 ----"),
	(Op.Dfma, Form.Cr, "0100 1011 0111 ----"),
	(Op.Dfma, Form.Imm, "0011 011- 0111 ----"),
	(Op.Dmnmx, Form.Reg, "0101 1100 0101 0---"),
	(Op.Dmnmx, Form.Cbuf, "0100 1100 0101 0---"),
	(Op.Dmnmx, Form.Imm, "0011 100- 0101 0---"),
	(Op.Dmul, Form.Reg, "0101 1100 1000 0---"),
	(Op.Dmul, Form.Cbuf, "0100 1100 1000 0---"),
	(Op.Dmul, Form.Imm, "0011 100- 1000 0---"),
	(Op.Dset, Form.Reg, "0101 1001 0--- ----"),
	(Op.Dset, Form.Cbuf, "0100 1001 0--- ----"),
	(Op.Dset, Form.Imm, "0011 001- 0--- ----"),
	(Op.Dsetp, Form.Reg, "0101 1011 1000 ----"),
	(Op.Dsetp, Form.Cbuf, "0100 1011 1000 ----"),
	(Op.Dsetp, Form.Imm, "0011 011- 1000 ----"),
	(Op.Exit, Form.None, "1110 0011 0000 ----"),
	(Op.F2f, Form.Reg, "0101 1100 1010 1---"),
	(Op.F2f, Form.Cbuf, "0100 1100 1010 1---"),
	(Op.F2f, Form.Imm, "0011 100- 1010 1---"),
	(Op.F2i, Form.Reg, "0101 1100 1011 0---"),
	(Op.F2i, Form.Cbuf, "0100 1100 1011 0---"),
	(Op.F2i, Form.Imm, "0011 100- 1011 0---"),
	(Op.Fadd, Form.Reg, "0101 1100 0101 1---"),
	(Op.Fadd, Form.Cbuf, "0100 1100 0101 1---"),
	(Op.Fadd, Form.Imm, "0011 100- 0101 1---"),
	(Op.Fadd, Form.Imm32, "0000 10-- ---- ----"),
	(Op.Fchk, Form.Reg, "0101 1100 1000 1---"),
	(Op.Fchk, Form.Cbuf, "0100 1100 1000 1---"),
	(Op.Fchk, Form.Imm, "0011 100- 1000 1---"),
	(Op.Fcmp, Form.Reg, "0101 1011 1010 ----"),
	(Op.Fcmp, Form.Rc, "0101 0011 1010 ----"),
	(Op.Fcmp, Form.Cr, "0100 1011 1010 ----"),
	(Op.Fcmp, Form.Imm, "0011 011- 1010 ----"),
	(Op.Ffma, Form.Reg, "0101 1001 1--- ----"),
	(Op.Ffma, Form.Rc, "0101 0001 1--- ----"),
	(Op.Ffma, Form.Cr, "0100 1001 1--- ----"),
	(Op.Ffma, Form.Imm, "0011 001- 1--- ----"),
	(Op.Ffma, Form.Imm32, "0000 11-- ---- ----"),
	(Op.Flo, Form.Reg, "0101 1100 0011 0---"),
	(Op.Flo, Form.Cbuf, "0100 1100 0011 0---"),
	(Op.Flo, Form.Imm, "0011 100- 0011 0---"),
	(Op.Fmnmx, Form.Reg, "0101 1100 0110 0---"),
	(Op.Fmnmx, Form.Cbuf, "0100 1100 0110 0---"),
	(Op.Fmnmx, Form.Imm, "0011 100- 0110 0---"),
	(Op.Fmul, Form.Reg, "0101 1100 0110 1---"),
	(Op.Fmul, Form.Cbuf, "0100 1100 0110 1---"),
	(Op.Fmul, Form.Imm, "0011 100- 0110 1---"),
	(Op.Fmul, Form.Imm32, "0001 1110 ---- ----"),
	(Op.Fset, Form.Reg, "0101 1000 ---- ----"),
	(Op.Fset, Form.Cbuf, "0100 1000 ---- ----"),
	(Op.Fset, Form.Imm, "0011 000- ---- ----"),
	(Op.Fsetp, Form.Reg, "0101 1011 1011 ----"),
	(Op.Fsetp, Form.Cbuf, "0100 1011 1011 ----"),
	(Op.Fsetp, Form.Imm, "0011 011- 1011 ----"),
	(Op.Fswzadd, Form.None, "0101 0000 1111 1---"),
	(Op.Getcrsptr, Form.None, "1110 0010 1100 ----"),
	(Op.Getlmembase, Form.None, "1110 0010 1101 ----"),
	(Op.Hadd2, Form.Reg, "0101 1101 0001 0---"),
	(Op.Hadd2, Form.Cbuf, "0111 101- 1--- ----"),
	(Op.Hadd2, Form.Imm, "0111 101- 0--- ----"),
	(Op.Hadd2, Form.Imm32, "0010 110- ---- ----"),
	(Op.Hfma2, Form.Reg, "0101 1101 0000 0---"),
	(Op.Hfma2, Form.Rc, "0110 0--- 1--- ----"),
	(Op.Hfma2, Form.Cr, "0111 0--- 1--- ----"),
	(Op.Hfma2, Form.Imm, "0111 0--- 0--- ----"),
	(Op.Hfma2, Form.Imm32, "0010 100- ---- ----"),
	(Op.Hmul2, Form.Reg, "0101 1101 0000 1---"),
	(Op.Hmul2, Form.Cbuf, "0111 100- 1--- ----"),
	(Op.Hmul2, Form.Imm, "0111 100- 0--- ----"),
	(Op.Hmul2, Form.Imm32, "0010 101- ---- ----"),
	(Op.Hset2, Form.Reg, "0101 1101 0001 1---"),
	(Op.Hset2, Form.Cbuf, "0111 110- 1--- ----"),
	(Op.Hset2, Form.Imm, "0111 110- 0--- ----"),
	(Op.Hsetp2, Form.Reg, "0101 1101 0010 0---"),
	(Op.Hsetp2, Form.Cbuf, "0111 111- 1--- ----"),
	(Op.Hsetp2, Form.Imm, "0111 111- 0--- ----"),
	(Op.I2f, Form.Reg, "0101 1100 1011 1---"),
	(Op.I2f, Form.Cbuf, "0100 1100 1011 1---"),
	(Op.I2f, Form.Imm, "0011 100- 1011 1---"),
	(Op.I2i, Form.Reg, "0101 1100 1110 0---"),
	(Op.I2i, Form.Cbuf, "0100 1100 1110 0---"),
	(Op.I2i, Form.Imm, "0011 100- 1110 0---"),
	(Op.Iadd, Form.Reg, "0101 1100 0001 0---"),
	(Op.Iadd, Form.Cbuf, "0100 1100 0001 0---"),
	(Op.Iadd, Form.Imm, "0011 100- 0001 0---"),
	(Op.Iadd3, Form.Reg, "0101 1100 1100 ----"),
	(Op.Iadd3, Form.Cbuf, "0100 1100 1100 ----"),
	(Op.Iadd3, Form.Imm, "0011 100- 1100 ----"),
	(Op.Iadd, Form.Imm32, "0001 110- ---- ----"),
	(Op.Icmp, Form.Reg, "0101 1011 0100 ----"),
	(Op.Icmp, Form.Rc, "0101 0011 0100 ----"),
	(Op.Icmp, Form.Cr, "0100 1011 0100 ----"),
	(Op.Icmp, Form.Imm, "0011 011- 0100 ----"),
	(Op.Ide, Form.None, "1110 0011 1001 ----"),
	(Op.Idp, Form.Reg, "0101 0011 1111 1---"),
	(Op.Idp, Form.Imm, "0101 0011 1101 1---"),
	(Op.Imad, Form.Reg, "0101 1010 0--- ----"),
	(Op.Imad, Form.Rc, "0101 0010 0--- ----"),
	(Op.Imad, Form.Cr, "0100 1010 0--- ----"),
	(Op.Imad, Form.Imm, "0011 010- 0--- ----"),
	(Op.Imad, Form.Imm32, "1000 00-- ---- ----"),
	(Op.Imadsp, Form.Reg, "0101 1010 1--- ----"),
	(Op.Imadsp, Form.Rc, "0101 0010 1--- ----"),
	(Op.Imadsp, Form.Cr, "0100 1010 1--- ----"),
	(Op.Imadsp, Form.Imm, "0011 010- 1--- ----"),
	(Op.Imnmx, Form.Reg, "0101 1100 0010 0---"),
	(Op.Imnmx, Form.Cbuf, "0100 1100 0010 0---"),
	(Op.Imnmx, Form.Imm, "0011 100- 0010 0---"),
	(Op.Imul, Form.Reg, "0101 1100 0011 1---"),
	(Op.Imul, Form.Cbuf, "0100 1100 0011 1---"),
	(Op.Imul, Form.Imm, "0011 100- 0011 1---"),
	(Op.Imul, Form.Imm32, "0001 1111 ---- ----"),
	(Op.Ipa, Form.None, "1110 0000 ---- ----"),
	(Op.Isberd, Form.None, "1110 1111 1101 0---"),
	(Op.Iscadd, Form.Reg, "0101 1100 0001 1---"),
	(Op.Iscadd, Form.Cbuf, "0100 1100 0001 1---"),
	(Op.Iscadd, Form.Imm, "0011 100- 0001 1---"),
	(Op.Iscadd, Form.Imm32, "0001 01-- ---- ----"),
	(Op.Iset, Form.Reg, "0101 1011 0101 ----"),
	(Op.Iset, Form.Cbuf, "0100 1011 0101 ----"),
	(Op.Iset, Form.Imm, "0011 011- 0101 ----"),
	(Op.Isetp, Form.Reg, "0101 1011 0110 ----"),
	(Op.Isetp, Form.Cbuf, "0100 1011 0110 ----"),
	(Op.Isetp, Form.Imm, "0011 011- 0110 ----"),
	(Op.Jcal, Form.None, "1110 0010 0010 ----"),
	(Op.Jmp, Form.None, "1110 0010 0001 ----"),
	(Op.Jmx, Form.None, "1110 0010 0000 ----"),
	(Op.Kil, Form.None, "1110 0011 0011 ----"),
	(Op.Ld, Form.None, "100- ---- ---- ----"),
	(Op.Ldc, Form.None, "1110 1111 1001 0---"),
	(Op.Ldg, Form.None, "1110 1110 1101 0---"),
	(Op.Ldl, Form.None, "1110 1111 0100 0---"),
	(Op.Lds, Form.None, "1110 1111 0100 1---"),
	(Op.LeaHi, Form.Reg, "0101 1011 1101 1---"),
	(Op.LeaHi, Form.Cbuf, "0001 10-- ---- ----"),
	(Op.LeaLo, Form.Reg, "0101 1011 1101 0---"),
	(Op.LeaLo, Form.Cbuf, "0100 1011 1101 ----"),
	(Op.LeaLo, Form.Imm, "0011 011- 1101 0---"),
	(Op.Lepc, Form.None, "0101 0000 1101 0---"),
	(Op.Longjmp, Form.None, "1110 0011 0001 ----"),
	(Op.Lop, Form.Reg, "0101 1100 0100 0---"),
	(Op.Lop, Form.Cbuf, "0100 1100 0100 0---"),
	(Op.Lop, Form.Imm, "0011 100- 0100 0---"),
	(Op.Lop3, Form.Reg, "0101 1011 1110 0---"),
	(Op.Lop3, Form.Cbuf, "0000 001- ---- ----"),
	(Op.Lop3, Form.Imm, "0011 11-- ---- ----"),
	(Op.Lop, Form.Imm32, "0000 01-- ---- ----"),
	(Op.Membar, Form.None, "1110 1111 1001 1---"),
	(Op.Mov, Form.Reg, "0101 1100 1001 1---"),
	(Op.Mov, Form.Cbuf, "0100 1100 1001 1---"),
	(Op.Mov, Form.Imm, "0011 100- 1001 1---"),
	(Op.Mov, Form.Imm32, "0000 0001 0000 ----"),
	(Op.Mufu, Form.None, "0101 0000 1000 0---"),
	(Op.Nop, Form.None, "0101 0000 1011 0---"),
	(Op.Out, Form.Reg, "1111 1011 1110 0---"),
	(Op.Out, Form.Cbuf, "1110 1011 1110 0---"),
	(Op.Out, Form.Imm, "1111 011- 1110 0---"),
	(Op.P2r, Form.Reg, "0101 1100 1110 1---"),
	(Op.P2r, Form.Cbuf, "0100 1100 1110 1---"),
	(Op.P2r, Form.Imm, "0011 1000 1110 1---"),
	(Op.Pbk, Form.None, "1110 0010 1010 ----"),
	(Op.Pcnt, Form.None, "1110 0010 1011 ----"),
	(Op.Pexit, Form.None, "1110 0010 0011 ----"),
	(Op.Pixld, Form.None, "1110 1111 1110 1---"),
	(Op.Plongjmp, Form.None, "1110 0010 1000 ----"),
	(Op.Popc, Form.Reg, "0101 1100 0000 1---"),
	(Op.Popc, Form.Cbuf, "0100 1100 0000 1---"),
	(Op.Popc, Form.Imm, "0011 100- 0000 1---"),
	(Op.Pret, Form.None, "1110 0010 0111 ----"),
	(Op.Prmt, Form.Reg, "0101 1011 1100 ----"),
	(Op.Prmt, Form.Rc, "0101 0011 1100 ----"),
	(Op.Prmt, Form.Cr, "0100 1011 1100 ----"),
	(Op.Prmt, Form.Imm, "0011 011- 1100 ----"),
	(Op.Pset, Form.None, "0101 0000 1000 1---"),
	(Op.Psetp, Form.None, "0101 0000 1001 0---"),
	(Op.R2b, Form.None, "1111 0000 1100 0---"),
	(Op.R2p, Form.Reg, "0101 1100 1111 0---"),
	(Op.R2p, Form.Cbuf, "0100 1100 1111 0---"),
	(Op.R2p, Form.Imm, "0011 100- 1111 0---"),
	(Op.Ram, Form.None, "1110 0011 1000 ----"),
	(Op.Red, Form.None, "1110 1011 1111 1---"),
	(Op.Ret, Form.None, "1110 0011 0010 ----"),
	(Op.Rro, Form.Reg, "0101 1100 1001 0---"),
	(Op.Rro, Form.Cbuf, "0100 1100 1001 0---"),
	(Op.Rro, Form.Imm, "0011 100- 1001 0---"),
	(Op.Rtt, Form.None, "1110 0011 0110 ----"),
	(Op.S2r, Form.None, "1111 0000 1100 1---"),
	(Op.Sam, Form.None, "1110 0011 0111 ----"),
	(Op.Sel, Form.Reg, "0101 1100 1010 0---"),
	(Op.Sel, Form.Cbuf, "0100 1100 1010 0---"),
	(Op.Sel, Form.Imm, "0011 100- 1010 0---"),
	(Op.Setcrsptr, Form.None, "1110 0010 1110 ----"),
	(Op.Setlmembase, Form.None, "1110 0010 1111 ----"),
	(Op.ShfL, Form.Reg, "0101 1011 1111 1---"),
	(Op.ShfL, Form.Imm, "0011 011- 1111 1---"),
	(Op.ShfR, Form.Reg, "0101 1100 1111 1---"),
	(Op.ShfR, Form.Imm, "0011 100- 1111 1---"),
	(Op.Shfl, Form.None, "1110 1111 0001 0---"),
	(Op.Shl, Form.Reg, "0101 1100 0100 1---"),
	(Op.Shl, Form.Cbuf, "0100 1100 0100 1---"),
	(Op.Shl, Form.Imm, "0011 100- 0100 1---"),
	(Op.Shr, Form.Reg, "0101 1100 0010 1---"),
	(Op.Shr, Form.Cbuf, "0100 1100 0010 1---"),
	(Op.Shr, Form.Imm, "0011 100- 0010 1---"),
	(Op.Ssy, Form.None, "1110 0010 1001 ----"),
	(Op.St, Form.None, "101- ---- ---- ----"),
	(Op.Stg, Form.None, "1110 1110 1101 1---"),
	(Op.Stl, Form.None, "1110 1111 0101 0---"),
	(Op.Stp, Form.None, "1110 1110 1010 0---"),
	(Op.Sts, Form.None, "1110 1111 0101 1---"),
	(Op.Suatom, Form.None, "1110 1010 0--- ----"),
	(Op.SuatomCas, Form.None, "1110 1010 1--- ----"),
	(Op.Suld, Form.None, "1110 1011 000- ----"),
	(Op.Sured, Form.None, "1110 1011 010- ----"),
	(Op.Sust, Form.None, "1110 1011 001- ----"),
	(Op.Sync, Form.None, "1111 0000 1111 1---"),
	(Op.Tex, Form.None, "1100 0--- ---- ----"),
	(Op.Tex, Form.Bindless, "1101 1110 10-- ----"),
	(Op.Texs, Form.None, "1101 -00- ---- ----"),
	(Op.Tld, Form.None, "1101 1100 ---- ----"),
	(Op.Tld, Form.Bindless, "1101 1101 ---- ----"),
	(Op.Tld4, Form.None, "1100 10-- ---- ----"),
	(Op.Tld4, Form.Bindless, "1101 1110 11-- ----"),
	(Op.Tld4s, Form.None, "1101 1111 -0-- ----"),
	(Op.Tlds, Form.None, "1101 -01- ---- ----"),
	(Op.Tmml, Form.None, "1101 1111 0101 1---"),
	(Op.Tmml, Form.Bindless, "1101 1111 0110 0---"),
	(Op.Txa, Form.None, "1101 1111 0100 0---"),
	(Op.Txd, Form.None, "1101 1110 00-- ----"),
	(Op.Txd, Form.Bindless, "1101 1110 01-- ----"),
	(Op.Txq, Form.None, "1101 1111 0100 1---"),
	(Op.Txq, Form.Bindless, "1101 1111 0101 0---"),
	(Op.Vabsdiff, Form.None, "0101 0100 ---- ----"),
	(Op.Vabsdiff4, Form.None, "0101 0000 0--- ----"),
	(Op.Vadd, Form.None, "0010 00-- ---- ----"),
	(Op.Vmad, Form.None, "0101 1111 ---- ----"),
	(Op.Vmnmx, Form.None, "0011 101- ---- ----"),
	(Op.Vote, Form.None, "0101 0000 1101 1---"),
	(Op.VoteVtg, Form.None, "0101 0000 1110 0---"),
	(Op.Vset, Form.None, "0100 000- ---- ----"),
	(Op.Vsetp, Form.None, "0101 0000 1111 0---"),
	(Op.Vshl, Form.None, "0101 0111 ---- ----"),
	(Op.Vshr, Form.None, "0101 0110 ---- ----"),
	(Op.Xmad, Form.Reg, "0101 1011 00-- ----"),
	(Op.Xmad, Form.Rc, "0101 0001 0--- ----"),
	(Op.Xmad, Form.Cr, "0100 111- ---- ----"),
	(Op.Xmad, Form.Imm, "0011 011- 00-- ----")
]

pub type Encoding:
	op Op
	form Form
	mask i64
	value i64

# the encodings, the most specific (most bits fixed) first
fn sortedEncodings():
	out = []
	for (op, form, pattern) in encodings:
		mask = 0
		value = 0
		for c in pattern:
			if c == ' ': continue
			mask = mask << 1 | (0 if c == '-' else 1)
			value = value << 1 | (1 if c == '1' else 0)
		out.push(Encoding(op, form, mask, value))
	out.sortBy(-.mask.bitCount())
	out

# Every value of the top 16 bits mapped to its encoding's index in `known` (-1 for none).
pub type OpTable:
	known Encoding[]
	index i64[]

pub fn newTable() OpTable:
	known = sortedEncodings()
	index = fill(65_536, -1)
	for top in 0..65536:
		for k, e in known:
			if top & e.mask == e.value:
				index[top] = k
				break
	OpTable(known, index)

# The encoding of an instruction word, Unknown when none matches.
pub fn encodingOf(t OpTable, w i64) Encoding:
	k = t.index[(w >> 48) & 0xFFFF]
	t.known[k] if k >= 0 else Encoding(op = .Unknown, form = .None, mask = 0, value = 0)
