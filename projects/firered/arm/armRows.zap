# long: the table of ARM, a row an instruction form
# ARM (ARMv4T): each class of the ARM7TDMI's manual, those that share bits with data processing
# before it (the multiplies, the swap and the halfword transfers sit in its gaps). The second
# operand of data processing is an immediate turned, a register shifted by an immediate or one
# shifted by a register: a row each. A row is its bits, `=`, its template (decode.zap).

armTable = r"""
cccc 0001 0010 1111 1111 1111 0001 mmmm = bx<c:cond> r<m>
cccc 0000 000S dddd ---- ssss 1001 mmmm = mul<S?s><c:cond> r<d>, r<m>, r<s>
cccc 0000 001S dddd nnnn ssss 1001 mmmm = mla<S?s><c:cond> r<d>, r<m>, r<s>, r<n>
cccc 0000 1UAS hhhh llll ssss 1001 mmmm = <UA@umull,umlal,smull,smlal><S?s><c:cond> r<l>, r<h>, r<m>, r<s>
cccc 0001 0B00 nnnn dddd 0000 1001 mmmm = swp<B?b><c:cond> r<d>, r<m>, [r<n>]
cccc 000- ---- ---- ---- ---- 1001 ---- = undefined
cccc 0001 U1W1 nnnn dddd hhhh 1SH1 llll = ldr<SH@,h,sb,sh><c:cond> r<d>, [r<n>, #<U?|-><hl>]<W?!>
cccc 0000 U1W1 nnnn dddd hhhh 1SH1 llll = ldr<SH@,h,sb,sh><c:cond> r<d>, [r<n>], #<U?|-><hl>
cccc 0001 U0W1 nnnn dddd 0000 1SH1 mmmm = ldr<SH@,h,sb,sh><c:cond> r<d>, [r<n>, <U?|->r<m>]<W?!>
cccc 0000 U0W1 nnnn dddd 0000 1SH1 mmmm = ldr<SH@,h,sb,sh><c:cond> r<d>, [r<n>], <U?|->r<m>
cccc 0001 U1W0 nnnn dddd hhhh 1011 llll = strh<c:cond> r<d>, [r<n>, #<U?|-><hl>]<W?!>
cccc 0000 U1W0 nnnn dddd hhhh 1011 llll = strh<c:cond> r<d>, [r<n>], #<U?|-><hl>
cccc 0001 U0W0 nnnn dddd 0000 1011 mmmm = strh<c:cond> r<d>, [r<n>, <U?|->r<m>]<W?!>
cccc 0000 U0W0 nnnn dddd 0000 1011 mmmm = strh<c:cond> r<d>, [r<n>], <U?|->r<m>
cccc 000- ---- ---- ---- ---- 1--1 ---- = undefined
cccc 0001 0P00 1111 dddd 0000 0000 0000 = mrs<c:cond> r<d>, <P@cpsr,spsr>
cccc 0001 0P10 ffff 1111 0000 0000 mmmm = msr<c:cond> <P@cpsr,spsr>_<f:psrmask>, r<m>
cccc 0011 0P10 ffff 1111 rrrr iiiiiiii = msr<c:cond> <P@cpsr,spsr>_<f:psrmask>, <ri:rotimm>
cccc 0010 oooS nnnn dddd rrrr iiiiiiii = <o@and,eor,sub,rsb,add,adc,sbc,rsc><S?s><c:cond> r<d>, r<n>, <ri:rotimm>
cccc 0000 oooS nnnn dddd iiiii tt0 mmmm = <o@and,eor,sub,rsb,add,adc,sbc,rsc><S?s><c:cond> r<d>, r<n>, r<m><ti:shift>
cccc 0000 oooS nnnn dddd ssss 0tt1 mmmm = <o@and,eor,sub,rsb,add,adc,sbc,rsc><S?s><c:cond> r<d>, r<n>, r<m><ts:regshift>
cccc 0011 1o0S nnnn dddd rrrr iiiiiiii = <o@orr,bic><S?s><c:cond> r<d>, r<n>, <ri:rotimm>
cccc 0001 1o0S nnnn dddd iiiii tt0 mmmm = <o@orr,bic><S?s><c:cond> r<d>, r<n>, r<m><ti:shift>
cccc 0001 1o0S nnnn dddd ssss 0tt1 mmmm = <o@orr,bic><S?s><c:cond> r<d>, r<n>, r<m><ts:regshift>
cccc 0011 0oo1 nnnn ---- rrrr iiiiiiii = <o@tst,teq,cmp,cmn><c:cond> r<n>, <ri:rotimm>
cccc 0001 0oo1 nnnn ---- iiiii tt0 mmmm = <o@tst,teq,cmp,cmn><c:cond> r<n>, r<m><ti:shift>
cccc 0001 0oo1 nnnn ---- ssss 0tt1 mmmm = <o@tst,teq,cmp,cmn><c:cond> r<n>, r<m><ts:regshift>
cccc 0011 1o1S ---- dddd rrrr iiiiiiii = <o@mov,mvn><S?s><c:cond> r<d>, <ri:rotimm>
cccc 0001 1o1S ---- dddd iiiii tt0 mmmm = <o@mov,mvn><S?s><c:cond> r<d>, r<m><ti:shift>
cccc 0001 1o1S ---- dddd ssss 0tt1 mmmm = <o@mov,mvn><S?s><c:cond> r<d>, r<m><ts:regshift>
cccc 011- ---- ---- ---- ---- ---1 ---- = undefined
cccc 0101 UBWL nnnn dddd oooooooooooo = <L@str,ldr><B?b><c:cond> r<d>, [r<n>, #<U?|-><o>]<W?!>
cccc 0100 UBWL nnnn dddd oooooooooooo = <L@str,ldr><B?b><c:cond> r<d>, [r<n>], #<U?|-><o>
cccc 0111 UBWL nnnn dddd iiiii tt0 mmmm = <L@str,ldr><B?b><c:cond> r<d>, [r<n>, <U?|->r<m><ti:shift>]<W?!>
cccc 0110 UBWL nnnn dddd iiiii tt0 mmmm = <L@str,ldr><B?b><c:cond> r<d>, [r<n>], <U?|->r<m><ti:shift>
cccc 100P USWL nnnn llllllllllllllll = <L@stm,ldm><UP@da,db,ia,ib><c:cond> r<n><W?!>, {<l:list>}<S?^>
cccc 101L oooooooooooooooooooooooo = b<L?l><c:cond> <o:target4>
cccc 1111 iiiiiiiiiiiiiiiiiiiiiiii = swi<c:cond> #<i:hex>
"""

pub fn armRows() Row[]:
	rowsOf(armTable)
