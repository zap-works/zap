# The table read by the one decoder.

pub type Decoder:
	rows Row[]   # by opcode
	assembler Assembler

	# The instruction at `at` (bank << 16 | pc) whose bytes start at `off` in `bytes`, read in the
	# widths; bytes past the end read as 0.
	pub fn decode(bytes u8[], off i64, at i64, w Widths) Instr:
		r = rows[bytes[off]]
		size = 1 + operandSize(r.mode, w)
		value = 0
		for k in 1..size:
			b = i64(bytes[off + k]) if off + k < bytes.len else 0
			value |= b << (8 * (k - 1))
		Instr(
			at,
			opcode = r.opcode,
			name = r.name.copy(),
			mode = r.mode.copy(),
			value,
			size,
			widths = w
		)

pub fn newDecoder() Decoder:
	rows = opcodeRows()
	Decoder(rows, assembler = newAssembler(rows))
