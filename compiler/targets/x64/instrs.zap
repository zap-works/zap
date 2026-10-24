# Instructions beyond x64.zap's: moves and copies through the frame, SSE and VEX encodings, loop
# alignment, and stores into a destination.

alias tys = g.c.types

# A destination for a value: kind 0 = [rbp + disp + off], kind 1 = [[rbp + disp] + off], kind 2 = discard.
type Dest:
	kind i64
	disp i64
	off i64

fn frameDest(disp i64):
	Dest(kind = 0, disp, off = 0)

fn destAt(d Dest, off i64):
	Dest(..d, off = d.off + off)

fn leaRaxRbp(mut g Gen, disp i64):
	g.a.em2(0x48, 0x8D)   # lea rax, [rbp+disp]
	g.a.emRbp(0, disp)

fn loadRcxFromRbp(mut g Gen, disp i64):
	g.a.em2(0x48, 0x8B)   # mov rcx, [rbp+disp]
	g.a.emRbp(1, disp)

fn addRcxImm(mut g Gen, v i64):
	if v != 0:
		g.a.em3(0x48, 0x81, 0xC1)   # add rcx, imm32
		g.a.emit32(v)

fn addRaxImm(mut g Gen, v i64):
	if v != 0:
		g.a.em2(0x48, 0x05)   # add rax, imm32
		g.a.emit32(v)

fn subRsp(mut g Gen, n i64):
	if n != 0:
		g.a.em3(0x48, 0x81, 0xEC)   # sub rsp, imm32
		g.a.emit32(n)

# copies n bytes from [rax] to [rcx]: up to unrolledCopyMost bytes as unrolled 8-byte moves
# through rdx (rep movsb costs some thirty cycles to start, and far more when its source was just
# written), longer copies with rep movsb (rsi, rdi, rcx)
fn copyBytes(mut g Gen, n i64):
	if n <= 0: return
	if n <= unrolledCopyMost:
		off = 0
		# (word by word: a value just written by words is read back as it was written, its
		# stores forwarded to the loads, which a 16-byte load spanning two cannot)
		while off + 8 <= n:
			g.movRdxIndirect(0x50, off)   # mov rdx, [rax+off]
			g.movRdxIndirect(0x51, off)   # mov [rcx+off], rdx
			off += 8
		if off + 4 <= n:
			g.a.em1(0x8B)   # mov edx, [rax+off]
			g.modRmDisp(0x50, off)
			g.a.em1(0x89)   # mov [rcx+off], edx
			g.modRmDisp(0x51, off)
			off += 4
		while off < n:
			g.a.em2(0x0F, 0xB6)   # movzx edx, byte [rax+off]
			g.modRmDisp(0x50, off)
			g.a.em1(0x88)   # mov [rcx+off], dl
			g.modRmDisp(0x51, off)
			off += 1
		return
	g.keepRsiRdi(false)   # they may hold locals
	g.a.em3(0x48, 0x89, 0xC6)   # mov rsi, rax
	g.a.em3(0x48, 0x89, 0xCF)   # mov rdi, rcx
	g.a.em3(0x48, 0xC7, 0xC1)   # mov rcx, n
	g.a.emit32(n)
	g.a.em2(0xF3, 0xA4)   # rep movsb
	g.keepRsiRdi(true)

unrolledCopyMost = 512

# mov rdx, [rax+off] (modrm 0x50) or mov [rcx+off], rdx (modrm 0x51)
fn movRdxIndirect(mut g Gen, modrm i64, off i64):
	g.a.em2(0x48, 0x8B if modrm == 0x50 else 0x89)
	g.modRmDisp(modrm, off)

# a modrm of a byte's displacement (mod 01) and its displacement, one of four bytes past 127
fn modRmDisp(mut g Gen, modrm i64, off i64):
	if off > 127:
		g.a.em1(modrm + 0x40)
		g.a.emit32(off)
	else:
		g.a.em2(modrm, off)

# __memcpy with a runtime length (rcx = n, rsi = source, rdi = destination): lengths under
# 64 copy 8 bytes at a time then byte by byte; longer ones use rep movsb
fn genMemcpyInline(mut g Gen):
	big = g.a.asmNewLabel()
	loop8 = g.a.asmNewLabel()
	tail = g.a.asmNewLabel()
	done = g.a.asmNewLabel()
	g.a.em4(0x48, 0x83, 0xF9, 0x40)   # cmp rcx, 64
	g.a.jccLabel(0x83, big)
	g.a.asmPlace(loop8)
	g.a.em4(0x48, 0x83, 0xF9, 0x08)   # cmp rcx, 8
	g.a.jccLabel(0x82, tail)
	g.a.em3(0x48, 0x8B, 0x16)   # mov rdx, [rsi]
	g.a.em3(0x48, 0x89, 0x17)   # mov [rdi], rdx
	g.a.em4(0x48, 0x83, 0xC6, 0x08)   # add rsi, 8
	g.a.em4(0x48, 0x83, 0xC7, 0x08)   # add rdi, 8
	g.a.em4(0x48, 0x83, 0xE9, 0x08)   # sub rcx, 8
	g.a.jmpLabel(loop8)
	g.a.asmPlace(tail)
	# the last 0 to 7 bytes: 4, 2 and 1 at a time, forward as the rest
	no4 = g.a.asmNewLabel()
	no2 = g.a.asmNewLabel()
	g.copyTailStep(4, [0x8B, 0x16], [0x89, 0x17], no4)   # mov edx, [rsi]; mov [rdi], edx
	g.copyTailStep(2, [0x0F, 0xB7, 0x16], [0x66, 0x89, 0x17], no2)   # movzx edx, word [rsi]; mov [rdi], dx
	g.a.em3(0xF6, 0xC1, 0x01)   # test cl, 1
	g.a.jccLabel(0x84, done)
	g.a.em3(0x0F, 0xB6, 0x16)   # movzx edx, byte [rsi]
	g.a.em2(0x88, 0x17)   # mov [rdi], dl
	g.a.jmpLabel(done)
	g.a.asmPlace(big)
	g.a.em2(0xF3, 0xA4)   # rep movsb
	g.a.asmPlace(done)

# one step of a copy's tail when bit n of cl is set: the load into edx, the store from it, both
# pointers n bytes on; skip is placed after it
fn copyTailStep(mut g Gen, n i64, load i64[], store i64[], skip i64):
	g.a.em3(0xF6, 0xC1, n)   # test cl, n
	g.a.jccLabel(0x84, skip)
	g.a.emN(load)
	g.a.emN(store)
	g.a.em4(0x48, 0x83, 0xC6, n)   # add rsi, n
	g.a.em4(0x48, 0x83, 0xC7, n)   # add rdi, n
	g.a.asmPlace(skip)

# the scale bits of a power-of-two stride up to 8, else -1
fn scaleBitsOf(stride i64):
	if stride == 1: return 0
	if stride == 2: return 1
	if stride == 4: return 2
	if stride == 8: return 3
	-1

# [REX] op1 [op2] modrm(11): an instruction on register reg and register rm
fn regOp(mut g Gen, rexW bool, op1 i64, op2 i64, reg i64, rm i64):
	rex = 0x40
	if rexW:
		rex |= 8
	if reg >= 8:
		rex |= 4
	if rm >= 8:
		rex |= 1
	if rex != 0x40:
		g.a.em1(rex)
	g.a.em1(op1)
	if op2 >= 0:
		g.a.em1(op2)
	g.a.em1(0xC0 | (reg & 7) << 3 | (rm & 7))

# The top of a loop placed at a 32-byte boundary (the processor fetches code 32 bytes at a time),
# padded with as few NOPs as fit (run once, as the loop is entered; a jump to the top just before
# them is dropped): where a hot loop starts no longer depends on the code before it. asmRelax pads
# it again where the code lands; the padding written here is never empty, so the top is past it
# wherever that is.
fn placeLoopTop(mut g Gen, top i64):
	g.a.asmDropJumpTo(top)
	pad = 32 - g.a.code.len % 32
	g.a.padAt.push(g.a.code.len)
	g.a.padLen.push(pad)
	nopsInto(g.a.code, pad)
	g.a.asmPlace(top)

# stores the 8-byte word in rax into the destination (tags, pointers, lengths)
fn storeWord(mut g Gen, d Dest):
	if d.kind == 2: return
	if d.kind == 0:
		g.a.storeRaxToRbp(d.disp + d.off)
		return
	g.loadRcxFromRbp(d.disp)
	g.a.memOp(true, 0x89, -1, 0, 1, -1, d.off)   # mov [rcx+off], rax

fn storeWordImm(mut g Gen, d Dest, v i64):
	if d.kind == 2: return
	g.a.movRaxImm(v)
	g.storeWord(d)

fn truncTo(mut g Gen, t TypeId):
	if g.tyK(t) != tInt: return
	g.truncBits(tys[t].bits, tys[t].isSigned)

# rax cut to its low bits, sign- or zero-extended
fn truncBits(mut g Gen, bits i64, signed bool):
	if bits == 64: return
	if signed:
		if bits == 32:
			g.a.em3(0x48, 0x63, 0xC0)
		elif bits == 16:
			g.a.em4(0x48, 0x0F, 0xBF, 0xC0)
		else:
			g.a.em4(0x48, 0x0F, 0xBE, 0xC0)
	else:
		if bits == 32:
			g.a.em2(0x89, 0xC0)
		elif bits == 16:
			g.a.em3(0x0F, 0xB7, 0xC0)
		else:
			g.a.em3(0x0F, 0xB6, 0xC0)

# whether v fits an instruction's 32-bit immediate (sign-extended)
fn fitsImm32(v i64):
	v >= -2_147_483_648 and v <= 2_147_483_647

# the three-byte VEX prefix of a 256-bit packed-double instruction (map 0F, pp 66, L 1):
# reg is the modrm.reg register, vvvv the first source, rm the modrm.rm register (or 0 for
# a memory operand)
# the three-byte VEX prefix: opcode map (1 0F, 2 0F38, 3 0F3A), pp (0 none, 1 66, 2 F3, 3 F2),
# W, L (0 for 128 bits, 1 for 256), the register fields (R and B from reg and rm, inverted)
# and the extra source vvvv (inverted)
# an AVX instruction was emitted: the function needs vzeroupper before it returns, and so does
# the code until the upper halves are clean again
fn usesAvx(mut g Gen):
	g.f.avxUsed = true
	g.avxDirty = true
