# The standard input (`stdin`), read as a stream from the console's buffer (coreTerminal.zap).

# The standard input, read as a stream: `stdin.line()`, `stdin.all()`, `stdin.text(n)`,
# `stdin.until(b)`.
pub type Input:
	handle i64

	# the next line of standard input without its line break; none at the end of the input. The
	# buffer is searched for the line break and the line copied a run at a time
	fn line() str?:
		if console.inEof or (console.inPos >= console.inLen and not stdinFill()): return none
		base = __ld64(__addr(console.inBuf)) + console.inPos
		first = byteIndex(__strof(base, console.inLen - console.inPos, 0), 10, 0)
		if first >= 0:
			# the whole line in the buffer (the usual case): one block, one copy
			n = first - 1 if first > 0 and __ld8(base + first - 1) == 13 else first
			out = strNew(n)
			__memcpy(sPtr(out), base, n)
			console.inPos += first + 1
			return out
		text u8[] = []
		loop:
			avail = __strof(
				__ld64(__addr(console.inBuf)) + console.inPos,
				console.inLen - console.inPos,
				0
			)
			at = byteIndex(avail, 10, 0)
			if at >= 0:
				text.reserve(text.len + at + 1)   # one block, the NUL's byte too (no growth step by step)
				text.extend(console.inBuf[console.inPos..console.inPos + at])
				console.inPos += at + 1
				break
			text.extend(console.inBuf[console.inPos..console.inLen])
			console.inPos = console.inLen
			if not stdinFill():
				break   # the input ends without a line break
		if text.len > 0 and text[len - 1] == '\r':
			_ = text.pop()
		str(move text)

	# standard input up to the byte b, left unread (the next read starts with it), or to its end;
	# none when it is already over. A FASTA record is `stdin.until('>')` after its header's line.
	# What the buffer holds is taken first; then the system reads straight into the text's room, a
	# megabyte at a time, and the bytes past b go back to the buffer.
	fn until(b u8) str?:
		if console.inEof or (console.inPos >= console.inLen and not stdinFill()): return none
		out u8[] = []
		avail = __strof(
			__ld64(__addr(console.inBuf)) + console.inPos,
			console.inLen - console.inPos,
			0
		)
		at = byteIndex(avail, i64(b), 0)
		if at >= 0:
			out.extend(console.inBuf[console.inPos..console.inPos + at])
			console.inPos += at
			return str(move out)
		out.extend(console.inBuf[console.inPos..console.inLen])
		console.inPos = console.inLen
		if console.inGiven:
			console.inEof = true   # a test's input ends where its text does
			return str(move out)
		flushStdout()   # a prompt must be visible before the wait
		loop:
			have = out.len
			chunk = 1_048_576   # (what follows b is copied back: a megabyte at most)
			out.reserve(have + chunk)
			room u8[] = []   # a window on the room past the text
			__st64(__addr(room), __ld64(__addr(out)) + have)
			__st64(__addr(room) + 8, chunk)
			got = readSome(stdinHandle, room, chunk)
			if got <= 0:
				console.inEof = true
				break
			found = byteIndex(__strof(__ld64(__addr(out)) + have, got, 0), i64(b), 0)
			if found >= 0:
				# the bytes from b on are the buffer's again
				console.inBuf = room[found..got].copy()
				console.inPos = 0
				console.inLen = got - found
				__st64(__addr(out) + 8, have + found)
				break
			__st64(__addr(out) + 8, have + got)
		str(move out)

	# n bytes of standard input as text (fewer when it ends first), or none when it is already over
	fn text(n i64) str?:
		out u8[] = []
		out.reserve(n)
		more = true
		while more and out.len < n:
			ch = stdinByte()
			if ch < 0:
				more = false
			else:
				out.push(u8(ch))
		if out.len == 0 and n > 0: return none
		str(move out)

	# The rest of standard input as one string: what the line buffer still holds, then the data.
	# When stdin is a file its size is known and the result's buffer is allocated once and read
	# into directly; a pipe is read 64 KB at a time into a growing buffer.
	fn all() str:
		if console.inGiven:
			rest = str(console.inBuf[console.inPos..console.inLen].copy())
			console.inPos = console.inLen
			console.inEof = true
			return rest
		flushStdout()
		h = handle
		held i64 = 0
		if not console.inEof and console.inPos < console.inLen:
			held = console.inLen - console.inPos
		known = fileSize(h)
		if known > 0 and held == 0:
			# a file: mapped, its pages faulted in on every processor at once (a page fault per
			# 4 KB, in parallel, costs less than the kernel's copy of the whole file); the text is
			# the view itself, never freed (a str that owns no block)
			mapping = CreateFileMappingA(h, 0, 2, 0, 0, 0)
			if mapping != 0:
				view = MapViewOfFile(mapping, 4, 0, 0, 0)
				if view != 0:
					parts = cpuCount()
					per = (known + parts - 1) / parts
					touched = (0..parts).parallel().map(k:
						lo = k * per
						hi = (lo + per).min(known)
						acc i64 = 0
						q = lo
						while q < hi:
							acc += __ld8(view + q)
							q += 4096
						acc
					)
					if touched.len > 0:
						console.inEof = true
						return __strof(view, known, 0)
		if known > 0:
			total = fileLeft(h) + held   # what the line buffer took is no longer in the file
			buf = zeroBytes(total)
			for i in 0..held:
				buf[i] = console.inBuf[console.inPos + i]
			console.inPos = console.inLen
			n = held
			if not console.inEof:
				n = readFully(h, buf, held)
				console.inEof = n < total
			buf.truncate(n)
			return str(move buf)
		buf u8[] = []
		if held > 0:
			buf.extend(console.inBuf[console.inPos..console.inLen])
			console.inPos = console.inLen
		if not console.inEof:
			readRest(h, buf)
			console.inEof = true
		str(move buf)

# the program's standard input
pub stdin = Input(handle = stdinHandle)

fn stdinFill() bool:
	if console.inGiven:
		console.inEof = true   # a test's input ends where its text does
		return false
	flushStdout()   # a prompt must be visible before the wait
	if console.inBuf.len == 0:
		console.inBuf = zeroBytes(stdinBufSize)
	got = readSome(stdinHandle, console.inBuf, stdinBufSize)
	if got <= 0:
		console.inEof = true
		return false
	console.inLen = got
	console.inPos = 0
	true

fn stdinByte() i64:
	if console.inEof: return -1
	if console.inPos >= console.inLen:
		if not stdinFill(): return -1
	b = console.inBuf[console.inPos]
	console.inPos += 1
	i64(b)
